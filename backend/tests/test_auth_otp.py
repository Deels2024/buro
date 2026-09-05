import pytest
from fastapi import HTTPException
from starlette.requests import Request

from app.api.routes import auth
from app.schemas import PhoneCodeRequest


def _request(*, peer: str, real_ip: str | None = None) -> Request:
    headers = [] if real_ip is None else [(b"x-real-ip", real_ip.encode())]
    return Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/v1/auth/request-code",
            "raw_path": b"/v1/auth/request-code",
            "query_string": b"",
            "headers": headers,
            "client": (peer, 50000),
            "server": ("api", 8080),
            "scheme": "http",
        }
    )


def test_client_ip_uses_gateway_address_and_rejects_public_spoof() -> None:
    assert auth._client_ip(_request(peer="172.18.0.5", real_ip="198.51.100.24")) == (
        "198.51.100.24"
    )
    assert auth._client_ip(_request(peer="8.8.8.8", real_ip="198.51.100.24")) == "8.8.8.8"
    assert auth._client_ip(_request(peer="172.18.0.5", real_ip="not-an-ip")) == "172.18.0.5"


@pytest.mark.asyncio
async def test_existing_cooldown_does_not_consume_rate_limit(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def remaining(_: str) -> int:
        return 37

    async def unexpected_rate_limit(*_: object) -> bool:
        raise AssertionError("rate limiter must not be consumed during resend cooldown")

    monkeypatch.setattr(auth, "_otp_cooldown_remaining", remaining)
    monkeypatch.setattr(auth, "rate_limit", unexpected_rate_limit)

    with pytest.raises(HTTPException) as captured:
        await auth.request_code(
            PhoneCodeRequest(phone="+79991234567"),
            _request(peer="172.18.0.5", real_ip="198.51.100.24"),
        )

    assert captured.value.status_code == 429
    assert captured.value.headers == {"Retry-After": "37"}


@pytest.mark.asyncio
async def test_forwarded_clients_get_distinct_ip_rate_buckets(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    rate_keys: list[str] = []

    async def no_cooldown(_: str) -> int:
        return 0

    async def allow(key: str, _: int, __: int) -> bool:
        rate_keys.append(key)
        return True

    async def ignore_set_json(*_: object, **__: object) -> None:
        return None

    async def ignore_send(*_: object, **__: object) -> None:
        return None

    monkeypatch.setattr(auth, "_otp_cooldown_remaining", no_cooldown)
    monkeypatch.setattr(auth, "_acquire_otp_cooldown", no_cooldown)
    monkeypatch.setattr(auth, "rate_limit", allow)
    monkeypatch.setattr(auth, "set_json", ignore_set_json)
    monkeypatch.setattr(auth, "send_otp", ignore_send)

    for real_ip in ("198.51.100.24", "203.0.113.19"):
        await auth.request_code(
            PhoneCodeRequest(phone="+79991234567"),
            _request(peer="172.18.0.5", real_ip=real_ip),
        )

    ip_keys = [key for key in rate_keys if key.startswith("otp:ip:rate:")]
    assert len(ip_keys) == 2
    assert ip_keys[0] != ip_keys[1]


class _RedisDeleteRecorder:
    def __init__(self) -> None:
        self.deleted: tuple[str, ...] = ()

    async def delete(self, *keys: str) -> None:
        self.deleted = keys


@pytest.mark.asyncio
async def test_delivery_failure_releases_code_and_resend_cooldown(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def no_cooldown(_: str) -> int:
        return 0

    async def allow(*_: object) -> bool:
        return True

    async def ignore_set_json(*_: object, **__: object) -> None:
        return None

    async def fail_send(*_: object, **__: object) -> None:
        raise RuntimeError("provider unavailable")

    redis = _RedisDeleteRecorder()
    monkeypatch.setattr(auth, "_otp_cooldown_remaining", no_cooldown)
    monkeypatch.setattr(auth, "_acquire_otp_cooldown", no_cooldown)
    monkeypatch.setattr(auth, "rate_limit", allow)
    monkeypatch.setattr(auth, "set_json", ignore_set_json)
    monkeypatch.setattr(auth, "send_otp", fail_send)
    monkeypatch.setattr(auth, "redis", redis)

    with pytest.raises(HTTPException) as captured:
        await auth.request_code(
            PhoneCodeRequest(phone="+79991234567"),
            _request(peer="172.18.0.5", real_ip="198.51.100.24"),
        )

    assert captured.value.status_code == 503
    assert len(redis.deleted) == 2
    assert redis.deleted[0].startswith("otp:")
    assert redis.deleted[1].startswith("otp:phone:cooldown:")


async def test_global_budget_rejects_before_a_paid_sms_and_releases_cooldown(monkeypatch):
    async def no_cooldown(*args):
        return 0
    async def allow(*args):
        return True
    async def exhausted():
        return 1800
    async def must_not_send(*args, **kwargs):
        raise AssertionError("No code or paid SMS may be created after reaching the cap")
    recorder = _RedisDeleteRecorder()
    monkeypatch.setattr(auth, "redis", recorder)
    monkeypatch.setattr(auth.settings, "smsc_login", "test")
    monkeypatch.setattr(auth.settings, "smsc_password", "test")
    monkeypatch.setattr(auth, "_otp_cooldown_remaining", no_cooldown)
    monkeypatch.setattr(auth, "_acquire_otp_cooldown", no_cooldown)
    monkeypatch.setattr(auth, "rate_limit", allow)
    monkeypatch.setattr(auth, "reserve_sms_send", exhausted)
    monkeypatch.setattr(auth, "set_json", must_not_send)
    monkeypatch.setattr(auth, "send_otp", must_not_send)
    with pytest.raises(HTTPException) as captured:
        await auth.request_code(PhoneCodeRequest(phone="+79991234567"), _request(peer="8.8.8.8"))
    assert captured.value.status_code == 503
    assert captured.value.headers == {"Retry-After": "1800"}
    assert len(recorder.deleted) == 1 and recorder.deleted[0].startswith("otp:phone:cooldown:")
