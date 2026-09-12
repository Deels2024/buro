import asyncio
import os
from datetime import UTC, datetime
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest
import test_auth_sessions
from sqlalchemy import select
from test_auth_sessions import add_refresh, add_user, headers

from app.api.routes import internal_deployment
from app.core.security import encrypt_json, phone_lookup_hash
from app.db.models import AuditEvent, Listing, RefreshToken, SupportTicket, User

session_app = test_auth_sessions.session_app


@pytest.mark.parametrize("path", [
    "/users", "/settings", "/organizations", "/operations", "/audit",
    "/analytics/overview", "/analytics/traffic", "/exports/overview.csv", "/ads",
])
async def test_moderator_cannot_read_administration(session_app, path):
    client, sessions, _ = session_app
    moderator = await add_user(sessions, role="moderator")
    assert (await client.get("/v1/admin" + path, headers=headers(moderator))).status_code == 403


async def test_moderator_cannot_escalate_roles_or_change_system_settings(session_app):
    client, sessions, _ = session_app
    moderator = await add_user(sessions, role="moderator", verified_at=datetime.now(UTC))
    async with sessions() as db:
        admin = User(phone_hash=uuid4().hex, phone_cipher=encrypt_json({"phone": "+79990000101"}), role="admin")
        db.add(admin)
        await db.commit()
    for target, payload in [(moderator, {"role": "admin"}), (admin, {"role": "user"}), (admin, {"status": "blocked"})]:
        response = await client.patch(f"/v1/admin/users/{target.id}", json=payload, headers=headers(moderator))
        assert response.status_code == 403
    assert (await client.put("/v1/admin/settings/search", json={"value": {"enabled": False}}, headers=headers(moderator))).status_code == 403
    assert (await client.post(f"/v1/admin/organizations/{uuid4()}/verify", json={"decision": "approve", "reason": "Проверено"}, headers=headers(moderator))).status_code == 403
    async with sessions() as db:
        assert (await db.get(User, moderator.id)).role == "moderator"
        saved = await db.get(User, admin.id)
        assert saved.role == "admin" and saved.status == "active"


async def test_moderator_can_moderate_and_handle_support(session_app):
    client, sessions, _ = session_app
    moderator = await add_user(sessions, role="moderator")
    async with sessions() as db:
        listing = Listing(owner_id=moderator.id, kind="lost", title="Ключи", description="Связка ключей",
                          category="other", public_region="Москва", status="active",
                          moderation_status="pending", event_at=datetime.now(UTC))
        ticket = SupportTicket(user_id=moderator.id, subject="Помогите найти вещь", category="other")
        db.add_all([listing, ticket])
        await db.commit()
    for path in ["/dashboard", "/listings", "/claims", "/matches", "/moderation/listings", "/support/tickets", "/disputes"]:
        assert (await client.get("/v1/admin" + path, headers=headers(moderator))).status_code == 200
    response = await client.post(f"/v1/admin/moderation/listings/{listing.id}",
                                json={"decision": "reject", "reason": "Нужно уточнить описание"}, headers=headers(moderator))
    assert response.status_code == 200 and response.json()["status"] == "rejected"
    assert (await client.patch(f"/v1/admin/support/tickets/{ticket.id}", json={"status": "resolved"}, headers=headers(moderator))).status_code == 200


async def test_admin_assigns_moderator_and_old_sessions_do_not_inherit_access(session_app):
    client, sessions, _ = session_app
    target = await add_user(sessions, verified_at=datetime.now(UTC))
    old_headers = headers(target)
    old_refresh = await add_refresh(sessions, target)
    async with sessions() as db:
        admin = User(phone_hash=uuid4().hex, phone_cipher="test", role="admin", verified_at=datetime.now(UTC))
        db.add(admin)
        await db.commit()
    response = await client.patch(f"/v1/admin/users/{target.id}", json={"role": "moderator"}, headers=headers(admin))
    assert response.status_code == 200 and response.json()["role"] == "moderator"
    assert (await client.get("/v1/admin/moderation/listings", headers=old_headers)).status_code == 401
    assert (await client.post("/v1/auth/refresh", json={"refresh_token": old_refresh})).status_code == 401
    target.role = "moderator"
    assert (await client.get("/v1/admin/moderation/listings", headers=headers(target))).status_code == 200
    for payload in [{"role": "user"}, {"status": "blocked"}, {"status": "deleted"}]:
        assert (await client.patch(f"/v1/admin/users/{admin.id}", json=payload, headers=headers(admin))).status_code == 409
    assert (await client.get("/v1/admin/settings", headers=headers(admin))).status_code == 200
    assert (await client.put("/v1/admin/settings/test", json={"value": {"enabled": True}}, headers=headers(admin))).status_code == 200
    assert (await client.patch(f"/v1/admin/users/{target.id}", json={"role": None, "status": None}, headers=headers(admin))).status_code == 200


