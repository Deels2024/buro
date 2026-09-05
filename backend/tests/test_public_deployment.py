"""Acceptance logic tested with actual transport/JSON failures from production."""
import importlib.util
import json
import socket
import ssl
from pathlib import Path
from urllib.error import URLError

import pytest

spec = importlib.util.spec_from_file_location("public_check", Path(__file__).resolve().parents[2] / "scripts/check-public.py")
public_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(public_check)
SHA = "a" * 40


def healthy():
    return {
        "site": {"ok": True, "body": "<html>Сайт</html>"},
        "admin": {"ok": True, "body": "<html>Админка</html>"},
        "api": {"ok": True, "body": json.dumps({"status": "ready", "database": "ok", "redis": "ok", "worker": "ok", "sms": "configured", "storage_transport": "https", "release_sha": SHA})},
        "web_release": {"ok": True, "body": SHA + "\n"},
        "robots": {"ok": True, "body": "Sitemap: https://edinburo.ru/sitemap.xml"},
        "sitemap": {"ok": True, "body": '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://edinburo.ru/</loc></url></urlset>'},
    }


def test_healthy_production_is_accepted():
    assert all(check["ok"] for check in public_check.evaluate(healthy(), SHA))


@pytest.mark.parametrize("component,value", [
    ("admin", {"ok": False, "reason": "dns_unavailable"}),
    ("api", {"ok": True, "body": "{bad json}"}),
    ("api", {"ok": True, "body": "[]"}),
    ("web_release", {"ok": True, "body": "b" * 40}),
    ("sitemap", {"ok": True, "body": "<html>server error</html>"}),
    ("robots", {"ok": True, "body": "Sitemap: http://old.example/sitemap.xml"}),
])
def test_partial_release_is_rejected(component, value):
    responses = healthy()
    responses[component] = value
    assert not all(check["ok"] for check in public_check.evaluate(responses, SHA))


def test_worker_failure_and_stale_release_fail_acceptance():
    responses = healthy()
    health = json.loads(responses["api"]["body"])
    health["worker"] = "unavailable"
    responses["api"]["body"] = json.dumps(health)
    checks = public_check.evaluate(responses, "b" * 40)
    assert {check["check"] for check in checks if not check["ok"]} == {"api_worker", "api_release"}


@pytest.mark.parametrize("reason,expected", [(socket.gaierror("unknown"), "dns_unavailable"), (ssl.SSLError("certificate"), "tls_error")])
def test_transport_error_is_reported_without_hiding_it(monkeypatch, reason, expected):
    def fail(*args, **kwargs):
        raise URLError(reason)
    monkeypatch.setattr(public_check, "urlopen", fail)
    assert public_check.fetch(public_check.ADMIN) == {"ok": False, "reason": expected}
