from unittest.mock import AsyncMock

from sqlalchemy import select
from test_workflows import photo, search_listing
from test_workflows import workflow as workflow

from app import worker
from app.db.models import MatchCandidate, MediaObject, Notification


async def test_improved_existing_match_notifies_once_without_photos(workflow, monkeypatch):
    _, sessions, users, _ = workflow
    monkeypatch.setattr(worker, "SessionLocal", sessions)
    source = await search_listing(sessions, users["claimant"], kind="lost", tags=[], public_features=[])
    candidate = await search_listing(sessions, users["holder"], tags=[], public_features=[])
    async with sessions() as db:
        db.add(MatchCandidate(source_listing_id=source.id, candidate_listing_id=candidate.id,
                              score=55, factors={}))
        await db.commit()
    await worker.match_listing(source.id)
    await worker.match_listing(source.id)
    async with sessions() as db:
        notes = list(await db.scalars(select(Notification)))
        matches = list(await db.scalars(select(MatchCandidate)))
        assert len(notes) == 2 and {n.user_id for n in notes} == {source.owner_id, candidate.owner_id}
        assert len(matches) == 2 and all(match.score >= 80 for match in matches)
        assert all("visual" not in match.factors for match in matches)


async def test_missing_embedding_is_repaired_after_service_recovers(workflow, monkeypatch):
    _, sessions, users, _ = workflow
    monkeypatch.setattr(worker, "SessionLocal", sessions)
    listing = await search_listing(sessions, users["holder"])
    media_id = await photo(sessions, users["holder"])
    from uuid import UUID
    async with sessions() as db:
        media = await db.get(MediaObject, UUID(media_id))
        media.listing_id = listing.id
        await db.commit()
    embedding = [1.0] + [0.0] * 511
    monkeypatch.setattr(worker.ai_service, "image_embedding", AsyncMock(side_effect=[None, embedding]))
    monkeypatch.setattr(worker.storage, "presign_download", lambda *args, **kwargs: "http://minio/test")
    enqueue = AsyncMock()
    monkeypatch.setattr(worker, "enqueue", enqueue)
    await worker.retry_missing_embeddings()
    enqueue.assert_not_awaited()
    await worker.retry_missing_embeddings()
    enqueue.assert_awaited_once_with("match_listing", {"listing_id": str(listing.id)})
    async with sessions() as db:
        media = await db.get(MediaObject, UUID(media_id))
        assert list(media.embedding) == embedding and media.status == "ready"
