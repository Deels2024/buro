from datetime import UTC, datetime
from uuid import UUID

from fastapi import APIRouter, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.api.deps import DB, CurrentUser
from app.core.security import decrypt_json, encrypt_json, hash_secret, mask_phone, random_token
from app.db.models import Listing, Notification, PushDevice, RefreshToken, SavedListing
from app.schemas import (
    AccountDeleteRequest,
    ListingOut,
    MessageResponse,
    NotificationOut,
    PushDeviceCreate,
    PushDeviceOut,
    SessionOut,
    UserOut,
    UserUpdate,
)
from app.services.serializers import listing_out

router = APIRouter()


def user_out(user: CurrentUser) -> UserOut:
    phone = decrypt_json(user.phone_cipher)["phone"]
    return UserOut(
        id=user.id,
        display_name=user.display_name,
        phone_masked=mask_phone(phone),
        role=user.role,
        status=user.status,
        verified_at=user.verified_at,
        admin_2fa_enabled=user.admin_2fa_enabled,
    )


@router.get("/me", response_model=UserOut)
async def me(user: CurrentUser) -> UserOut:
    return user_out(user)


@router.patch("/me", response_model=UserOut)
async def update_me(payload: UserUpdate, db: DB, user: CurrentUser) -> UserOut:
    user.display_name = payload.display_name.strip()
    user.updated_at = datetime.now(UTC)
    await db.commit()
    return user_out(user)


@router.get("/me/notifications", response_model=list[NotificationOut])
async def notifications(db: DB, user: CurrentUser, limit: int = 50) -> list[Notification]:
    result = await db.scalars(
        select(Notification)
        .where(Notification.user_id == user.id)
        .order_by(Notification.created_at.desc())
        .limit(min(limit, 100))
    )
    return list(result)


@router.put("/me/notifications/read-all", response_model=MessageResponse)
async def read_all_notifications(db: DB, user: CurrentUser) -> MessageResponse:
    now = datetime.now(UTC)
    result = await db.scalars(
        select(Notification).where(Notification.user_id == user.id, Notification.read_at.is_(None))
    )
    for notification in result:
        notification.read_at = now
    await db.commit()
    return MessageResponse(message="Уведомления прочитаны")


@router.put("/me/notifications/{notification_id}/read", response_model=NotificationOut)
async def read_notification(notification_id: UUID, db: DB, user: CurrentUser) -> Notification:
    notification = await db.get(Notification, notification_id)
    if not notification or notification.user_id != user.id:
        raise HTTPException(status_code=404, detail="Уведомление не найдено")
    notification.read_at = notification.read_at or datetime.now(UTC)
    await db.commit()
    await db.refresh(notification)
    return notification


@router.get("/me/devices", response_model=list[PushDeviceOut])
async def devices(db: DB, user: CurrentUser) -> list[PushDevice]:
    result = await db.scalars(
        select(PushDevice).where(PushDevice.user_id == user.id).order_by(PushDevice.updated_at.desc())
    )
    return list(result)


@router.put("/me/devices", response_model=PushDeviceOut)
async def register_device(payload: PushDeviceCreate, db: DB, user: CurrentUser) -> PushDevice:
    token_hash = hash_secret(payload.token)
    device = await db.scalar(
        select(PushDevice).where(PushDevice.platform == payload.platform, PushDevice.token_hash == token_hash)
    )
    now = datetime.now(UTC)
    if not device:
        device = PushDevice(
            user_id=user.id,
            platform=payload.platform,
            token_hash=token_hash,
            token_cipher=encrypt_json({"token": payload.token}),
        )
        db.add(device)
    device.user_id = user.id
    device.device_name = payload.device_name
    device.app_version = payload.app_version
    device.locale = payload.locale
    device.status = "active"
    device.last_seen_at = now
    await db.commit()
    await db.refresh(device)
    return device


@router.delete("/me/devices/{device_id}", status_code=204)
async def unregister_device(device_id: UUID, db: DB, user: CurrentUser) -> None:
    device = await db.get(PushDevice, device_id)
    if device and device.user_id == user.id:
        await db.delete(device)
        await db.commit()


@router.get("/me/sessions", response_model=list[SessionOut])
async def sessions(db: DB, user: CurrentUser) -> list[SessionOut]:
    now = datetime.now(UTC)
    result = await db.scalars(
        select(RefreshToken)
        .where(
            RefreshToken.user_id == user.id,
            RefreshToken.revoked_at.is_(None),
            RefreshToken.expires_at > now,
        )
        .order_by(RefreshToken.created_at.desc())
    )
    return [
        SessionOut(
            id=item.id,
            device_name=item.device_name,
            expires_at=item.expires_at,
            created_at=item.created_at,
        )
        for item in result
    ]


@router.delete("/me/sessions/{session_id}", response_model=MessageResponse)
async def revoke_session(session_id: UUID, db: DB, user: CurrentUser) -> MessageResponse:
    record = await db.get(RefreshToken, session_id)
    if not record or record.user_id != user.id:
        raise HTTPException(status_code=404, detail="Сессия не найдена")
    record.revoked_at = datetime.now(UTC)
    await db.commit()
    return MessageResponse(message="Сессия завершена")


@router.get("/me/saved", response_model=list[ListingOut])
async def saved_listings(db: DB, user: CurrentUser) -> list[ListingOut]:
    result = await db.scalars(
        select(Listing)
        .join(SavedListing, SavedListing.listing_id == Listing.id)
        .where(SavedListing.user_id == user.id, Listing.status == "active")
        .options(selectinload(Listing.media))
        .order_by(SavedListing.created_at.desc())
    )
    return [listing_out(item) for item in result]


@router.put("/me/saved/{listing_id}", response_model=MessageResponse)
async def save_listing(listing_id: UUID, db: DB, user: CurrentUser) -> MessageResponse:
    listing = await db.get(Listing, listing_id)
    if not listing or listing.status != "active":
        raise HTTPException(status_code=404, detail="Публикация не найдена")
    existing = await db.scalar(
        select(SavedListing).where(
            SavedListing.user_id == user.id,
            SavedListing.listing_id == listing_id,
        )
    )
    if not existing:
        db.add(SavedListing(user_id=user.id, listing_id=listing_id))
        await db.commit()
    return MessageResponse(message="Сохранено")


@router.delete("/me/saved/{listing_id}", response_model=MessageResponse)
async def unsave_listing(listing_id: UUID, db: DB, user: CurrentUser) -> MessageResponse:
    existing = await db.scalar(
        select(SavedListing).where(
            SavedListing.user_id == user.id,
            SavedListing.listing_id == listing_id,
        )
    )
    if existing:
        await db.delete(existing)
        await db.commit()
    return MessageResponse(message="Удалено из сохранённого")


@router.delete("/me", response_model=MessageResponse)
async def delete_account(payload: AccountDeleteRequest, db: DB, user: CurrentUser) -> MessageResponse:
    now = datetime.now(UTC)
    user.display_name = "Удалённый пользователь"
    user.phone_hash = hash_secret(random_token(32))
    user.phone_cipher = encrypt_json({"phone": None})
    user.status = "deleted"
    tokens = await db.scalars(
        select(RefreshToken).where(RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None))
    )
    for token in tokens:
        token.revoked_at = now
    listings = await db.scalars(
        select(Listing).where(Listing.owner_id == user.id, Listing.status.in_(["draft", "active", "paused"]))
    )
    for listing in listings:
        listing.status = "closed"
        listing.closed_at = now
    await db.commit()
    return MessageResponse(message="Аккаунт удалён, активные публикации закрыты")
