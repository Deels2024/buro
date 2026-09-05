import asyncio
import json

import pytest
from fakeredis.aioredis import FakeRedis

from app import worker
from app.services import cache


@pytest.fixture
async def queue(monkeypatch):
    fake = FakeRedis(decode_responses=True)
    monkeypatch.setattr(cache, "redis", fake)
    monkeypatch.setattr(worker, "redis", fake)
    yield fake
    await fake.aclose()


async def take(queue):
    return await queue.rpoplpush("bureau:jobs", "bureau:jobs:processing")


async def test_fifo_work_does_not_starve_older_publications(queue, monkeypatch):
    done = []
    async def process(payload):
        done.append(payload["id"])
    monkeypatch.setitem(worker.HANDLERS, "test", process)
    for number in range(5):
        await cache.enqueue("test", {"id": number})
    for _ in range(5):
        await worker.process_job(await take(queue))
    assert done == list(range(5))
    assert await queue.llen("bureau:jobs:processing") == 0


@pytest.mark.parametrize("bad", ["not-json", "null", "[]", '{"name": []}', '{"name":"test","payload":[]}', '{"name":"test","payload":{},"attempts":"many"}'])
async def test_bad_job_is_quarantined_without_stopping_next_task(queue, monkeypatch, bad):
    done = []
    async def process(payload):
        done.append(payload)
    monkeypatch.setitem(worker.HANDLERS, "test", process)
    await queue.lpush("bureau:jobs", bad)
    await cache.enqueue("test", {"ok": True})
    await worker.process_job(await take(queue))
    await worker.process_job(await take(queue))
    assert done == [{"ok": True}]
    assert await queue.lrange("bureau:jobs:dead", 0, -1) == [bad]
    assert await queue.llen("bureau:jobs:processing") == 0


async def test_retries_are_bounded_and_other_tasks_get_a_turn(queue, monkeypatch):
    done = []
    async def process(payload):
        done.append(payload["id"])
        if payload["id"] == "broken":
            raise OSError("temporary dependency failure")
    monkeypatch.setitem(worker.HANDLERS, "test", process)
    await cache.enqueue("test", {"id": "broken"})
    await cache.enqueue("test", {"id": "good"})
    for _ in range(4):
        await worker.process_job(await take(queue))
    assert done == ["broken", "good", "broken", "broken"]
    assert await queue.llen("bureau:jobs") == 0
    assert await queue.llen("bureau:jobs:processing") == 0
    dead = json.loads(await queue.lindex("bureau:jobs:dead", 0))
    assert dead["attempts"] == 3


async def test_shutdown_preserves_unfinished_job_for_recovery(queue, monkeypatch):
    started = asyncio.Event()
    async def process(payload):
        started.set()
        await asyncio.Event().wait()
    monkeypatch.setitem(worker.HANDLERS, "test", process)
    await cache.enqueue("test", {})
    raw = await take(queue)
    task = asyncio.create_task(worker.process_job(raw))
    await started.wait()
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert await queue.lrange("bureau:jobs:processing", 0, -1) == [raw]
    assert await queue.llen("bureau:jobs:dead") == 0
