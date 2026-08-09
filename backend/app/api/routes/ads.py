from datetime import UTC, datetime

from fastapi import APIRouter, HTTPException, Query, Request
from sqlalchemy import select

from app.api.deps import DB
from app.core.security import hash_secret
from app.db.models import AdCampaign, AdEvent
from app.schemas import AdCampaignOut, AdEventCreate
from app.services.cache import rate_limit

router = APIRouter()
ALLOWED_PLACEMENTS = {"home_feed", "search_results"}


@router.get("/current", response_model=AdCampaignOut | None)
async def current_ad(
    db: DB,
    placement: str = Query(pattern="^(home_feed|search_results)$"),
) -> AdCampaign | None:
    now = datetime.now(UTC)
    campaigns = await db.scalars(
        select(AdCampaign).where(
            AdCampaign.status == "active",
            AdCampaign.starts_at <= now,
            AdCampaign.ends_at >= now,
        )
    )
    return next((campaign for campaign in campaigns if placement in campaign.placements), None)


@router.post("/events", status_code=202)
async def track_ad_event(payload: AdEventCreate, db: DB, request: Request) -> dict[str, str]:
    if payload.placement not in ALLOWED_PLACEMENTS:
        raise HTTPException(status_code=422, detail="Реклама запрещена в этом сценарии")
    campaign = await db.get(AdCampaign, payload.campaign_id)
    if not campaign or payload.placement not in campaign.placements:
        raise HTTPException(status_code=404, detail="Кампания не найдена")
    client_hash = hash_secret(request.client.host if request.client else "unknown")[:24]
    if not await rate_limit(f"rate:ad:{client_hash}", 300, 3600):
        raise HTTPException(status_code=429, detail="Слишком много событий")
    anonymous_hash = None
    if payload.tracking_consent and payload.anonymous_id:
        anonymous_hash = hash_secret(payload.anonymous_id)
    db.add(
        AdEvent(
            campaign_id=campaign.id,
            event_type=payload.event_type,
            placement=payload.placement,
            anonymous_id_hash=anonymous_hash,
            context=payload.context if payload.tracking_consent else {},
        )
    )
    await db.commit()
    return {"status": "accepted"}
