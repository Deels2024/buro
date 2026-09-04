import csv
import io
from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import StreamingResponse
from sqlalchemy import String, cast, func, or_, select

from app.api.deps import DB, AdminUser
from app.core.security import decrypt_json, mask_phone
from app.db.models import (
    AuditEvent,
    Claim,
    Handover,
    IntegrationWebhook,
    Listing,
    MatchCandidate,
    Organization,
    SupportTicket,
    SystemSetting,
    User,
    WebhookDelivery,
)
from app.schemas import AdminUserUpdate, SystemSettingUpdate
from app.services.audit import add_audit
from app.services.matching import normalized_factors
from app.services.traffic import traffic_totals

router = APIRouter()


def _window(date_from: datetime | None, date_to: datetime | None) -> tuple[datetime, datetime]:
    end = date_to or datetime.now(UTC)
    start = date_from or end - timedelta(days=30)
    if start >= end:
        raise HTTPException(status_code=422, detail="Начало периода должно быть раньше окончания")
    if end - start > timedelta(days=730):
        raise HTTPException(status_code=422, detail="Максимальный период — 730 дней")
    return start, end


async def _count(db: DB, model_column, *filters) -> int:
    return int(await db.scalar(select(func.count(model_column)).where(*filters)) or 0)


@router.get("/analytics/overview")
async def analytics_overview(
    db: DB,
    _: AdminUser,
    date_from: datetime | None = None,
    date_to: datetime | None = None,
    granularity: str = Query("day", pattern="^(day|week|month)$"),
) -> dict:
    start, end = _window(date_from, date_to)
    listing_filter = (Listing.created_at >= start, Listing.created_at < end)
    claim_filter = (Claim.created_at >= start, Claim.created_at < end)
    handover_filter = (Handover.created_at >= start, Handover.created_at < end)

    users = await _count(db, User.id, User.created_at >= start, User.created_at < end)
    listings = await _count(db, Listing.id, *listing_filter)
    found = await _count(db, Listing.id, *listing_filter, Listing.kind == "found")
    lost = await _count(db, Listing.id, *listing_filter, Listing.kind == "lost")
    matches = await _count(db, MatchCandidate.id, MatchCandidate.created_at >= start, MatchCandidate.created_at < end)
    claims = await _count(db, Claim.id, *claim_filter)
    approved_claims = await _count(db, Claim.id, *claim_filter, Claim.status == "approved")
    returned = await _count(db, Handover.id, *handover_filter, Handover.completed_at.is_not(None))

    bucket = func.date_trunc(granularity, Listing.created_at).label("bucket")
    series_rows = await db.execute(
        select(bucket, Listing.kind, func.count(Listing.id))
        .where(*listing_filter)
        .group_by(bucket, Listing.kind)
        .order_by(bucket)
    )
    series: dict[str, dict] = {}
    for point, kind, count in series_rows.all():
        key = point.isoformat()
        series.setdefault(key, {"date": key, "lost": 0, "found": 0})[kind] = count

    category_rows = await db.execute(
        select(Listing.category, func.count(Listing.id))
        .where(*listing_filter)
        .group_by(Listing.category)
        .order_by(func.count(Listing.id).desc())
        .limit(12)
    )
    region_rows = await db.execute(
        select(Listing.public_region, func.count(Listing.id))
        .where(*listing_filter)
        .group_by(Listing.public_region)
        .order_by(func.count(Listing.id).desc())
        .limit(12)
    )
    support_open = await _count(db, SupportTicket.id, SupportTicket.status.notin_(["resolved", "closed"]))
    pending_webhooks = await _count(db, WebhookDelivery.id, WebhookDelivery.status.in_(["pending", "retrying"]))
    webhook_failures = await _count(db, WebhookDelivery.id, WebhookDelivery.status == "failed")

    return {
        "period": {"from": start, "to": end, "granularity": granularity},
        "kpi": {
            "new_users": users,
            "listings": listings,
            "lost": lost,
            "found": found,
            "matches": matches,
            "claims": claims,
            "approved_claims": approved_claims,
            "returned": returned,
            "return_rate": round(returned / max(found, 1) * 100, 2),
            "claim_approval_rate": round(approved_claims / max(claims, 1) * 100, 2),
        },
        "funnel": [
            {"stage": "Публикации", "value": listings},
            {"stage": "Совпадения", "value": matches},
            {"stage": "Заявления", "value": claims},
            {"stage": "Подтверждены", "value": approved_claims},
            {"stage": "Возвращены", "value": returned},
        ],
        "series": list(series.values()),
        "categories": [{"name": name, "value": count} for name, count in category_rows.all()],
        "regions": [{"name": name, "value": count} for name, count in region_rows.all()],
        "operations": {
            "support_open": support_open,
            "webhook_queue": pending_webhooks,
            "webhook_failures": webhook_failures,
        },
    }


