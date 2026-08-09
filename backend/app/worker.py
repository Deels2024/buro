import asyncio
import json
import logging
from datetime import timedelta
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.db.models import Listing, MatchCandidate, MediaObject, Notification, WebhookDelivery
from app.db.session import SessionLocal
from app.services.ai import ai_service
from app.services.cache import enqueue, redis
from app.services.matching import distance_km, score_candidate
from app.services.storage import storage
from app.services.webhooks import create_deliveries, deliver, enqueue_deliveries

logger = logging.getLogger(__name__)


async def process_media(media_id: UUID) -> None:
    async with SessionLocal() as db:
        media = await db.get(MediaObject, media_id)
        if not media:
            return
        actual_hash = await asyncio.to_thread(storage.sha256, media.object_key)
        if actual_hash != media.sha256:
            media.status = "rejected"
            media.moderation_labels = ["checksum_mismatch"]
            await db.commit()
            return
        if media.mime_type.startswith("image/"):
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
        if not source or source.status != "active":
            return
        candidates = list(
            await db.scalars(
                select(Listing)
                .where(
                    Listing.kind != source.kind,
                    Listing.status == "active",
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


async def run_worker() -> None:
    logger.info("Bureau worker started")
    while True:
        raw = await redis.brpoplpush("bureau:jobs", "bureau:jobs:processing", timeout=30)
        if not raw:
            continue
        job = json.loads(raw)
        handler = HANDLERS.get(job.get("name"))
        if not handler:
            logger.error("Unknown job: %s", job.get("name"))
            await redis.lrem("bureau:jobs:processing", 1, raw)
            await redis.rpush("bureau:jobs:dead", raw)
            continue
        try:
            await handler(job["payload"])
            await redis.lrem("bureau:jobs:processing", 1, raw)
        except Exception:
            logger.exception("Job failed: %s", job.get("name"))
            await redis.lrem("bureau:jobs:processing", 1, raw)
            job["attempts"] = int(job.get("attempts", 0)) + 1
            target = "bureau:jobs" if job["attempts"] < 3 else "bureau:jobs:dead"
            await redis.rpush(target, json.dumps(job))


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    asyncio.run(run_worker())
