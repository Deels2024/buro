import asyncio

from fastapi import APIRouter, HTTPException

from app.api.deps import DB, CurrentUser
from app.core.config import settings
from app.db.models import Listing, MediaObject
from app.schemas import MediaCompleteRequest, MediaOut, MediaPresignOut, MediaPresignRequest
from app.services.cache import enqueue, rate_limit
from app.services.serializers import media_out
from app.services.storage import storage

router = APIRouter()


@router.post("/presign", response_model=MediaPresignOut)
async def presign(payload: MediaPresignRequest, user: CurrentUser) -> MediaPresignOut:
    if not await rate_limit(f"rate:upload:{user.id}", 200, 86400):
        raise HTTPException(status_code=429, detail="Дневной лимит загрузок исчерпан")
    if payload.size_bytes > settings.max_upload_bytes:
        raise HTTPException(status_code=413, detail="Файл слишком большой")
    object_key = storage.make_key(user.id, payload.filename, payload.mime_type, payload.purpose)
    upload_url = storage.presign_upload(object_key, payload.mime_type, payload.size_bytes)
    return MediaPresignOut(
        object_key=object_key,
        upload_url=upload_url,
        required_headers={"Content-Type": payload.mime_type},
        expires_in=settings.s3_presign_ttl_seconds,
    )


@router.post("/complete", response_model=MediaOut)
async def complete(payload: MediaCompleteRequest, db: DB, user: CurrentUser) -> MediaOut:
    expected_prefix = f"{payload.purpose}/{user.id}/"
    if not payload.object_key.startswith(expected_prefix):
        raise HTTPException(status_code=403, detail="Объект не принадлежит пользователю")
    if payload.listing_id:
        listing = await db.get(Listing, payload.listing_id)
        if not listing or listing.owner_id != user.id:
            raise HTTPException(status_code=404, detail="Публикация не найдена")
        if listing.status == "active":
            listing.moderation_status = "pending"
    if payload.size_bytes > settings.max_upload_bytes:
        raise HTTPException(413, "Файл слишком большой")
    try:
        head = await asyncio.to_thread(storage.head, payload.object_key)
    except Exception as exc:
        raise HTTPException(status_code=400, detail="Файл не найден в хранилище") from exc
    actual_size = int(head.get("ContentLength", 0))
    if actual_size != payload.size_bytes:
        raise HTTPException(status_code=400, detail="Размер файла не совпадает")
    if head.get("ContentType") != payload.mime_type:
        raise HTTPException(status_code=400, detail="Тип файла не совпадает")
    media = MediaObject(
        owner_id=user.id,
        listing_id=payload.listing_id,
        purpose=payload.purpose,
        object_key=payload.object_key,
        mime_type=payload.mime_type,
        size_bytes=payload.size_bytes,
        sha256=payload.sha256.lower(),
        width=payload.width,
        height=payload.height,
        duration_seconds=payload.duration_seconds,
        status="processing",
    )
    db.add(media)
    await db.commit()
    await db.refresh(media)
    await enqueue("process_media", {"media_id": str(media.id)})
    return media_out(media)
