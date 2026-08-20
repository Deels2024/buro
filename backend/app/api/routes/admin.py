from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import func, select

from app.api.deps import DB, AdminUser
from app.db.models import AdCampaign, AdEvent, Claim, Listing, ModerationCase, Organization
from app.schemas import AdCampaignCreate, AdCampaignOut, ModerationDecision
from app.services.audit import add_audit

router = APIRouter()


@router.get("/dashboard")
async def dashboard(db: DB, _: AdminUser) -> dict[str, int]:
    open_cases = await db.scalar(select(func.count(ModerationCase.id)).where(ModerationCase.status == "open"))
    risky_claims = await db.scalar(select(func.count(Claim.id)).where(Claim.risk_score >= 0.6))
    pending_orgs = await db.scalar(select(func.count(Organization.id)).where(Organization.status == "pending"))
    pending_listings = await db.scalar(
        select(func.count(Listing.id)).where(Listing.moderation_status == "pending")
    )
    return {
        "open_cases": open_cases or 0,
        "risky_claims": risky_claims or 0,
        "pending_organizations": pending_orgs or 0,
        "pending_listings": pending_listings or 0,
    }


@router.get("/moderation/listings")
async def listing_queue(
    db: DB,
    _: AdminUser,
    limit: int = Query(default=50, ge=1, le=100),
) -> list[dict]:
    listings = await db.scalars(
        select(Listing)
        .where(Listing.moderation_status == "pending")
        .order_by(Listing.created_at)
        .limit(limit)
    )
    return [
        {
            "id": str(item.id),
            "title": item.title,
            "kind": item.kind,
            "category": item.category,
            "created_at": item.created_at,
        }
        for item in listings
    ]


@router.post("/moderation/listings/{listing_id}")
async def moderate_listing(
    payload: ModerationDecision,
    listing_id: UUID,
    db: DB,
    admin: AdminUser,
) -> dict[str, str]:
    listing = await db.get(Listing, listing_id)
    if not listing:
        raise HTTPException(status_code=404, detail="Публикация не найдена")
    status_map = {
        "approve": "approved",
        "reject": "rejected",
        "block": "blocked",
        "request_changes": "changes_requested",
    }
    listing.moderation_status = status_map[payload.decision]
    if payload.decision == "block":
        listing.status = "blocked"
    db.add(
        ModerationCase(
            entity_type="listing",
            entity_id=listing.id,
            reason=payload.reason[:120],
            status="resolved",
            assigned_to=admin.id,
            resolution=payload.decision,
        )
    )
    add_audit(
        db,
        actor_id=admin.id,
        action="moderation.listing",
        entity_type="listing",
        entity_id=listing.id,
        payload={"decision": payload.decision},
    )
    await db.commit()
    return {"status": listing.moderation_status}


@router.get("/claims/risk")
async def risky_claims(db: DB, _: AdminUser, limit: int = 50) -> list[dict]:
    claims = await db.scalars(
        select(Claim).where(Claim.risk_score >= 0.4).order_by(Claim.risk_score.desc()).limit(min(limit, 100))
    )
    return [
        {
            "id": str(item.id),
            "listing_id": str(item.listing_id),
            "risk_score": item.risk_score,
            "risk_factors": item.risk_factors,
            "status": item.status,
        }
        for item in claims
    ]


@router.get("/disputes")
async def disputes(db: DB, _: AdminUser, limit: int = 50) -> list[dict]:
    cases = await db.scalars(
        select(ModerationCase)
        .where(ModerationCase.entity_type == "claim", ModerationCase.status == "open")
        .order_by(ModerationCase.priority.desc(), ModerationCase.created_at)
        .limit(min(limit, 100))
    )
    return [
        {
            "id": str(case.id),
            "claim_id": str(case.entity_id),
            "reason": case.reason,
            "priority": case.priority,
            "created_at": case.created_at,
        }
        for case in cases
    ]


