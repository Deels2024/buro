import base64
import hashlib
import logging
from uuid import uuid4

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint

from app.core.config import settings
from app.core.security import hash_secret
from app.services.cache import get_json, set_json

logger = logging.getLogger(__name__)


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        supplied = request.headers.get(settings.request_id_header, "")
        request_id = supplied[:80] if supplied and supplied.replace("-", "").isalnum() else str(uuid4())
        request.state.request_id = request_id
        response = await call_next(request)
        response.headers[settings.request_id_header] = request_id
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault("Permissions-Policy", "camera=(self), microphone=(self), geolocation=(self)")
        return response


class IdempotencyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        # OTP, MFA and refresh credentials are single-use. A cached successful
        # response must never reissue tokens after those credentials are spent.
        if request.url.path.startswith("/v1/auth/"):
            return await call_next(request)
        key = request.headers.get("Idempotency-Key")
        if request.method not in {"POST", "PUT", "PATCH", "DELETE"} or not key:
            return await call_next(request)
        if len(key) < 8 or len(key) > 128:
            return Response(
                content='{"detail":"Idempotency-Key должен содержать от 8 до 128 символов"}',
                status_code=422,
                media_type="application/json",
            )
        body = await request.body()
        body_hash = hashlib.sha256(body).hexdigest()
        subject = request.headers.get("Authorization", "anonymous")
        cache_key = f"idempotency:{hash_secret(f'{subject}|{request.method}|{request.url.path}|{key}') }"
        try:
            cached = await get_json(cache_key)
        except Exception:
            logger.warning("Idempotency cache read failed; processing request normally", exc_info=True)
            cached = None
        if cached:
            if cached["body_hash"] != body_hash:
                return Response(
                    content='{"detail":"Этот Idempotency-Key уже использован с другим запросом"}',
                    status_code=409,
                    media_type="application/json",
                )
            headers = dict(cached.get("headers", {}))
            headers["X-Idempotent-Replay"] = "true"
            return Response(
                content=base64.b64decode(cached["body"]),
                status_code=cached["status_code"],
                headers=headers,
                media_type=cached.get("media_type"),
            )

        response = await call_next(request)
        response_body = b"".join([chunk async for chunk in response.body_iterator])
        content_type = response.headers.get("content-type", "application/json").split(";")[0]
        headers = {
            key: value
            for key, value in response.headers.items()
            if key.lower() in {"content-language", "location"}
        }
        if response.status_code < 500:
            try:
                await set_json(
                    cache_key,
                    {
                        "body_hash": body_hash,
                        "status_code": response.status_code,
                        "body": base64.b64encode(response_body).decode(),
                        "media_type": content_type,
                        "headers": headers,
                    },
                    ttl=24 * 3600,
                )
            except Exception:
                logger.warning("Idempotency response cache write failed", exc_info=True)
        return Response(
            content=response_body,
            status_code=response.status_code,
            headers=dict(response.headers),
            media_type=content_type,
        )
