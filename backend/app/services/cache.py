import json
from typing import Any

from redis.asyncio import Redis

from app.core.config import settings

redis = Redis.from_url(settings.redis_url, decode_responses=True)


async def set_json(key: str, value: Any, ttl: int) -> None:
    await redis.set(key, json.dumps(value, ensure_ascii=False), ex=ttl)


async def get_json(key: str) -> Any | None:
    value = await redis.get(key)
    return json.loads(value) if value else None


async def enqueue(job_name: str, payload: dict) -> None:
    await redis.rpush("bureau:jobs", json.dumps({"name": job_name, "payload": payload}))


async def rate_limit(key: str, limit: int, period_seconds: int) -> bool:
    current = await redis.incr(key)
    if current == 1:
        await redis.expire(key, period_seconds)
    return current <= limit
