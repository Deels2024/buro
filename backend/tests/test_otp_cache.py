import asyncio
import json

import pytest
from fakeredis.aioredis import FakeRedis

from app.services import cache
from app.services.cache import OtpVerificationResult


@pytest.fixture
def fake_redis(monkeypatch: pytest.MonkeyPatch) -> FakeRedis:
    instance = FakeRedis(decode_responses=True)
    monkeypatch.setattr(cache, "redis", instance)
    return instance


async def _store_otp(fake_redis: FakeRedis, key: str, code_hash: str, *, ttl_ms: int = 120_000) -> None:
    await fake_redis.set(
        key,
        json.dumps({"hash": code_hash, "attempts": 0}),
        px=ttl_ms,
    )


async def test_valid_otp_is_consumed_only_once(fake_redis: FakeRedis) -> None:
    key = "otp:phone"
    await _store_otp(fake_redis, key, "correct-hash")

    results = await asyncio.gather(
        *(cache.verify_and_consume_otp(key, "correct-hash", 5) for _ in range(20))
    )

    assert results.count(OtpVerificationResult.VERIFIED) == 1
    assert results.count(OtpVerificationResult.EXPIRED) == 19
    assert await fake_redis.get(key) is None


async def test_invalid_attempt_preserves_ttl_and_allows_later_success(fake_redis: FakeRedis) -> None:
    key = "otp:phone"
    await _store_otp(fake_redis, key, "correct-hash")
    ttl_before = await fake_redis.pttl(key)

    result = await cache.verify_and_consume_otp(key, "wrong-hash", 5)
    ttl_after = await fake_redis.pttl(key)

    assert result == OtpVerificationResult.INVALID
    assert 0 < ttl_after <= ttl_before
    assert json.loads(await fake_redis.get(key)) == {"hash": "correct-hash", "attempts": 1}
    assert (
        await cache.verify_and_consume_otp(key, "correct-hash", 5)
        == OtpVerificationResult.VERIFIED
    )


async def test_attempt_limit_removes_otp_atomically(fake_redis: FakeRedis) -> None:
    key = "otp:phone"
    await _store_otp(fake_redis, key, "correct-hash")

    first_results = [
        await cache.verify_and_consume_otp(key, "wrong-hash", 3)
        for _ in range(2)
    ]
    final_result = await cache.verify_and_consume_otp(key, "wrong-hash", 3)

    assert first_results == [OtpVerificationResult.INVALID, OtpVerificationResult.INVALID]
    assert final_result == OtpVerificationResult.ATTEMPTS_EXCEEDED
    assert await fake_redis.get(key) is None
    assert (
        await cache.verify_and_consume_otp(key, "correct-hash", 3)
        == OtpVerificationResult.EXPIRED
    )


async def test_rate_limit_is_atomic_and_expires(fake_redis: FakeRedis) -> None:
    results = await asyncio.gather(
        *(cache.rate_limit("rate:test", 5, 60) for _ in range(20))
    )

    assert results.count(True) == 5
    assert results.count(False) == 15
    assert 0 < await fake_redis.ttl("rate:test") <= 60


async def test_rate_limit_repairs_a_counter_without_ttl(fake_redis: FakeRedis) -> None:
    await fake_redis.set("rate:test", "5")

    assert not await cache.rate_limit("rate:test", 5, 60)
    assert 0 < await fake_redis.ttl("rate:test") <= 60


async def test_sms_budget_is_shared_and_atomic(fake_redis, monkeypatch):
    monkeypatch.setattr(cache.settings, "sms_hourly_limit", 3)
    monkeypatch.setattr(cache.settings, "sms_daily_limit", 10)
    results = await asyncio.gather(*(cache.reserve_sms_send() for _ in range(20)))
    assert results.count(0) == 3
    assert all(0 < value <= 3600 for value in results if value)
    # Requests rejected by the hour cap do not consume the day cap.
    day_key = (await fake_redis.keys("sms:budget:day:*"))[0]
    assert int(await fake_redis.get(day_key)) == 3
    assert 0 < await fake_redis.ttl(day_key) <= 86400


async def test_daily_budget_stops_send_even_when_hourly_budget_remains(fake_redis, monkeypatch):
    monkeypatch.setattr(cache.settings, "sms_hourly_limit", 20)
    monkeypatch.setattr(cache.settings, "sms_daily_limit", 2)
    assert await cache.reserve_sms_send() == 0
    assert await cache.reserve_sms_send() == 0
    assert 0 < await cache.reserve_sms_send() <= 86400
