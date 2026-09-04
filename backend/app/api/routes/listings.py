from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query
from sqlalchemy import func, or_, select
from sqlalchemy.orm import selectinload

from app.services.matching import normalized_factors
from app.api.deps import DB, CurrentUser
from app.core.security import encrypt_json
from app.db.models import Branch, Listing, MatchCandidate, MediaObject, OrganizationMember
from app.schemas import (
    AIDescribeRequest,
    AIItemDescription,
    AIPhotoSearchRequest,
    ListingCreate,
    ListingOut,
    ListingPage,
    ListingUpdate,
    MatchDecision,
    MatchOut,
    PhotoSearchOut,
)
from app.services.ai import ai_service
from app.services.categories import category_values
from app.services.cache import enqueue, rate_limit
from app.services.serializers import listing_out
from app.services.storage import storage
from app.services.traffic import record_event
from app.services.webhooks import create_deliveries, enqueue_deliveries

router = APIRouter()


async def _get_listing(db: DB, listing_id: UUID) -> Listing:
    listing = await db.scalar(
        select(Listing).where(Listing.id == listing_id).options(selectinload(Listing.media))
    )
    if not listing:
        raise HTTPException(status_code=404, detail="Публикация не найдена")
    return listing


async def _can_manage_organization(db: DB, user_id: UUID, organization_id: UUID) -> bool:
    member = await db.scalar(
        select(OrganizationMember).where(
            OrganizationMember.organization_id == organization_id,
            OrganizationMember.user_id == user_id,
            OrganizationMember.status == "active",
            OrganizationMember.role.in_(["owner", "manager", "operator"]),
        )
    )
    return member is not None


@router.post("", response_model=ListingOut, status_code=201)
async def create_listing(payload: ListingCreate, db: DB, user: CurrentUser) -> ListingOut:
    if payload.organization_id and not await _can_manage_organization(db, user.id, payload.organization_id):
        raise HTTPException(status_code=403, detail="Нет доступа к организации")
    if payload.publish and payload.kind == "found" and not payload.media_ids:
        raise HTTPException(status_code=422, detail="Для публикации нужна хотя бы одна фотография")

    if payload.branch_id:
        branch = await db.get(Branch, payload.branch_id)
        if not branch or branch.organization_id != payload.organization_id or not branch.active:
            raise HTTPException(status_code=422, detail="Филиал не относится к организации")
    now = datetime.now(UTC)
    listing = Listing(
        owner_id=user.id,
        organization_id=payload.organization_id,
        branch_id=payload.branch_id,
        kind=payload.kind,
        status="active" if payload.publish else "draft",
        title=payload.title.strip(),
        description=payload.description.strip(),
        category=payload.category.strip(),
        tags=payload.tags,
        public_features=payload.public_features,
        hidden_features_cipher=encrypt_json(payload.hidden_features) if payload.hidden_features else None,
        event_at=payload.event_at,
        public_region=payload.location.region.strip(),
        approx_latitude=round(payload.location.latitude, 2) if payload.location.latitude is not None else None,
        approx_longitude=round(payload.location.longitude, 2) if payload.location.longitude is not None else None,
        exact_location_cipher=encrypt_json(payload.location.model_dump(mode="json")),
        storage_code=payload.storage_code,
        published_at=now if payload.publish else None,
        moderation_status="auto_approved" if not payload.publish else "pending",
    )
    db.add(listing)
    await db.flush()
    if payload.media_ids:
        media = list(
            await db.scalars(
                select(MediaObject).where(
                    MediaObject.id.in_(payload.media_ids),
                    MediaObject.owner_id == user.id,
                    MediaObject.listing_id.is_(None),
                    MediaObject.purpose == "listing",
                    MediaObject.mime_type.like("image/%"),
                    MediaObject.status.in_(["ready", "processing"]),
                )
            )
        )
        if len(media) != len(set(payload.media_ids)):
            raise HTTPException(status_code=422, detail="Часть медиа недоступна")
        for item in media:
            item.listing_id = listing.id
    delivery_ids = await create_deliveries(
        db,
        organization_id=listing.organization_id,
        event_type="listing.created",
        payload={"listing_id": str(listing.id), "kind": listing.kind, "status": listing.status},
    )
    await db.commit()
    await enqueue_deliveries(delivery_ids)
    listing = await _get_listing(db, listing.id)
    if payload.publish:
        await record_event("publication")
        await enqueue("match_listing", {"listing_id": str(listing.id)})
    return listing_out(listing, private=True)