async def test_provisioning_requires_separate_oidc_and_verified_phone(session_app, monkeypatch):
    client, sessions, _ = session_app
    target = await add_user(sessions, verified_at=datetime.now(UTC))
    old_refresh = await add_refresh(sessions, target)
    old_headers = headers(target)
    body = b"+79991234567"
    url = "/v1/internal/deployment/administrator"
    assert (await client.post(url, content=body, headers={"Content-Type": "application/octet-stream"})).status_code == 401
    verify = AsyncMock(return_value={"actor_id": "160591824", "run_id": "test-run"})
    monkeypatch.setattr(internal_deployment, "verify_github_oidc_token", verify)
    configuration_headers = {"Content-Type": "application/octet-stream", "Authorization": "Bearer oidc-token"}
    response = await client.post(url, content=body, headers=configuration_headers)
    assert response.status_code == 200 and response.json() == {"status": "configured", "role": "admin"}
    assert response.headers["cache-control"] == "no-store"
    verify.assert_awaited_once_with("oidc-token", configure_admin=True)
    assert (await client.get("/v1/admin/users", headers=old_headers)).status_code == 401
    assert (await client.post("/v1/auth/refresh", json={"refresh_token": old_refresh})).status_code == 401
    async with sessions() as db:
        saved = await db.get(User, target.id)
        assert saved.role == "admin"
        audit = (await db.scalars(select(AuditEvent).where(AuditEvent.action == "deployment.administrator.grant"))).one()
        assert body.decode() not in str(audit.payload) and phone_lookup_hash(body.decode()) not in str(audit.payload)
    new_refresh = await add_refresh(sessions, target)
    assert (await client.post(url, content=body, headers=configuration_headers)).status_code == 200
    assert (await client.post("/v1/auth/refresh", json={"refresh_token": new_refresh})).status_code == 200
    for raw, expected in [(b"invalid-phone", 422), (b"a" * 33, 422), (b"+79990000001", 409)]:
        result = await client.post(url, content=raw, headers=configuration_headers)
        assert result.status_code == expected and raw.decode() not in result.text


@pytest.mark.parametrize("status,verified", [("blocked", True), ("deleted", True), ("invited", False), ("active", False)])
async def test_provisioning_does_not_activate_unverified_or_blocked_accounts(session_app, monkeypatch, status, verified):
    client, sessions, _ = session_app
    target = await add_user(sessions, status=status, verified_at=datetime.now(UTC) if verified else None)
    monkeypatch.setattr(internal_deployment, "verify_github_oidc_token", AsyncMock(return_value={"actor_id": "160591824"}))
    response = await client.post("/v1/internal/deployment/administrator", content=b"+79991234567",
                                headers={"Content-Type": "application/octet-stream", "Authorization": "Bearer oidc-token"})
    assert response.status_code == 409
    async with sessions() as db:
        saved = await db.get(User, target.id)
        assert saved.status == status and saved.role == "user"


@pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL", "").startswith("postgresql"), reason="Row-lock concurrency requires PostgreSQL")
async def test_inflight_refresh_cannot_escape_administrator_grant(session_app, monkeypatch):
    client, sessions, _ = session_app
    target = await add_user(sessions, verified_at=datetime.now(UTC))
    refresh = await add_refresh(sessions, target)
    monkeypatch.setattr(internal_deployment, "verify_github_oidc_token", AsyncMock(return_value={"actor_id": "160591824"}))
    responses = await asyncio.gather(
        client.post("/v1/internal/deployment/administrator", content=b"+79991234567",
                    headers={"Content-Type": "application/octet-stream", "Authorization": "Bearer oidc-token"}),
        *(client.post("/v1/auth/refresh", json={"refresh_token": refresh}) for _ in range(5)),
    )
    assert responses[0].status_code == 200
    for response in responses[1:]:
        assert response.status_code in {200, 401}
        if response.status_code == 200:
            assert (await client.get("/v1/admin/users", headers={"Authorization": "Bearer " + response.json()["access_token"]})).status_code == 401
            assert (await client.post("/v1/auth/refresh", json={"refresh_token": response.json()["refresh_token"]})).status_code == 401
    async with sessions() as db:
        assert not (await db.scalars(select(RefreshToken).where(RefreshToken.user_id == target.id, RefreshToken.revoked_at.is_(None)))).all()
