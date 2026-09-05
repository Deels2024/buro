import asyncio
import hashlib
import json
import logging
import signal
from datetime import timedelta
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.config import settings
from app.db.models import Listing, MatchCandidate, MediaObject, Notification, WebhookDelivery
from app.db.session import SessionLocal
from app.services.ai import ai_service
from app.services.cache import enqueue, redis
from app.services.matching import distance_km, score_candidate
from app.services.media_safety import clean_photo
from app.services.storage import storage
from app.services.webhooks import create_deliveries, deliver, enqueue_deliveries

logger = logging.getLogger(__name__)


async def process_media(media_id: UUID) -> None:
    async with SessionLocal() as db:
        media = await db.get(MediaObject, media_id)
        if not media or media.status in {"ready", "rejected", "blocked"}:
            return
        actual_hash = await asyncio.to_thread(storage.sha256, media.object_key)
        if actual_hash != media.sha256:
            media.status = "rejected"
            media.moderation_labels = ["checksum_mismatch"]
            await db.commit()
            return
        if media.mime_type.startswith("image/"):
            try:
                content = await asyncio.to_thread(storage.read_bytes, media.object_key)
                clean, width, height = await asyncio.to_thread(clean_photo, content, media.mime_type)
            except (ValueError, OSError, Warning):
                media.status = "rejected"
                media.moderation_labels = ["invalid_image"]
                await db.commit()
                return
            old_key = media.object_key
            safe_key = storage.make_key(media.owner_id, "photo", media.mime_type, media.purpose)
            await asyncio.to_thread(storage.write_bytes, safe_key, clean, media.mime_type)
            media.object_key = safe_key
            media.sha256 = hashlib.sha256(clean).hexdigest()
            media.size_bytes = len(clean)
            media.width, media.height = width, height
            await db.commit()
            await asyncio.to_thread(storage.delete, old_key)
            url = storage.presign_download(media.object_key, internal=True)
            media.embedding = await ai_service.image_embedding(url)
        media.status = "ready"
        await db.commit()
        if media.listing_id:
            await enqueue("match_listing", {"listing_id": str(media.listing_id)})


async def match_listing(listing_id: UUID) -> None:
    async with SessionLocal() as db:
        source = await db.scalar(
            select(Listing).where(Listing.id == listing_id).options(selectinload(Listing.media))
        )
        if not source or source.status != "active" or source.moderation_status not in {"approved", "auto_approved"}:
            return
        candidates = list(
            await db.scalars(
                select(Listing)
                .where(
                    Listing.kind != source.kind,
                    Listing.status == "active",
                    Listing.moderation_status.in_(["approved", "auto_approved"]),
                    Listing.event_at >= source.event_at - timedelta(days=90),
                    Listing.event_at <= source.event_at + timedelta(days=90),
                )
                .options(selectinload(Listing.media))
                .limit(1000)
            )
        )
        source_embedding = next(
            (list(item.embedding) for item in source.media if item.embedding is not None), None
        )
        delivery_ids = []
        for candidate in candidates:
            candidate_embedding = next(
                (list(item.embedding) for item in candidate.media if item.embedding is not None), None
            )
            distance = distance_km(
                source.approx_latitude,
                source.approx_longitude,
                candidate.approx_latitude,
                candidate.approx_longitude,
            )
            score, factors = score_candidate(
                source_tags=[*source.tags, *source.public_features],
                candidate_tags=[*candidate.tags, *candidate.public_features],
                source_date=source.event_at,
                candidate_date=candidate.event_at,
                distance=distance,
                source_embedding=source_embedding,
                candidate_embedding=candidate_embedding,
                same_category=source.category == candidate.category,
            )
            if score < 45:
                continue
            pairs = ((source, candidate), (candidate, source))
            for pair_source, pair_candidate in pairs:
                existing = await db.scalar(
                    select(MatchCandidate).where(
                        MatchCandidate.source_listing_id == pair_source.id,
                        MatchCandidate.candidate_listing_id == pair_candidate.id,
                    )
                )
                is_new = existing is None
                if existing:
                    existing.score = score
                    existing.factors = factors
                else:
                    db.add(
                        MatchCandidate(
                            source_listing_id=pair_source.id,
                            candidate_listing_id=pair_candidate.id,
                            score=score,
                            factors=factors,
                        )
                    )
                if is_new and score >= 80:
                    db.add(
                        Notification(
                            user_id=pair_source.owner_id,
                            kind="new_match",
                            title=f"Новое совпадение · {round(score)}%",
                            body=f"Возможно, это «{pair_candidate.title}».",
                            data={
                                "listing_id": str(pair_source.id),
                                "candidate_id": str(pair_candidate.id),
                            },
                        )
                        )
                    delivery_ids.extend(
                        await create_deliveries(
                            db,
                            organization_id=pair_source.organization_id,
                            event_type="match.created",
                            payload={
                                "listing_id": str(pair_source.id),
                                "candidate_listing_id": str(pair_candidate.id),
                                "score": score,
                            },
                        )
                    )
        await db.commit()
        await enqueue_deliveries(delivery_ids)


