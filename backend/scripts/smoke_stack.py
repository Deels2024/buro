"""Post-install smoke test through the public gateway.

Uses only the Python standard library so it can run inside the API image.
"""

from __future__ import annotations

import json
import os
from http.cookiejar import CookieJar
from urllib.error import HTTPError
from urllib.request import HTTPCookieProcessor, Request, build_opener

from app.core.config import settings

BASE_URL = os.getenv("SMOKE_BASE_URL", "http://gateway").rstrip("/")


def request_json(opener, path: str, *, method: str = "GET", payload: dict | None = None):
    body = json.dumps(payload).encode() if payload is not None else None
    request = Request(
        f"{BASE_URL}{path}",
        data=body,
        method=method,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
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

    status, health = request_json(opener, "/v1/health/ready")
    if status != 200 or health.get("status") != "ready":
        raise RuntimeError(f"Health check failed: {health}")

    phone = settings.bootstrap_admin_phone
    _, requested = request_json(
        opener,
        "/api/session/request-code",
        method="POST",
        payload={"phone": phone},
    )
    code = requested.get("dev_code")
    if not code:
        raise RuntimeError("Development OTP was not returned")

    _, verified = request_json(
        opener,
        "/api/session/verify-code",
        method="POST",
        payload={"phone": phone, "code": code, "device_name": "Install smoke test"},
    )
    if verified.get("mfa_required"):
        print("Smoke test: health and SMS authentication are ready; existing administrator requires 2FA")
        return
    if not verified.get("authenticated"):
        raise RuntimeError(f"Administrator login failed: {verified}")

    _, session = request_json(opener, "/api/session/status")
    if not session.get("authenticated") or session.get("user", {}).get("role") not in {
        "admin",
        "moderator",
    }:
        raise RuntimeError(f"Administrator session failed: {session}")

    _, dashboard = request_json(opener, "/api/backend/admin/dashboard")
    if "open_cases" not in dashboard or "pending_listings" not in dashboard:
        raise RuntimeError(f"Admin API returned an unexpected response: {dashboard}")

    _, logged_out = request_json(opener, "/api/session/logout", method="POST", payload={})
    if logged_out.get("authenticated") is not False:
        raise RuntimeError(f"Logout failed: {logged_out}")

    print("Smoke test passed: gateway -> admin session -> backend dashboard -> logout")


if __name__ == "__main__":
    main()