@router.get("/users")
async def users(
    db: DB,
    _: AdminUser,
    query: str | None = Query(None, max_length=120),
    role: str | None = None,
    status: str | None = None,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
) -> dict:
    filters = []
    if query:
        filters.append(User.display_name.ilike(f"%{query.strip()}%"))
    if role:
        filters.append(User.role == role)
    if status:
        filters.append(User.status == status)
    total = await _count(db, User.id, *filters)
    result = await db.scalars(
        select(User).where(*filters).order_by(User.created_at.desc()).offset(offset).limit(limit)
    )
    items = []
    for user in result:
        try:
            phone_masked = mask_phone(decrypt_json(user.phone_cipher)["phone"])
        except (ValueError, TypeError):
            phone_masked = "удалён"
        items.append(
            {
                "id": str(user.id),
                "display_name": user.display_name,
                "phone_masked": phone_masked,
                "role": user.role,
                "status": user.status,
                "admin_2fa_enabled": user.admin_2fa_enabled,
                "verified_at": user.verified_at,
                "last_seen_at": user.last_seen_at,
                "created_at": user.created_at,
            }
        )
    return {"items": items, "total": total, "limit": limit, "offset": offset}


@router.get("/users/{user_id}")
async def user_details(user_id: UUID, db: DB, _: AdminUser) -> dict:
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    return {
        "id": str(user.id),
        "display_name": user.display_name,
        "role": user.role,
        "status": user.status,
        "admin_2fa_enabled": user.admin_2fa_enabled,
        "last_seen_at": user.last_seen_at,
        "created_at": user.created_at,
        "counts": {
            "listings": await _count(db, Listing.id, Listing.owner_id == user.id),
            "claims": await _count(db, Claim.id, Claim.claimant_id == user.id),
            "support_tickets": await _count(db, SupportTicket.id, SupportTicket.user_id == user.id),
        },
    }


@router.patch("/users/{user_id}")
async def update_user(
    user_id: UUID,
    payload: AdminUserUpdate,
    db: DB,
    admin: AdminUser,
) -> dict:
    target = await db.get(User, user_id)
    if not target:
        raise HTTPException(status_code=404, detail="Пользователь не найден")
    if target.id == admin.id and payload.status in {"blocked", "deleted"}:
        raise HTTPException(status_code=409, detail="Нельзя заблокировать собственный аккаунт")
    data = payload.model_dump(exclude_unset=True)
    for key, value in data.items():
        setattr(target, key, value)
    add_audit(
        db,
        actor_id=admin.id,
        action="admin.user.update",
        entity_type="user",
        entity_id=target.id,
        payload=data,
    )
    await db.commit()
    return {"id": str(target.id), "role": target.role, "status": target.status}


@router.get("/organizations")
async def organizations(
    db: DB,
    _: AdminUser,
    query: str | None = Query(None, max_length=240),
    status: str | None = None,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
) -> dict:
    filters = []
    if query:
        term = f"%{query.strip()}%"
        filters.append(or_(Organization.name.ilike(term), Organization.inn.ilike(term)))
    if status:
        filters.append(Organization.status == status)
    total = await _count(db, Organization.id, *filters)
    result = await db.scalars(
        select(Organization).where(*filters).order_by(Organization.created_at.desc()).offset(offset).limit(limit)
    )
    items = []
    for organization in result:
        items.append(
            {
                "id": str(organization.id),
                "name": organization.name,
                "inn": organization.inn,
                "status": organization.status,
                "api_enabled": organization.api_enabled,
                "inventory": await _count(db, Listing.id, Listing.organization_id == organization.id),
                "webhooks": await _count(db, IntegrationWebhook.id, IntegrationWebhook.organization_id == organization.id),
                "created_at": organization.created_at,
            }
        )
    return {"items": items, "total": total, "limit": limit, "offset": offset}


