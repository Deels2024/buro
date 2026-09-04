"""Post-install smoke test through the public gateway.

Uses only the Python standard library so it can run inside the API image.
"""

from __future__ import annotations

import hashlib
import io
import json
import os
import time
from datetime import UTC, datetime
from http.cookiejar import CookieJar
from urllib.error import HTTPError
from urllib.parse import urlsplit, urlunsplit
from urllib.request import HTTPCookieProcessor, Request, build_opener

from PIL import Image

from app.core.config import settings

BASE_URL = os.getenv("SMOKE_BASE_URL", "http://gateway").rstrip("/")
PUBLIC_HOST = os.getenv("SMOKE_PUBLIC_HOST", "edinburo.ru")
ADMIN_HOST = os.getenv("SMOKE_ADMIN_HOST", "admin.edinburo.ru")


def request_json(
    opener,
    path: str,
    *,
    host: str,
    method: str = "GET",
    payload: dict | None = None,
):
    body = json.dumps(payload).encode() if payload is not None else None
    request = Request(
        f"{BASE_URL}{path}",
        data=body,
        method=method,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Host": host,
        },
    )
    try:
        with opener.open(request, timeout=20) as response:
            return response.status, json.load(response)
    except HTTPError as exc:
        try:
            detail = json.load(exc)
        except Exception:
            detail = {"detail": exc.reason}
        raise RuntimeError(f"{method} {path}: HTTP {exc.code}: {detail}") from exc


def main() -> None:
    opener = build_opener(HTTPCookieProcessor(CookieJar()))

    status, health = request_json(opener, "/v1/health/ready", host=PUBLIC_HOST)
    if status != 200 or health.get("status") != "ready":
        raise RuntimeError(f"Health check failed: {health}")

    phone = settings.bootstrap_admin_phone
    _, requested = request_json(
        opener,
        "/api/session/request-code",
        host=ADMIN_HOST,
        method="POST",
        payload={"phone": phone},
    )
    code = requested.get("dev_code")
    if not code:
        raise RuntimeError("Development OTP was not returned")

    _, verified = request_json(
        opener,
        "/api/session/verify-code",
        host=ADMIN_HOST,
        method="POST",
        payload={"phone": phone, "code": code, "device_name": "Install smoke test"},
    )
    if verified.get("mfa_required"):
        print("Smoke test: health and SMS authentication are ready; existing administrator requires 2FA")
        return
    if not verified.get("authenticated"):
        raise RuntimeError(f"Administrator login failed: {verified}")

    _, session = request_json(opener, "/api/session/status", host=ADMIN_HOST)
    if not session.get("authenticated") or session.get("user", {}).get("role") not in {
        "admin",
        "moderator",
    }:
        raise RuntimeError(f"Administrator session failed: {session}")

    _, dashboard = request_json(
        opener,
        "/api/backend/admin/dashboard",
        host=ADMIN_HOST,
    )
    if "open_cases" not in dashboard or "pending_listings" not in dashboard:
        raise RuntimeError(f"Admin API returned an unexpected response: {dashboard}")

    check_photo_workflow(opener)

    _, logged_out = request_json(
        opener,
        "/api/session/logout",
        host=ADMIN_HOST,
        method="POST",
        payload={},
    )
    if logged_out.get("authenticated") is not False:
        raise RuntimeError(f"Logout failed: {logged_out}")

    print("Smoke test passed: gateway -> admin session -> backend dashboard -> logout")


def signed_storage_request(url: str, *, data: bytes | None = None):
    # The public endpoint may be localhost on the CI host. Reach the same MinIO
    # from the API container while retaining the signed Host, path and query.
    public = urlsplit(url)
    internal = urlsplit(settings.s3_endpoint)
    target = urlunsplit((internal.scheme, internal.netloc, public.path, public.query, ""))
    headers = {"Host": public.netloc}
    if data is not None:
        headers["Content-Type"] = "image/jpeg"
    return build_opener().open(Request(target, data=data, method="PUT" if data is not None else "GET", headers=headers), timeout=20)


def check_photo_workflow(opener) -> None:
    image = Image.new("RGB", (64, 48), color=(30, 80, 120))
    exif = Image.Exif()
    exif[270] = "CI private image metadata"
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", exif=exif)
    content = buffer.getvalue()
    digest = hashlib.sha256(content).hexdigest()
    _, signed = request_json(opener, "/api/backend/media/presign", host=ADMIN_HOST, method="POST", payload={
        "filename":"smoke.jpg", "mime_type":"image/jpeg", "size_bytes":len(content), "purpose":"listing",
    })
    with signed_storage_request(signed["upload_url"], data=content) as uploaded:
        if uploaded.status != 200:
            raise RuntimeError("Signed photo upload failed")
    _, media = request_json(opener, "/api/backend/media/complete", host=ADMIN_HOST, method="POST", payload={
        "object_key":signed["object_key"], "mime_type":"image/jpeg", "size_bytes":len(content), "sha256":digest, "purpose":"listing",
    })
    _, listing = request_json(opener, "/api/backend/listings", host=ADMIN_HOST, method="POST", payload={
        "kind":"found", "title":"Проверка обработки фотографии", "description":"Тестовая карточка только в изолированном CI-стеке.",
        "category":"other", "event_at":datetime.now(UTC).isoformat(), "location":{"region":"Тестовый город"}, "media_ids":[media["id"]],
    })
    for _ in range(30):
        _, current = request_json(opener, f'/api/backend/listings/{listing["id"]}/manage', host=ADMIN_HOST)
        ready = next((item for item in current["media"] if item["status"] == "ready"), None)
        if ready:
            with signed_storage_request(ready["download_url"]) as downloaded:
                cleaned = downloaded.read()
            with Image.open(io.BytesIO(cleaned)) as decoded:
                if decoded.getexif() or decoded.size != (64, 48):
                    raise RuntimeError("Photo metadata was not removed correctly")
            if hashlib.sha256(cleaned).hexdigest() == digest:
                raise RuntimeError("Worker did not rewrite the uploaded image")
            print("Photo workflow passed: signed upload -> completion -> worker -> metadata-free download")
            return
        if any(item["status"] in {"rejected", "blocked"} for item in current["media"]):
            raise RuntimeError("Worker rejected the valid test photo")
        time.sleep(1)
    raise RuntimeError("Worker did not finish processing the test photo")


if __name__ == "__main__":
    main()
