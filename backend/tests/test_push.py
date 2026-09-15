import base64
import importlib.util
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import select
from test_auth_sessions import add_user, headers
from test_auth_sessions import session_app as session_app

from app.core.security import decrypt_json
from app.db.models import Notification, PushDelivery, PushDevice
from app.services import push


def subscription(endpoint="https://web.push.apple.com/QExample"):
    return {"endpoint": endpoint, "keys": {"p256dh": push.vapid_keys()[0],
            "auth": base64.urlsafe_b64encode(b"0123456789abcdef").decode().rstrip("=")}}


@pytest.mark.parametrize("endpoint", ["http://web.push.apple.com/a", "https://localhost/a", "https://127.0.0.1/a",
    "https://web.push.apple.com.evil.example/a", "https://evil.example/", "https://user:pass@web.push.apple.com/a",
    "https://web.push.apple.com:8080/a", "https://web.push.apple.com:bad/a"])
def test_subscription_rejects_untrusted_targets(endpoint):
    with pytest.raises(ValueError):
        push.validate_subscription(subscription(endpoint))


def test_send_uses_real_encryption_and_vapid_with_private_payload(monkeypatch):
    # Intercept only HTTP: exercise pywebpush's actual encoding and key parsing.
    post = Mock(return_value=SimpleNamespace(status_code=201, text="", headers={}))
    monkeypatch.setattr(push.DirectSession, "post", post)
    assert push.send(subscription(), "f" * 32, "chat_message") == 201
    kwargs = post.call_args.kwargs
    assert kwargs["headers"]["authorization"].startswith("vapid ")
    assert kwargs["data"] and b"chat_message" not in kwargs["data"]
    assert kwargs["timeout"] == 10
    with push.DirectSession() as session:
        assert session.trust_env is False


async def setup_delivery(session_app):
    client, sessions, _ = session_app
    user = await add_user(sessions)
    response = await client.put("/v1/users/me/push/subscription", json=subscription(), headers=headers(user))
    assert response.status_code == 200, response.text
    async with sessions() as db:
        device = await db.scalar(select(PushDevice))
        assert "endpoint" not in response.text and device.token_cipher != str(subscription())
        assert decrypt_json(device.token_cipher) == subscription()
        note = Notification(user_id=user.id, kind="new_match", title="PRIVATE ITEM", body="PRIVATE ADDRESS", data={})
        db.add(note)
        await db.commit()
    return user, device.id, note.id


async def test_push_requires_login_and_does_not_replay_old_notifications(session_app, monkeypatch):
    client, sessions, _ = session_app
    assert (await client.put("/v1/users/me/push/subscription", json=subscription())).status_code == 401
    user, _, _ = await setup_delivery(session_app)
    send = Mock(return_value=201)
    monkeypatch.setattr(push, "send", send)
    async with sessions() as db:
        db.add(Notification(user_id=user.id, kind="new_match", title="Old", body="Old", data={},
                            created_at=datetime.now(UTC) - timedelta(hours=2)))
        await db.commit()
        await push.deliver_pending(db)
    async with sessions() as db:  # Simulate a restarted worker with a fresh session.
        await push.deliver_pending(db)
        deliveries = list(await db.scalars(select(PushDelivery)))
        assert len(deliveries) == 1 and deliveries[0].status == "sent"
    assert send.call_count == 1
    assert "PRIVATE" not in str(send.call_args)


async def test_temporary_failure_retries_but_expired_subscription_stops(session_app, monkeypatch):
    _, sessions, _ = session_app
    await setup_delivery(session_app)
    send = Mock(side_effect=[503, 410])
    monkeypatch.setattr(push, "send", send)
    async with sessions() as db:
        await push.deliver_pending(db)
        delivery = await db.scalar(select(PushDelivery))
        assert delivery.status == "pending" and delivery.attempts == 1
        await push.deliver_pending(db)
        assert send.call_count == 1  # Respect backoff.
        delivery.next_attempt_at = datetime.now(UTC) - timedelta(seconds=1)
        await db.commit()
        await push.deliver_pending(db)
        assert delivery.status == "expired"
        assert (await db.scalar(select(PushDevice))).status == "expired"
        await push.deliver_pending(db)
        assert send.call_count == 2


async def test_opt_out_prevents_delivery(session_app, monkeypatch):
    client, sessions, _ = session_app
    user, device, _ = await setup_delivery(session_app)
    send = Mock(return_value=201)
    monkeypatch.setattr(push, "send", send)
    assert (await client.delete(f"/v1/users/me/devices/{device}", headers=headers(user))).status_code == 204
    async with sessions() as db:
        await push.deliver_pending(db)
    send.assert_not_called()


async def test_push_migration_handles_existing_and_fresh_installs(session_app):
    _, sessions, _ = session_app
    spec = importlib.util.spec_from_file_location("push_migration", "alembic/versions/0004_push_delivery.py")
    migration = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(migration)
    async with sessions() as db:
        connection = await db.connection()
        def upgrade_twice(sync_connection):
            with Operations.context(MigrationContext.configure(sync_connection)):
                migration.upgrade()  # Initial migration may already have created it.
                PushDelivery.__table__.drop(sync_connection)
                migration.upgrade()  # Upgrade of a real previous schema.
                migration.upgrade()
        await connection.run_sync(upgrade_twice)
        await db.commit()
        assert list(await db.scalars(select(PushDelivery))) == []
