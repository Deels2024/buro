import asyncio
import os
from datetime import UTC, datetime, timedelta
from http.cookiejar import MozillaCookieJar
from uuid import uuid4

import pytest
from fakeredis.aioredis import FakeRedis
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.api.routes import admin, auth
from app.core.config import settings
from app.core.security import create_access_token, encrypt_json, hash_secret, phone_lookup_hash
from app.core.totp import generate_totp_secret, totp_code
from app.db.base import Base
from app.db.models import RefreshToken, User
from app.db.session import get_db
from app.main import app
from app.services import cache


@pytest.fixture
async def browser_app(session_app, monkeypatch):
    client, sessions, fake = session_app
    monkeypatch.setattr(settings, "public_api_url", "https://test/v1")
    client.base_url = "https://test"
    client.headers.update({"Origin": "https://test", "X-Bureau-Web-Session": "1"})
    return client, sessions, fake


async def browser_login(client, user):
    await cache.set_json("otp:" + user.phone_hash, {"hash": hash_secret("123456"), "attempts": 0}, 300)
    return await client.post("/v1/auth/verify-code", json={"phone": "+79991234567", "code": "123456"})


async def test_browser_sms_session_survives_process_restart_without_local_storage(browser_app, tmp_path):
    client, sessions, _ = browser_app
    user = await add_user(sessions)
    login = await browser_login(client, user)
    assert login.status_code == 200
    cookie = login.headers["set-cookie"]
    for flag in ("HttpOnly", "Secure", "SameSite=strict", "Path=/", "Max-Age=2592000"):
        assert flag in cookie
    assert "Domain=" not in cookie
    assert login.headers["cache-control"] == "no-store"
    # Simulate a closed browser: only persistent cookies survive disk save/load;
    # no bearer token, localStorage, crypto key or live API client is retained.
    saved = MozillaCookieJar(str(tmp_path / "cookies.txt"))
    for item in client.cookies.jar:
        saved.set_cookie(item)
    saved.save()
    restored = MozillaCookieJar(saved.filename)
    restored.load()
    async with AsyncClient(transport=ASGITransport(app=app), base_url="https://test", cookies=restored,
        headers={"Origin": "https://test", "X-Bureau-Web-Session": "1"}) as reopened:
        response = await reopened.post("/v1/auth/session")
        assert response.status_code == 200
        me = await reopened.get("/v1/users/me", headers={"Authorization": "Bearer " + response.json()["access_token"]})
        assert me.status_code == 200 and me.json()["id"] == str(user.id)
        assert response.json()["refresh_token"] != login.json()["refresh_token"]


async def test_browser_lost_response_recovers_and_logout_revokes_successor(browser_app):
    client, sessions, _ = browser_app
    user = await add_user(sessions)
    login = await browser_login(client, user)
    old_cookie = {"Cookie": auth.WEB_SESSION_COOKIE + "=" + login.json()["refresh_token"]}
    first = await client.post("/v1/auth/session", headers=old_cookie)
    recovered = await client.post("/v1/auth/session", headers=old_cookie)
    assert first.status_code == recovered.status_code == 200
    assert first.json()["refresh_token"] == recovered.json()["refresh_token"]
    logout = await client.delete("/v1/auth/session", headers=old_cookie)
    assert logout.status_code == 200
    assert "Max-Age=0" in logout.headers["set-cookie"]
    assert (await client.post("/v1/auth/session", headers=old_cookie)).status_code == 401
    successor_cookie = {"Cookie": auth.WEB_SESSION_COOKIE + "=" + first.json()["refresh_token"]}
    assert (await client.post("/v1/auth/session", headers=successor_cookie)).status_code == 401
    assert (await client.post("/v1/auth/session")).status_code == 401


@pytest.mark.parametrize("method", ["POST", "DELETE"])
@pytest.mark.parametrize("overrides", [
    {"Origin": "https://evil.test"}, {"Origin": "https://admin.test"},
    {"Origin": "null"}, {"Origin": ""}, {"X-Bureau-Web-Session": ""},
])
async def test_browser_cookie_requires_exact_origin_and_explicit_header(browser_app, method, overrides):
    client, sessions, _ = browser_app
    user = await add_user(sessions)
    assert (await browser_login(client, user)).status_code == 200
    response = await client.request(method, "/v1/auth/session", headers=overrides)
    assert response.status_code == 403
    assert "set-cookie" not in response.headers
    assert (await client.post("/v1/auth/session")).status_code == 200


