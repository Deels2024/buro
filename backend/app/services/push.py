"""Opt-in Web Push. Delivery state survives worker/Redis restarts."""
import asyncio
import base64
import json
from datetime import UTC, datetime, timedelta
from urllib.parse import urlparse

import requests
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from pywebpush import WebPushException, webpush
from sqlalchemy import and_, select

from app.core.security import decrypt_json, hash_secret
from app.db.models import Notification, PushDelivery, PushDevice, User

PLATFORM = "webpush"
_ORDER = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551


def vapid_keys() -> tuple[str, str]:
    # Stable, purpose-separated key: no additional secret needs to be copied
    # to the VPS. Rotating APP_SECRET intentionally requires re-subscription.
    scalar = int(hash_secret("bureau:webpush:vapid:v1"), 16) % (_ORDER - 1) + 1
    key = ec.derive_private_key(scalar, ec.SECP256R1())
    public = key.public_key().public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)
    private = key.private_bytes(serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption())
    return base64.urlsafe_b64encode(public).decode().rstrip("="), base64.urlsafe_b64encode(private).decode().rstrip("=")


def validate_subscription(subscription: dict) -> dict:
    endpoint = subscription.get("endpoint", "")
    if not isinstance(endpoint, str) or len(endpoint) > 3000:
        raise ValueError("Некорректная подписка уведомлений")
    url = urlparse(endpoint)
    host = url.hostname or ""
    allowed = host in {"fcm.googleapis.com", "updates.push.services.mozilla.com", "web.push.apple.com"}
    allowed = allowed or host.endswith(".push.apple.com") or host.endswith(".notify.windows.com")
    if not allowed or url.scheme != "https" or url.port not in {None, 443} or url.username or url.password or url.fragment:
        raise ValueError("Неподдерживаемый адрес сервиса уведомлений")
    keys = subscription.get("keys", {})
    if not isinstance(keys, dict):
        raise ValueError("Некорректные ключи подписки")
    try:
        public = keys.get("p256dh", "")
        auth = keys.get("auth", "")
        if not isinstance(public, str) or not isinstance(auth, str) or len(public) > 100 or len(auth) > 30:
            raise ValueError
        decoded = base64.urlsafe_b64decode(public + "=" * (-len(public) % 4))
        ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), decoded)
        if len(base64.urlsafe_b64decode(auth + "=" * (-len(auth) % 4))) != 16:
            raise ValueError
    except (ValueError, TypeError) as exc:
        raise ValueError("Некорректные ключи подписки") from exc
    return {"endpoint": endpoint, "keys": {"p256dh": public, "auth": auth}}


class DirectSession(requests.Session):
    def __init__(self):
        super().__init__()
        self.trust_env = False

    def request(self, *args, **kwargs):
        kwargs["allow_redirects"] = False
        return super().request(*args, **kwargs)


def send(subscription: dict, notification_id: str, kind: str) -> int:
    subscription = validate_subscription(subscription)
    # Lock screens never expose descriptions, names, addresses or chat text.
    body = {"new_match": "Появилось похожее объявление. Откройте кабинет.",
            "chat_message": "Вам ответили в чате по вещи.",
            "support_reply": "Поддержка ответила на ваше обращение."}.get(kind, "Есть обновление по вашему обращению.")
    data = json.dumps({"title": "Бюро находок", "body": body, "tag": notification_id,
                       "url": "/app/?action=notifications"}, ensure_ascii=False)
    with DirectSession() as session:
        try:
            response = webpush(subscription_info=subscription, data=data,
                vapid_private_key=vapid_keys()[1], vapid_claims={"sub": "https://edinburo.ru"},
                ttl=86400, timeout=10, requests_session=session,
                headers={"Topic": notification_id.replace("-", "")})
            return response.status_code
        except WebPushException as exc:
            return exc.response.status_code if exc.response is not None else 503


async def deliver_pending(db) -> None:
    now = datetime.now(UTC)
    cutoff = now - timedelta(days=1)
    missing = (await db.execute(select(Notification.id, PushDevice.id).join(
        PushDevice, and_(PushDevice.user_id == Notification.user_id, PushDevice.platform == PLATFORM,
                         PushDevice.status == "active", Notification.created_at >= PushDevice.created_at)
    ).outerjoin(PushDelivery, and_(PushDelivery.notification_id == Notification.id,
                                  PushDelivery.device_id == PushDevice.id))
        .where(Notification.created_at >= cutoff, Notification.read_at.is_(None), PushDelivery.id.is_(None))
        .order_by(Notification.created_at, PushDevice.id).limit(100))).all()
    for notification_id, device_id in missing:
        db.add(PushDelivery(notification_id=notification_id, device_id=device_id, next_attempt_at=now))
    await db.commit()
    pending = list(await db.scalars(select(PushDelivery).where(
        PushDelivery.status == "pending", PushDelivery.next_attempt_at <= now
    ).order_by(PushDelivery.next_attempt_at).limit(10)))
    for delivery in pending:
        note = await db.get(Notification, delivery.notification_id)
        device = await db.get(PushDevice, delivery.device_id)
        user = await db.get(User, note.user_id) if note else None
        if (not note or not device or not user or user.status != "active" or device.status != "active"
                or device.user_id != note.user_id or note.read_at or note.created_at.replace(tzinfo=UTC) < cutoff):
            delivery.status = "skipped"
            await db.commit()
            continue
        delivery.attempts += 1
        delivery.next_attempt_at = now + timedelta(seconds=min(3600, 60 * 2 ** delivery.attempts))
        await db.commit()  # A crash leaves a retryable attempt, never loses the notification.
        try:
            result = await asyncio.to_thread(send, decrypt_json(device.token_cipher), str(note.id), note.kind)
        except (ValueError, requests.RequestException):
            result = 503
        if 200 <= result < 300:
            delivery.status = "sent"
        elif result in {404, 410}:
            device.status = "expired"
            delivery.status = "expired"
        elif delivery.attempts >= 5 or (result < 500 and result not in {408, 429}):
            delivery.status = "failed"
        await db.commit()
