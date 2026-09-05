#!/usr/bin/env python3
"""Read-only production acceptance checks; no credentials or paid API calls."""
import argparse
import json
import socket
import ssl
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from xml.etree import ElementTree

PUBLIC = "https://edinburo.ru"
ADMIN = "https://admin.edinburo.ru"
ENDPOINTS = {
    "site": PUBLIC + "/",
    "admin": ADMIN + "/",
    "api": PUBLIC + "/v1/health/ready",
    "web_release": PUBLIC + "/app/release-sha.txt",
    "robots": PUBLIC + "/robots.txt",
    "sitemap": PUBLIC + "/sitemap.xml",
}


def fetch(url):
    request = Request(url, headers={"User-Agent": "Bureau-Readiness/1.0", "Cache-Control": "no-cache"})
    try:
        with urlopen(request, timeout=12) as response:
            body = response.read(8 * 1024 * 1024 + 1)
            if len(body) > 8 * 1024 * 1024:
                return {"ok": False, "reason": "response_too_large"}
            return {"ok": response.status == 200, "status": response.status, "body": body.decode("utf-8")}
    except HTTPError as exc:
        return {"ok": False, "reason": "http_error", "status": exc.code}
    except URLError as exc:
        if isinstance(exc.reason, socket.gaierror):
            reason = "dns_unavailable"
        elif isinstance(exc.reason, ssl.SSLError):
            reason = "tls_error"
        else:
            reason = "connection_unavailable"
        return {"ok": False, "reason": reason}
    except (OSError, UnicodeError):
        return {"ok": False, "reason": "connection_or_encoding_error"}


def evaluate(responses, expected_release=None, preflight=False):
    checks = []

    def record(name, ok, reason):
        checks.append({"check": name, "ok": bool(ok), "reason": "ok" if ok else reason})

    for name, result in responses.items():
        record(name, result["ok"], result.get("reason", "unexpected_http_status"))
    if preflight:
        return checks

    api = responses.get("api", {})
    if api.get("ok"):
        try:
            health = json.loads(api["body"])
            if not isinstance(health, dict):
                raise TypeError("health must be an object")
        except (ValueError, KeyError, TypeError):
            health = {}
            record("api_json", False, "invalid_json")
        for key, value in {
            "status": "ready", "database": "ok", "redis": "ok",
            "worker": "ok", "sms": "configured", "storage_transport": "https",
        }.items():
            record("api_" + key, health.get(key) == value, "unexpected_" + key)
        sha = health.get("release_sha", "")
        valid_sha = isinstance(sha, str) and len(sha) == 40 and all(c in "0123456789abcdef" for c in sha)
        record("api_release", valid_sha and (not expected_release or sha == expected_release), "wrong_release")
        web = responses.get("web_release", {})
        if web.get("ok"):
            record("release_consistency", valid_sha and web["body"].strip() == sha, "frontend_backend_mismatch")
    if responses.get("robots", {}).get("ok"):
        record("robots_sitemap", "Sitemap: " + PUBLIC + "/sitemap.xml" in responses["robots"]["body"], "missing_canonical_sitemap")
    if responses.get("sitemap", {}).get("ok"):
        try:
            root = ElementTree.fromstring(responses["sitemap"]["body"])
            locations = [node.text for node in root.iter() if node.tag.rsplit("}", 1)[-1] == "loc"]
            record("sitemap_canonical", PUBLIC + "/" in locations and all(loc and loc.startswith(PUBLIC + "/") for loc in locations), "invalid_canonical_locations")
        except ElementTree.ParseError:
            record("sitemap_xml", False, "invalid_xml")
    return checks


def check_public(expected_release=None, preflight=False):
    endpoints = {k: v for k, v in ENDPOINTS.items() if not preflight or k in {"site", "admin"}}
    with ThreadPoolExecutor(max_workers=6) as pool:
        responses = dict(zip(endpoints, pool.map(fetch, endpoints.values()), strict=True))
    return evaluate(responses, expected_release, preflight)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-release")
    parser.add_argument("--preflight", action="store_true", help="Check site/admin reachability before any deployment")
    parser.add_argument("--attempts", type=int, choices=range(1, 13), default=1)
    parser.add_argument("--report", help="Write a JSON report without response bodies or credentials")
    args = parser.parse_args()
    if args.expected_release and (len(args.expected_release) != 40 or any(c not in "0123456789abcdef" for c in args.expected_release)):
        parser.error("expected release must be a full Git SHA")
    for attempt in range(1, args.attempts + 1):
        checks = check_public(args.expected_release, args.preflight)
        ok = all(item["ok"] for item in checks)
        report = {"ok": ok, "attempt": attempt, "checks": checks}
        print(json.dumps(report, ensure_ascii=False), flush=True)
        if ok or attempt == args.attempts:
            break
        time.sleep(5)
    if args.report:
        with open(args.report, "w", encoding="utf-8") as stream:
            json.dump(report, stream, ensure_ascii=False, indent=2)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