@pytest.mark.parametrize("state", ["expired", "revoked", "blocked", "mfa-required"])
async def test_browser_cookie_does_not_bypass_session_revocation(browser_app, state):
    client, sessions, _ = browser_app
    user = await add_user(sessions)
    login = await browser_login(client, user)
    async with sessions() as db:
        record = await db.scalar(select(RefreshToken).where(RefreshToken.token_hash == hash_secret(login.json()["refresh_token"])))
        saved = await db.get(User, user.id)
        if state == "expired":
            record.expires_at = datetime.now(UTC) - timedelta(seconds=1)
        elif state == "revoked":
            record.revoked_at = datetime.now(UTC)
        elif state == "blocked":
            saved.status = "blocked"
        else:
            saved.role = "admin"
            saved.admin_2fa_enabled = True
        await db.commit()
    assert (await client.post("/v1/auth/session")).status_code == 401


async def test_existing_browser_token_migrates_without_another_sms(browser_app):
    client, sessions, _ = browser_app
    user = await add_user(sessions)
    old = await add_refresh(sessions, user)
    migrated = await client.post("/v1/auth/refresh", json={"refresh_token": old}, headers={"X-Refresh-Operation": uuid4().hex})
    assert migrated.status_code == 200 and auth.WEB_SESSION_COOKIE in client.cookies
    assert (await client.post("/v1/auth/session")).status_code == 200


async def test_admin_browser_cookie_is_issued_only_after_2fa(browser_app):
    client, sessions, _ = browser_app
    secret = generate_totp_secret()
    user = await add_user(sessions, role="admin", admin_2fa_enabled=True, admin_totp_secret_cipher=encrypt_json({"secret": secret}))
    first = await browser_login(client, user)
    assert first.json()["mfa_required"] is True
    assert "set-cookie" not in first.headers
    second = await client.post("/v1/auth/verify-admin-2fa", json={"mfa_ticket": first.json()["mfa_ticket"], "code": totp_code(secret)})
    assert second.status_code == 200 and auth.WEB_SESSION_COOKIE in client.cookies
    assert (await client.post("/v1/auth/session")).status_code == 200


async def test_native_login_keeps_bearer_protocol_without_browser_cookie(session_app):
    client, sessions, _ = session_app
    user = await add_user(sessions)
    login = await browser_login(client, user)
    assert login.status_code == 200
    assert "set-cookie" not in login.headers


@pytest.fixture
async def session_app(tmp_path, monkeypatch):
    url = os.environ.get("TEST_DATABASE_URL", f"sqlite+aiosqlite:///{tmp_path}/sessions.db")
    engine = create_async_engine(url)
    async with engine.begin() as connection:
        if url.startswith("postgresql"):
            await connection.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
        await connection.run_sync(Base.metadata.create_all)
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    async def database():
        async with sessions() as db:
            yield db
    app.dependency_overrides[get_db] = database
    fake = FakeRedis(decode_responses=True)
    for module in (auth, admin, cache):
        monkeypatch.setattr(module, "redis", fake)
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        yield client, sessions, fake
    app.dependency_overrides.clear()
    await fake.aclose()
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.drop_all)
    await engine.dispose()


async def add_user(sessions, **values):
    async with sessions() as db:
        user = User(phone_hash=phone_lookup_hash("+79991234567"), phone_cipher=encrypt_json({"phone": "+79991234567"}), **values)
        db.add(user)
        await db.commit()
        return user


async def add_refresh(sessions, user, **values):
    raw = uuid4().hex * 2
    async with sessions() as db:
        db.add(RefreshToken(user_id=user.id, token_hash=hash_secret(raw), expires_at=datetime.now(UTC) + timedelta(days=1), **values))
        await db.commit()
    return raw


def headers(user, mfa=False):
    return {"Authorization": "Bearer " + create_access_token(str(user.id), user.role, mfa=mfa)}


async def test_parallel_refresh_rotates_once_and_new_session_remains_usable(session_app):
    client, sessions, _ = session_app
    user = await add_user(sessions)
    old = await add_refresh(sessions, user)
    responses = await asyncio.gather(*(client.post("/v1/auth/refresh", json={"refresh_token": old}) for _ in range(10)))
    assert [r.status_code for r in responses].count(200) == 1
    assert [r.status_code for r in responses].count(401) == 9
    new = next(r.json() for r in responses if r.status_code == 200)
    assert (await client.get("/v1/users/me", headers={"Authorization": "Bearer " + new["access_token"]})).status_code == 200
    assert (await client.post("/v1/auth/refresh", json={"refresh_token": new["refresh_token"]})).status_code == 200