@router.get("/listings")
async def listings(
    db: DB,
    _: AdminUser,
    query: str | None = Query(None, max_length=180),
    kind: str | None = None,
    status: str | None = None,
    moderation_status: str | None = None,
    organization_id: UUID | None = None,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
) -> dict:
    filters = []
    if query:
        term = f"%{query.strip()}%"
        filters.append(or_(Listing.title.ilike(term), Listing.description.ilike(term)))
    if kind:
        filters.append(Listing.kind == kind)
    if status:
        filters.append(Listing.status == status)
    if moderation_status:
        filters.append(Listing.moderation_status == moderation_status)
    if organization_id:
        filters.append(Listing.organization_id == organization_id)
    total = await _count(db, Listing.id, *filters)
    result = await db.scalars(
        select(Listing).where(*filters).order_by(Listing.created_at.desc()).offset(offset).limit(limit)
    )
    return {
        "items": [
            {
                "id": str(item.id),
                "title": item.title,
                "kind": item.kind,
                "category": item.category,
                "region": item.public_region,
                "status": item.status,
                "moderation_status": item.moderation_status,
                "organization_id": str(item.organization_id) if item.organization_id else None,
                "created_at": item.created_at,
            }
            for item in result
        ],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


@router.get("/claims")
async def claims(
    db: DB,
    _: AdminUser,
    status: str | None = None,
    query: str | None = Query(None, max_length=200),
    min_risk: float | None = Query(None, ge=0, le=1),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
) -> dict:
    filters = []
    if query:
        term = f"%{query.strip()}%"
        filters.append(or_(cast(Claim.id, String).ilike(term), Claim.listing_id.in_(select(Listing.id).where(Listing.title.ilike(term)))))
    if status:
        filters.append(Claim.status == status)
    if min_risk is not None:
        filters.append(Claim.risk_score >= min_risk)
    total = await _count(db, Claim.id, *filters)
    result = await db.scalars(
        select(Claim).where(*filters).order_by(Claim.created_at.desc()).offset(offset).limit(limit)
    )
    return {
        "items": [
            {
                "id": str(item.id),
                "listing_id": str(item.listing_id),
                "claimant_id": str(item.claimant_id),
                "status": item.status,
                "risk_score": item.risk_score,
                "risk_factors": item.risk_factors,
                "submitted_at": item.submitted_at,
                "created_at": item.created_at,
            }
            for item in result
        ],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


@router.get("/matches")
async def matches(
    db: DB,
    _: AdminUser,
    status: str | None = None,
    min_score: float = Query(0, ge=0, le=100),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
) -> dict:
    filters = [MatchCandidate.score >= min_score]
    if status:
        filters.append(MatchCandidate.status == status)
    total = await _count(db, MatchCandidate.id, *filters)
    result = await db.scalars(
        select(MatchCandidate)
        .where(*filters)
        .order_by(MatchCandidate.score.desc(), MatchCandidate.created_at.desc())
        .offset(offset)
        .limit(limit)
    )
    return {
        "items": [
            {
                "id": str(item.id),
                "source_listing_id": str(item.source_listing_id),
                "candidate_listing_id": str(item.candidate_listing_id),
                "score": item.score,
                "factors": normalized_factors(item.factors),
                "status": item.status,
                "created_at": item.created_at,
            }
            for item in result
        ],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


@router.get("/handovers")
async def handovers(
    db: DB,
    _: AdminUser,
    completed: bool | None = None,
    method: str | None = None,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
) -> dict:
    filters = []
    if completed is True:
        filters.append(Handover.completed_at.is_not(None))
    if completed is False:
        filters.append(Handover.completed_at.is_(None))
    if method:
        filters.append(Handover.method == method)
    total = await _count(db, Handover.id, *filters)
    result = await db.scalars(
        select(Handover).where(*filters).order_by(Handover.created_at.desc()).offset(offset).limit(limit)
    )
    return {
        "items": [
            {
                "id": str(item.id),
                "claim_id": str(item.claim_id),
                "method": item.method,
                "scheduled_at": item.scheduled_at,
                "holder_confirmed_at": item.holder_confirmed_at,
                "claimant_confirmed_at": item.claimant_confirmed_at,
                "completed_at": item.completed_at,
                "created_at": item.created_at,
            }
            for item in result
        ],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


@router.get("/audit")
async def audit(
    db: DB,
    _: AdminUser,
    actor_id: UUID | None = None,
    action: str | None = Query(None, max_length=80),
    entity_type: str | None = Query(None, max_length=40),
    limit: int = Query(100, ge=1, le=200),
    offset: int = Query(0, ge=0),
) -> dict:
    filters = []
    if actor_id:
        filters.append(AuditEvent.actor_id == actor_id)
    if action:
        filters.append(AuditEvent.action == action)
    if entity_type:
        filters.append(AuditEvent.entity_type == entity_type)
    total = await _count(db, AuditEvent.id, *filters)
    result = await db.scalars(
        select(AuditEvent).where(*filters).order_by(AuditEvent.created_at.desc()).offset(offset).limit(limit)
    )
    return {
        "items": [
            {
                "id": str(item.id),
                "actor_id": str(item.actor_id) if item.actor_id else None,
                "action": item.action,
                "entity_type": item.entity_type,
                "entity_id": str(item.entity_id) if item.entity_id else None,
                "payload": item.payload,
                "created_at": item.created_at,
            }
            for item in result
        ],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


@router.get("/settings")
async def settings_list(db: DB, _: AdminUser) -> list[dict]:
    result = await db.scalars(select(SystemSetting).order_by(SystemSetting.key))
    return [
        {
            "key": item.key,
            "value": item.value,
            "description": item.description,
            "public": item.public,
            "updated_at": item.updated_at,
            "updated_by": str(item.updated_by) if item.updated_by else None,
        }
        for item in result
    ]


@router.put("/settings/{key}")
async def update_setting(
    key: str,
    payload: SystemSettingUpdate,
    db: DB,
    admin: AdminUser,
) -> dict:
    if not key.replace(".", "").replace("_", "").isalnum() or len(key) > 120:
        raise HTTPException(status_code=422, detail="Недопустимый ключ настройки")
    record = await db.scalar(select(SystemSetting).where(SystemSetting.key == key))
    if not record:
        record = SystemSetting(key=key)
        db.add(record)
    record.value = payload.value
    record.description = payload.description
    record.public = payload.public
    record.updated_by = admin.id
    await db.flush()
    add_audit(
        db,
        actor_id=admin.id,
        action="admin.setting.update",
        entity_type="system_setting",
        entity_id=record.id,
        payload={"key": key, "public": payload.public},
    )
    await db.commit()
    return {"key": record.key, "value": record.value, "public": record.public}


@router.get("/exports/overview.csv")
async def overview_csv(
    db: DB,
    _: AdminUser,
    date_from: datetime | None = None,
    date_to: datetime | None = None,
) -> StreamingResponse:
    start, end = _window(date_from, date_to)
    rows = await db.execute(
        select(Listing.kind, Listing.category, Listing.public_region, func.count(Listing.id))
        .where(Listing.created_at >= start, Listing.created_at < end)
        .group_by(Listing.kind, Listing.category, Listing.public_region)
        .order_by(func.count(Listing.id).desc())
    )
    output = io.StringIO()
    output.write("\ufeff")
    writer = csv.writer(output)
    writer.writerow(["Тип", "Категория", "Регион", "Количество"])
    for row in rows.all():
        writer.writerow(row)
    filename = f"bureau-overview-{start.date()}-{end.date()}.csv"
    return StreamingResponse(
        iter([output.getvalue().encode("utf-8")]),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/analytics/traffic")
async def traffic(_: AdminUser, days: int = Query(30, ge=1, le=90)) -> dict:
    return await traffic_totals(days)
