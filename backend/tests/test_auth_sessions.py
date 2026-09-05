import asyncio
import os
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from fakeredis.aioredis import FakeRedis
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.api.routes import admin, auth
from app.core.security import create_access_token, encrypt_json, hash_secret, phone_lookup_hash
from app.core.totp import generate_totp_secret, totp_code
from app.db.base import Base
from app.db.models import RefreshToken, User
from app.db.session import get_db
from app.main import app
from app.services import cache


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