async def test_enabled_2fa_cannot_be_reset_by_setup(session_app):
    client, sessions, _ = session_app
    cipher = encrypt_json({"secret": generate_totp_secret()})
    user = await add_user(sessions, role="admin", admin_2fa_enabled=True, admin_totp_secret_cipher=cipher)
    response = await client.post("/v1/auth/admin-2fa/setup", headers=headers(user, mfa=True))
    assert response.status_code == 409
    async with sessions() as db:
        saved = await db.get(User, user.id)
        assert saved.admin_2fa_enabled and saved.admin_totp_secret_cipher == cipher


async def test_idempotency_cannot_replay_successful_login_or_rotation(session_app):
    client, sessions, _ = session_app
    user = await add_user(sessions)
    await cache.set_json("otp:" + user.phone_hash, {"hash": hash_secret("123456"), "attempts": 0}, 300)
    body = {"phone": "+79991234567", "code": "123456"}
    key = {"Idempotency-Key": "same-login-request"}
    first = await client.post("/v1/auth/verify-code", json=body, headers=key)
    assert first.status_code == 200
    repeated = await client.post("/v1/auth/verify-code", json=body, headers=key)
    assert repeated.status_code == 400
    assert "access_token" not in repeated.json()
    refresh_body = {"refresh_token": first.json()["refresh_token"]}
    assert (await client.post("/v1/auth/refresh", json=refresh_body, headers=key)).status_code == 200
    assert (await client.post("/v1/auth/refresh", json=refresh_body, headers=key)).status_code == 401


async def test_2fa_setup_code_has_a_bruteforce_limit(session_app):
    client, sessions, _ = session_app
    secret = generate_totp_secret()
    user = await add_user(sessions, role="admin", admin_totp_secret_cipher=encrypt_json({"secret": secret}))
    wrong = "000000" if totp_code(secret) != "000000" else "111111"
    for _ in range(5):
        assert (await client.post("/v1/auth/admin-2fa/enable", json={"code": wrong}, headers=headers(user))).status_code == 400
    assert (await client.post("/v1/auth/admin-2fa/enable", json={"code": totp_code(secret)}, headers=headers(user))).status_code == 429


async def test_blocked_user_cannot_get_tokens_from_a_valid_sms(session_app):
    client, sessions, _ = session_app
    user = await add_user(sessions, status="blocked")
    await cache.set_json("otp:" + user.phone_hash, {"hash": hash_secret("123456"), "attempts": 0}, 300)
    assert (await client.post("/v1/auth/verify-code", json={"phone": "+79991234567", "code": "123456"})).status_code == 403
    async with sessions() as db:
        assert await db.scalar(select(func.count(RefreshToken.id))) == 0


async def test_non_mfa_refresh_cannot_extend_an_admin_session_after_2fa_is_enabled(session_app):
    client, sessions, _ = session_app
    user = await add_user(sessions, role="admin", admin_2fa_enabled=True)
    raw = await add_refresh(sessions, user, mfa_verified=False)
    assert (await client.post("/v1/auth/refresh", json={"refresh_token": raw})).status_code == 401


async def test_operations_are_admin_only_and_do_not_expose_payloads(session_app):
    client, sessions, fake = session_app
    user = await add_user(sessions)
    assert (await client.get("/v1/admin/operations")).status_code == 401
    assert (await client.get("/v1/admin/operations", headers=headers(user))).status_code == 403
    async with sessions() as db:
        saved = await db.get(User, user.id)
        saved.role = "admin"
        await db.commit()
    user.role = "admin"
    await fake.lpush("bureau:jobs:dead", '{"private":"hidden-user-evidence"}')
    response = await client.get("/v1/admin/operations", headers=headers(user))
    assert response.status_code == 200
    assert response.json()["failed"] == 1
    assert response.json()["worker"] == "unavailable"
    assert "hidden-user-evidence" not in response.text