@router.get("", response_model=ListingPage)
async def search_listings(
    db: DB,
    query: str | None = Query(default=None, max_length=200),
    kind: str | None = Query(default=None, pattern="^(lost|found)$"),
    category: str | None = Query(default=None, max_length=80),
    region: str | None = Query(default=None, max_length=180),
    since: datetime | None = None,
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> ListingPage:
    filters = [
        Listing.status == "active",
        Listing.moderation_status.in_(["approved", "auto_approved"]),
    ]
    if kind:
        filters.append(Listing.kind == kind)
    if category:
        filters.append(func.lower(Listing.category).in_(category_values(category)))
    if region:
        filters.append(Listing.public_region.ilike(f"%{region}%"))
    if since:
        filters.append(Listing.event_at >= since)
    if query:
        term = f"%{query.strip()}%"
        filters.append(or_(Listing.title.ilike(term), Listing.description.ilike(term)))

    total = await db.scalar(select(func.count(Listing.id)).where(*filters)) or 0
    result = await db.scalars(
        select(Listing)
        .where(*filters)
        .options(selectinload(Listing.media))
        .order_by(Listing.published_at.desc())
        .offset(offset)
        .limit(limit)
    )
    return ListingPage(
        items=[listing_out(item) for item in result],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get("/mine", response_model=list[ListingOut])
async def my_listings(db: DB, user: CurrentUser) -> list[ListingOut]:
    result = await db.scalars(
        select(Listing)
        .where(Listing.owner_id == user.id)
        .options(selectinload(Listing.media))
        .order_by(Listing.created_at.desc())
    )
    return [listing_out(item, private=True) for item in result]


@router.get("/{listing_id}", response_model=ListingOut)
async def get_listing(listing_id: UUID, db: DB) -> ListingOut:
    listing = await _get_listing(db, listing_id)
    if listing.status != "active" or listing.moderation_status not in {"approved", "auto_approved"}:
        raise HTTPException(status_code=404, detail="Публикация не найдена")
    return listing_out(listing)


async def _assert_manage(db: DB, user: CurrentUser, listing: Listing) -> None:
    allowed = listing.owner_id == user.id or user.role in {"admin", "moderator"}
    if not allowed and listing.organization_id:
        allowed = await _can_manage_organization(db, user.id, listing.organization_id)
    if not allowed:
        raise HTTPException(status_code=403, detail="Нет доступа к публикации")


@router.get("/{listing_id}/manage", response_model=ListingOut)
async def managed_listing(listing_id: UUID, db: DB, user: CurrentUser) -> ListingOut:
    listing = await _get_listing(db, listing_id)
    await _assert_manage(db, user, listing)
    return listing_out(listing, private=True)


@router.patch("/{listing_id}", response_model=ListingOut)
async def update_listing(payload: ListingUpdate, listing_id: UUID, db: DB, user: CurrentUser) -> ListingOut:
    listing = await _get_listing(db, listing_id)
    await _assert_manage(db, user, listing)
    if listing.status in {"closed", "blocked"} and user.role not in {"admin", "moderator"}:
        raise HTTPException(status_code=409, detail="Закрытую или заблокированную публикацию нельзя изменить")
    data = payload.model_dump(exclude_unset=True, exclude_none=True)
    public_changed = bool(set(data) & {"title", "description", "category", "tags", "public_features", "event_at", "location", "media_ids"})
    was_active = listing.status == "active"
    location = data.pop("location", None)
    hidden_features = data.pop("hidden_features", None)
    media_ids = data.pop("media_ids", None)
    if media_ids is not None:
        media = list(await db.scalars(select(MediaObject).where(
            MediaObject.id.in_(media_ids),
            or_(MediaObject.listing_id == listing.id, (MediaObject.owner_id == user.id) & MediaObject.listing_id.is_(None)),
            MediaObject.purpose == "listing", MediaObject.mime_type.like("image/%"),
            MediaObject.status.in_(["ready", "processing"]),
        )))
        if len(media) != len(set(media_ids)):
            raise HTTPException(status_code=422, detail="Часть фотографий недоступна")
        for old in list(listing.media):
            if old.id not in media_ids:
                old.listing_id = None
        for item in media:
            item.listing_id = listing.id
    else:
        media = list(listing.media)
    if location:
        listing.public_region = location["region"]
        listing.approx_latitude = round(location["latitude"], 2) if location.get("latitude") is not None else None
        listing.approx_longitude = round(location["longitude"], 2) if location.get("longitude") is not None else None
        listing.exact_location_cipher = encrypt_json(location)
    if hidden_features is not None:
        listing.hidden_features_cipher = encrypt_json(hidden_features)
    for key, value in data.items():
        setattr(listing, key, value)
    if listing.status == "active":
        if listing.kind == "found" and not any(item.status in {"ready", "processing"} for item in media):
            raise HTTPException(status_code=422, detail="Для публикации находки нужна фотография")
        listing.published_at = listing.published_at or datetime.now(UTC)
        if public_changed or not was_active:
            listing.moderation_status = "pending"
    if listing.status == "closed":
        listing.closed_at = datetime.now(UTC)
    delivery_ids = await create_deliveries(
        db, organization_id=listing.organization_id, event_type="listing.updated",
        payload={"listing_id": str(listing.id), "status": listing.status},
    )
    await db.commit()
    await enqueue_deliveries(delivery_ids)
    # Refresh the collection after reassigning photo foreign keys.
    await db.refresh(listing, attribute_names=["media"])
    return listing_out(listing, private=True)


@router.post("/ai/describe", response_model=AIItemDescription)
async def describe_with_ai(payload: AIDescribeRequest, db: DB, user: CurrentUser) -> AIItemDescription:
    if not await rate_limit(f"rate:ai:{user.id}", 60, 3600):
        raise HTTPException(status_code=429, detail="Лимит ИИ-запросов исчерпан")
    media = await db.get(MediaObject, payload.media_id)
    if not media or media.owner_id != user.id or not media.mime_type.startswith("image/"):
        raise HTTPException(status_code=404, detail="Фотография не найдена")
    image_url = storage.presign_download(media.object_key)
    return await ai_service.describe_item(image_url, payload.kind, payload.user_hint)


@router.post("/ai/search", response_model=list[PhotoSearchOut])
async def search_by_photo(payload: AIPhotoSearchRequest, db: DB, user: CurrentUser) -> list[PhotoSearchOut]:
    if not await rate_limit(f"rate:photo-search:{user.id}", 120, 3600):
        raise HTTPException(status_code=429, detail="Лимит поиска по фото исчерпан")
    media = await db.get(MediaObject, payload.media_id)
    if not media or media.owner_id != user.id or not media.mime_type.startswith("image/"):
        raise HTTPException(status_code=404, detail="Фотография не найдена")
    if media.embedding is None:
        image_url = storage.presign_download(media.object_key, internal=True)
        media.embedding = await ai_service.image_embedding(image_url)
        if media.embedding is not None:
            await db.commit()
    if media.embedding is None:
        raise HTTPException(status_code=503, detail="Визуальный поиск временно недоступен")

    distance = MediaObject.embedding.cosine_distance(media.embedding).label("distance")
    filters = [
        Listing.status == "active",
        Listing.moderation_status.in_(["approved", "auto_approved"]),
        MediaObject.embedding.is_not(None),
        MediaObject.id != media.id,
    ]
    if payload.target_kind:
        filters.append(Listing.kind == payload.target_kind)
    if payload.category:
        filters.append(func.lower(Listing.category).in_(category_values(payload.category)))
    if payload.region:
        filters.append(Listing.public_region.ilike(f"%{payload.region}%"))
    rows = await db.execute(
        select(Listing, distance)
        .join(MediaObject, MediaObject.listing_id == Listing.id)
        .where(*filters)
        .options(selectinload(Listing.media))
        .order_by(distance)
        .limit(payload.limit * 3)
    )
    output: list[PhotoSearchOut] = []
    seen: set[UUID] = set()
    for listing, raw_distance in rows.all():
        if listing.id in seen:
            continue
        seen.add(listing.id)
        visual_score = round(max(0.0, 1.0 - float(raw_distance)) * 100, 2)
        output.append(PhotoSearchOut(listing=listing_out(listing), visual_score=visual_score))
        if len(output) == payload.limit:
            break
    return output


@router.get("/{listing_id}/matches", response_model=list[MatchOut])
async def matches(listing_id: UUID, db: DB, user: CurrentUser, limit: int = 20) -> list[MatchOut]:
    source = await _get_listing(db, listing_id)
    if source.owner_id != user.id and user.role not in {"admin", "moderator"}:
        raise HTTPException(status_code=403, detail="Нет доступа к совпадениям")
    candidates = list(
        await db.scalars(
            select(MatchCandidate)
            .where(MatchCandidate.source_listing_id == listing_id)
            .order_by(MatchCandidate.score.desc())
            .limit(min(limit, 100))
        )
    )
    output = []
    for candidate in candidates:
        item = await _get_listing(db, candidate.candidate_listing_id)
        if item.status != "active" or item.moderation_status not in {"approved", "auto_approved"}:
            continue
        output.append(
            MatchOut(
                id=candidate.id,
                candidate=listing_out(item),
                score=candidate.score,
                factors=normalized_factors(candidate.factors),
                status=candidate.status,
                created_at=candidate.created_at,
            )
        )
    return output


@router.patch("/{listing_id}/matches/{match_id}", response_model=MatchOut)
async def update_match(
    listing_id: UUID,
    match_id: UUID,
    payload: MatchDecision,
    db: DB,
    user: CurrentUser,
) -> MatchOut:
    source = await _get_listing(db, listing_id)
    if source.owner_id != user.id and user.role not in {"admin", "moderator"}:
        raise HTTPException(status_code=403, detail="Нет доступа к совпадениям")
    match = await db.get(MatchCandidate, match_id)
    if not match or match.source_listing_id != listing_id:
        raise HTTPException(status_code=404, detail="Совпадение не найдено")
    candidate = await _get_listing(db, match.candidate_listing_id)
    if candidate.status != "active" or candidate.moderation_status not in {"approved", "auto_approved"}:
        raise HTTPException(status_code=404, detail="Совпадение недоступно")
    match.status = payload.status
    await db.commit()
    candidate = await _get_listing(db, match.candidate_listing_id)
    return MatchOut(
        id=match.id,
        candidate=listing_out(candidate),
        score=match.score,
        factors=normalized_factors(match.factors),
        status=match.status,
        created_at=match.created_at,
    )


@router.post("/{listing_id}/rematch", status_code=202)
async def rematch(listing_id: UUID, db: DB, user: CurrentUser) -> dict[str, str]:
    listing = await _get_listing(db, listing_id)
    if listing.owner_id != user.id and user.role not in {"admin", "moderator"}:
        raise HTTPException(status_code=403, detail="Нет доступа")
    if listing.event_at < datetime.now(UTC) - timedelta(days=365 * 5):
        raise HTTPException(status_code=422, detail="Слишком старая публикация")
    if not await rate_limit(f"rate:rematch:{listing.id}", 3, 3600):
        raise HTTPException(status_code=429, detail="Повторный поиск уже запущен")
    await enqueue("match_listing", {"listing_id": str(listing.id)})
    return {"status": "queued"}