@router.post("/disputes/{case_id}/resolve")
async def resolve_dispute(
    payload: ModerationDecision,
    case_id: UUID,
    db: DB,
    admin: AdminUser,
) -> dict[str, str]:
    case = await db.get(ModerationCase, case_id)
    if not case or case.entity_type != "claim" or case.status != "open":
        raise HTTPException(status_code=404, detail="Спор не найден")
    claim = await db.get(Claim, case.entity_id)
    if not claim:
        raise HTTPException(status_code=404, detail="Заявление не найдено")
    case.status = "resolved"
    case.assigned_to = admin.id
    case.resolution = payload.reason
    if payload.decision == "approve":
        claim.status = "approved"
    elif payload.decision in {"reject", "block"}:
        claim.status = "rejected"
    else:
        claim.status = "needs_more_info"
    claim.decision_reason = payload.reason
    claim.decided_by = admin.id
    claim.decided_at = datetime.now(UTC)
    add_audit(
        db,
        actor_id=admin.id,
        action="dispute.resolve",
        entity_type="claim",
        entity_id=claim.id,
        payload={"decision": payload.decision},
    )
    await db.commit()
    return {"status": case.status, "claim_status": claim.status}


@router.post("/organizations/{organization_id}/verify")
async def verify_organization(
    payload: ModerationDecision,
    organization_id: UUID,
    db: DB,
    admin: AdminUser,
) -> dict[str, str]:
    organization = await db.get(Organization, organization_id)
    if not organization:
        raise HTTPException(status_code=404, detail="Организация не найдена")
    organization.status = "verified" if payload.decision == "approve" else "rejected"
    organization.verification_data = {
        **organization.verification_data,
        "decision": payload.decision,
        "reason": payload.reason,
        "decided_at": datetime.now(UTC).isoformat(),
    }
    add_audit(
        db,
        actor_id=admin.id,
        action="organization.verify",
        entity_type="organization",
        entity_id=organization.id,
        payload={"decision": payload.decision},
    )
    await db.commit()
    return {"status": organization.status}


@router.post("/ads", response_model=AdCampaignOut, status_code=201)
async def create_ad_campaign(payload: AdCampaignCreate, db: DB, _: AdminUser) -> AdCampaign:
    if payload.ends_at <= payload.starts_at:
        raise HTTPException(status_code=422, detail="Дата окончания должна быть позже даты начала")
    campaign = AdCampaign(
        advertiser_name=payload.advertiser_name,
        title=payload.title,
        body=payload.body,
        action_label=payload.action_label,
        action_url=str(payload.action_url),
        placements=payload.placements,
        targeting=payload.targeting,
        erid=payload.erid,
        age_rating=payload.age_rating,
        starts_at=payload.starts_at,
        ends_at=payload.ends_at,
        daily_budget_kopecks=payload.daily_budget_kopecks,
        status="active",
    )
    db.add(campaign)
    await db.commit()
    await db.refresh(campaign)
    return campaign


@router.get("/ads", response_model=list[AdCampaignOut])
async def ad_campaigns(
    db: DB,
    _: AdminUser,
    status: str | None = Query(default=None, max_length=24),
    limit: int = Query(default=100, ge=1, le=100),
) -> list[AdCampaign]:
    filters = [AdCampaign.status == status] if status else []
    result = await db.scalars(
        select(AdCampaign)
        .where(*filters)
        .order_by(AdCampaign.created_at.desc())
        .limit(limit)
    )
    return list(result)


@router.patch("/ads/{campaign_id}/status", response_model=AdCampaignOut)
async def update_ad_status(
    campaign_id: UUID,
    status: str,
    db: DB,
    _: AdminUser,
) -> AdCampaign:
    if status not in {"draft", "active", "paused", "ended"}:
        raise HTTPException(status_code=422, detail="Недопустимый статус")
    campaign = await db.get(AdCampaign, campaign_id)
    if not campaign:
        raise HTTPException(status_code=404, detail="Кампания не найдена")
    campaign.status = status
    await db.commit()
    await db.refresh(campaign)
    return campaign


@router.get("/ads/{campaign_id}/stats")
async def ad_stats(campaign_id: UUID, db: DB, _: AdminUser) -> dict:
    campaign = await db.get(AdCampaign, campaign_id)
    if not campaign:
        raise HTTPException(status_code=404, detail="Кампания не найдена")
    rows = await db.execute(
        select(AdEvent.event_type, func.count(AdEvent.id))
        .where(AdEvent.campaign_id == campaign_id)
        .group_by(AdEvent.event_type)
    )
    metrics = dict(rows.all())
    impressions = metrics.get("impression", 0)
    clicks = metrics.get("click", 0)
    return {
        "campaign_id": str(campaign.id),
        "impressions": impressions,
        "clicks": clicks,
        "ctr": round(clicks / impressions * 100, 2) if impressions else 0,
    }