async def test_lost_refresh_response_can_be_recovered_only_by_same_operation(session_app):
    client, sessions, fake = session_app
    user = await add_user(sessions)
    old = await add_refresh(sessions, user)
    body = {"refresh_token": old}
    operation = {"X-Refresh-Operation": uuid4().hex}
    first = await client.post("/v1/auth/refresh", json=body, headers=operation)
    assert first.status_code == 200
    replay = await client.post("/v1/auth/refresh", json=body, headers=operation)
    assert replay.status_code == 200
    assert replay.json()["refresh_token"] == first.json()["refresh_token"]
    assert (await client.post("/v1/auth/refresh", json=body)).status_code == 401
    assert (await client.post("/v1/auth/refresh", json=body, headers={"X-Refresh-Operation": uuid4().hex})).status_code == 401
    for key in await fake.keys("refresh:recovery:*"):
        assert first.json()["refresh_token"] not in await fake.get(key)
    assert (await client.post("/v1/auth/logout", json={"refresh_token": first.json()["refresh_token"]},
        headers={"Authorization": "Bearer " + first.json()["access_token"]})).status_code == 200
    assert (await client.post("/v1/auth/refresh", json=body, headers=operation)).status_code == 401


async def test_recovery_cannot_restore_a_blocked_account(session_app):
    client, sessions, _ = session_app
    user = await add_user(sessions)
    old = await add_refresh(sessions, user)
    operation = {"X-Refresh-Operation": uuid4().hex}
    body = {"refresh_token": old}
    assert (await client.post("/v1/auth/refresh", json=body, headers=operation)).status_code == 200
    async with sessions() as db:
        saved = await db.get(User, user.id)
        saved.status = "blocked"
        await db.commit()
    assert (await client.post("/v1/auth/refresh", json=body, headers=operation)).status_code == 401


async def test_parallel_recovery_returns_one_successor(session_app):
    client, sessions, _ = session_app
    user = await add_user(sessions)
    old = await add_refresh(sessions, user)
    operation = {"X-Refresh-Operation": uuid4().hex}
    replies = await asyncio.gather(*(client.post("/v1/auth/refresh", json={"refresh_token": old},
        headers=operation) for _ in range(6)))
    assert all(reply.status_code == 200 for reply in replies)
    assert len({reply.json()["refresh_token"] for reply in replies}) == 1


async def test_lost_response_recovers_after_days_and_cache_loss(session_app, monkeypatch):
    client, sessions, fake = session_app
    user = await add_user(sessions)
    old = await add_refresh(sessions, user)
    operation = {"X-Refresh-Operation": uuid4().hex}
    body = {"refresh_token": old}
    first = await client.post("/v1/auth/refresh", json=body, headers=operation)
    assert first.status_code == 200
    await fake.flushall()
    later = datetime.now(UTC) + timedelta(days=7)

    class LaterDateTime(datetime):
        @classmethod
        def now(cls, tz=None):
            return later

    monkeypatch.setattr(auth, "datetime", LaterDateTime)
    recovered = await client.post("/v1/auth/refresh", json=body, headers=operation)
    assert recovered.status_code == 200
    assert recovered.json()["refresh_token"] == first.json()["refresh_token"]
    # Recovery returns the existing token; it does not mint another 30 days.
    async with sessions() as db:
        assert await db.scalar(select(func.count(RefreshToken.id))) == 2
    later += timedelta(days=30)
    assert (await client.post("/v1/auth/refresh", json=body, headers=operation)).status_code == 401


async def test_recovery_cannot_replay_a_successor_that_was_already_consumed(session_app):
    client, sessions, _ = session_app
    user = await add_user(sessions)
    old = await add_refresh(sessions, user)
    operation = {"X-Refresh-Operation": uuid4().hex}
    body = {"refresh_token": old}
    first = await client.post("/v1/auth/refresh", json=body, headers=operation)
    assert first.status_code == 200
    second = await client.post("/v1/auth/refresh", json={"refresh_token": first.json()["refresh_token"]})
    assert second.status_code == 200
    assert (await client.post("/v1/auth/refresh", json=body, headers=operation)).status_code == 401


async def test_legacy_cached_successor_remains_recoverable(session_app):
    client, sessions, fake = session_app
    user = await add_user(sessions)
    old = await add_refresh(sessions, user, revoked_at=datetime.now(UTC))
    successor = await add_refresh(sessions, user)
    operation = uuid4().hex
    key = "refresh:recovery:" + hash_secret(f"{hash_secret(old)}|{operation}")
    await fake.set(key, encrypt_json({"refresh_token": successor}), ex=86400)
    response = await client.post("/v1/auth/refresh", json={"refresh_token": old},
        headers={"X-Refresh-Operation": operation})
    assert response.status_code == 200
    assert response.json()["refresh_token"] == successor
