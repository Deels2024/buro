import json
from enum import StrEnum
from typing import Any

from redis.asyncio import Redis

from app.core.config import settings

redis = Redis.from_url(settings.redis_url, decode_responses=True)


class OtpVerificationResult(StrEnum):
    VERIFIED = "verified"
    EXPIRED = "expired"
    INVALID = "invalid"
    ATTEMPTS_EXCEEDED = "attempts_exceeded"


_VERIFY_AND_CONSUME_OTP_SCRIPT = """
local raw = redis.call("GET", KEYS[1])
if not raw then
  return 0
end

local saved = cjson.decode(raw)
local attempts = tonumber(saved["attempts"]) or 0
local max_attempts = tonumber(ARGV[2])

if attempts >= max_attempts then
  redis.call("DEL", KEYS[1])
  return 3
end

if saved["hash"] ~= ARGV[1] then
  attempts = attempts + 1
  if attempts >= max_attempts then
    redis.call("DEL", KEYS[1])
    return 3
  end
  saved["attempts"] = attempts
  redis.call("SET", KEYS[1], cjson.encode(saved), "KEEPTTL")
  return 2
end

redis.call("DEL", KEYS[1])
return 1
"""

_OTP_VERIFICATION_RESULTS = {
    0: OtpVerificationResult.EXPIRED,
    1: OtpVerificationResult.VERIFIED,
    2: OtpVerificationResult.INVALID,
    3: OtpVerificationResult.ATTEMPTS_EXCEEDED,
}

_RATE_LIMIT_SCRIPT = """
local current = redis.call("INCR", KEYS[1])
local ttl = redis.call("TTL", KEYS[1])
if current == 1 or ttl < 0 then
  redis.call("EXPIRE", KEYS[1], ARGV[1])
end
return current
"""


async def set_json(key: str, value: Any, ttl: int) -> None:
    await redis.set(key, json.dumps(value, ensure_ascii=False), ex=ttl)


async def get_json(key: str) -> Any | None:
    value = await redis.get(key)
    return json.loads(value) if value else None


async def verify_and_consume_otp(
    key: str,
    candidate_hash: str,
    max_attempts: int,
) -> OtpVerificationResult:
    result = await redis.eval(
        _VERIFY_AND_CONSUME_OTP_SCRIPT,
        1,
        key,
        candidate_hash,
        max_attempts,
    )
    try:
        return _OTP_VERIFICATION_RESULTS[int(result)]
    except (KeyError, TypeError, ValueError) as exc:
        raise RuntimeError("Redis returned an unknown OTP verification result") from exc


async def enqueue(job_name: str, payload: dict) -> None:
    await redis.rpush("bureau:jobs", json.dumps({"name": job_name, "payload": payload}))


async def rate_limit(key: str, limit: int, period_seconds: int) -> bool:
    current = await redis.eval(_RATE_LIMIT_SCRIPT, 1, key, period_seconds)
    return int(current) <= limit
