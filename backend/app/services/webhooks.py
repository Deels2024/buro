import asyncio
import hashlib
import hmac
import ipaddress
import json
import socket
from datetime import UTC, datetime, timedelta
from urllib.parse import urlparse
from uuid import UUID, uuid4

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import decrypt_json
from app.db.models import IntegrationWebhook, WebhookDelivery
from app.services.cache import enqueue


def validate_webhook_url(url: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("Вебхук должен использовать публичный HTTPS URL без встроенных учётных данных")
    if parsed.hostname.lower() in {"localhost", "localhost.localdomain"}:
        raise ValueError("Локальные адреса запрещены")
    try:
        address = ipaddress.ip_address(parsed.hostname)
    except ValueError:
        return
    if not address.is_global:
        raise ValueError("Приватные и служебные адреса запрещены")


async def assert_safe_webhook_target(url: str) -> None:
    validate_webhook_url(url)
    host = urlparse(url).hostname
    records = await asyncio.to_thread(socket.getaddrinfo, host, 443, type=socket.SOCK_STREAM)
    for record in records:
        if not ipaddress.ip_address(record[4][0]).is_global:
            raise ValueError("Домен вебхука указывает на приватный или служебный адрес")


async def create_deliveries(
    db: AsyncSession,
    *,
    organization_id: UUID | None,
    event_type: str,
    payload: dict,
) -> list[UUID]:
    if not organization_id:
        return []
    hooks = list(
        await db.scalars(
            select(IntegrationWebhook).where(
                IntegrationWebhook.organization_id == organization_id,
                IntegrationWebhook.status == "active",
            )
        )
    )
    event_id = uuid4()
    deliveries = []
    for hook in hooks:
        if event_type not in hook.events:
            continue
        delivery = WebhookDelivery(
            webhook_id=hook.id,
            event_id=event_id,
            event_type=event_type,
            payload={
                "id": str(event_id),
                "type": event_type,
                "created_at": datetime.now(UTC).isoformat(),
                "data": payload,
            },
        )
        db.add(delivery)
        deliveries.append(delivery)
    await db.flush()
    return [item.id for item in deliveries]


async def enqueue_deliveries(delivery_ids: list[UUID]) -> None:
    for delivery_id in delivery_ids:
        await enqueue("deliver_webhook", {"delivery_id": str(delivery_id)})


async def deliver(db: AsyncSession, delivery_id: UUID) -> None:
    delivery = await db.get(WebhookDelivery, delivery_id)
    if not delivery or delivery.status == "delivered":
        return
    webhook = await db.get(IntegrationWebhook, delivery.webhook_id)
    if not webhook or webhook.status != "active":
        delivery.status = "cancelled"
        await db.commit()
        return
    body = json.dumps(delivery.payload, ensure_ascii=False, separators=(",", ":")).encode()
    secret = decrypt_json(webhook.secret_cipher)["secret"].encode()
    timestamp = str(int(datetime.now(UTC).timestamp()))
    signature = hmac.new(secret, timestamp.encode() + b"." + body, hashlib.sha256).hexdigest()
    delivery.attempts += 1
    try:
        await assert_safe_webhook_target(webhook.url)
        async with httpx.AsyncClient(timeout=settings.webhook_timeout_seconds) as client:
            response = await client.post(
                webhook.url,
                content=body,
                headers={
                    "Content-Type": "application/json",
                    "X-Bureau-Event": delivery.event_type,
                    "X-Bureau-Event-ID": str(delivery.event_id),
                    "X-Bureau-Timestamp": timestamp,
                    "X-Bureau-Signature": f"sha256={signature}",
                },
            )
        delivery.response_status = response.status_code
        delivery.response_excerpt = response.text[:500]
        if 200 <= response.status_code < 300:
            delivery.status = "delivered"
            delivery.delivered_at = datetime.now(UTC)
            webhook.last_success_at = datetime.now(UTC)
            webhook.failure_count = 0
        else:
            raise RuntimeError(f"HTTP {response.status_code}")
    except Exception as exc:
        webhook.last_failure_at = datetime.now(UTC)
        webhook.failure_count += 1
        delivery.response_excerpt = delivery.response_excerpt or str(exc)[:500]
        if delivery.attempts >= settings.webhook_max_attempts:
            delivery.status = "failed"
        else:
            delivery.status = "retrying"
            delay = min(3600, 2 ** delivery.attempts * 15)
            delivery.next_attempt_at = datetime.now(UTC) + timedelta(seconds=delay)
    await db.commit()