async def deliver_webhook(delivery_id: UUID) -> None:
    async with SessionLocal() as db:
        await deliver(db, delivery_id)
        record = await db.get(WebhookDelivery, delivery_id)
        if record and record.status == "retrying":
            await enqueue("deliver_webhook", {"delivery_id": str(delivery_id)})


HANDLERS = {
    "process_media": lambda payload: process_media(UUID(payload["media_id"])),
    "match_listing": lambda payload: match_listing(UUID(payload["listing_id"])),
    "deliver_webhook": lambda payload: deliver_webhook(UUID(payload["delivery_id"])),
}


async def process_job(raw: str) -> None:
    """Quarantine malformed messages and acknowledge queue transitions atomically."""
    destination = None
    replacement = raw
    try:
        job = json.loads(raw)
        if not isinstance(job, dict) or not isinstance(job.get("name"), str):
            raise ValueError("Invalid job envelope")
        if not isinstance(job.get("payload"), dict):
            raise ValueError("Invalid job payload")
        attempts = job.get("attempts", 0)
        if type(attempts) is not int or not 0 <= attempts < 3:
            raise ValueError("Invalid job attempts")
        handler = HANDLERS.get(job["name"])
        if handler is None:
            raise ValueError("Unknown job handler")
    except (ValueError, TypeError):
        destination = "bureau:jobs:dead"
    else:
        try:
            async with asyncio.timeout(300):
                await handler(job["payload"])
        except Exception:
            logger.exception("Job failed: %s", job["name"])
            job["attempts"] = attempts + 1
            destination = "bureau:jobs" if job["attempts"] < 3 else "bureau:jobs:dead"
            replacement = json.dumps(job)
    # Cancellation before this transaction leaves the task in processing for
    # recovery. Retry insertion and removal must succeed together.
    async with redis.pipeline(transaction=True) as pipe:
        if destination:
            pipe.lpush(destination, replacement)
        pipe.lrem("bureau:jobs:processing", 1, raw)
        await pipe.execute()


async def run_worker() -> None:
    logger.info("Bureau worker started")
    # A killed predecessor can retain its lease until TTL. Stay alive while
    # waiting; repeated crash/restart cycles cause Compose to fail activation.
    lease = redis.lock("bureau:worker:lease", timeout=120, blocking_timeout=130)
    if not await lease.acquire():
        raise RuntimeError("Another worker owns the processing queue")
    worker_id = str(uuid4())
    try:
        # Only the lease holder can recover tasks left by the previous process.
        while await redis.rpoplpush("bureau:jobs:processing", "bureau:jobs"):
            pass

        async def heartbeat() -> None:
            while True:
                await lease.extend(120, replace_ttl=True)
                await redis.set("bureau:worker:heartbeat", f"{settings.release_sha}:{worker_id}", ex=60)
                await asyncio.sleep(15)

        async def consume() -> None:
            while True:
                raw = await redis.brpoplpush("bureau:jobs", "bureau:jobs:processing", timeout=15)
                if not raw:
                    continue
                await process_job(raw)
        async with asyncio.TaskGroup() as group:
            group.create_task(heartbeat())
            group.create_task(consume())
    finally:
        if await lease.owned():
            await redis.delete("bureau:worker:heartbeat")
            await lease.release()
        await redis.aclose()


async def main() -> None:
    task = asyncio.create_task(run_worker())
    loop = asyncio.get_running_loop()
    loop.add_signal_handler(signal.SIGTERM, task.cancel)
    try:
        await task
    except asyncio.CancelledError:
        # Cancellation unwinds the task group and releases the queue lease.
        pass
    finally:
        loop.remove_signal_handler(signal.SIGTERM)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())
