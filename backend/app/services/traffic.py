"""Daily aggregate events, without cookies, user IDs, IPs or query text."""
import logging
from datetime import UTC, datetime, timedelta

from app.services.cache import redis

EVENTS = ("home", "search", "listing_view", "publication", "claim_submitted", "handover_completed")
logger = logging.getLogger(__name__)


async def record_event(event: str) -> None:
    if event not in EVENTS:
        return
    try:
        key = f"bureau:traffic:{datetime.now(UTC):%Y-%m-%d}"
        async with redis.pipeline(transaction=True) as pipe:
            await pipe.hincrby(key, event, 1).expire(key, 90 * 86400).execute()
    except Exception:
        logger.warning("Aggregate metrics are temporarily unavailable")


async def traffic_totals(days: int = 30) -> dict:
    now = datetime.now(UTC)
    keys = [f"bureau:traffic:{now - timedelta(days=i):%Y-%m-%d}" for i in range(days)]
    async with redis.pipeline(transaction=False) as pipe:
        for key in keys:
            pipe.hgetall(key)
        rows = await pipe.execute()
    totals = {event: sum(int(row.get(event, 0)) for row in rows) for event in EVENTS}
    return {"days": days, "counts": totals, "measurement": "events_not_unique_users", "retention_days": 90}
