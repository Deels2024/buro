import json
from unittest.mock import AsyncMock

from fastapi import HTTPException

from app.services import yandex_diagnostics
from app.services.yandex_maps import MapsProviderError


async def test_diagnostics_compares_routes_using_only_a_public_city(monkeypatch):
    settings = yandex_diagnostics.settings
    for name in ("yandex_maps_js_api_key", "yandex_geocoder_api_key", "yandex_suggest_api_key"):
        monkeypatch.setattr(settings, name, "private-test-key")
    monkeypatch.setattr(settings, "openai_proxy_address", "private-proxy-address")
    budget = AsyncMock()
    monkeypatch.setattr(yandex_diagnostics, "budget", budget)
    monkeypatch.setattr(yandex_diagnostics, "parse_geocode", lambda _: {"region": "Москва"})
    monkeypatch.setattr(yandex_diagnostics, "parse_suggestions", lambda _: [{"title": "Москва"}])

    async def provider(service, params, *, route):
        assert params.get("geocode", params.get("text")) == "Москва"
        if route == "auto":
            raise MapsProviderError("private-test-key", reason="ip_restricted", provider_status=403)
        if route == "proxy":
            raise MapsProviderError("private-proxy-address", reason="connect_timeout")
        return {}

    request = AsyncMock(side_effect=provider)
    monkeypatch.setattr(yandex_diagnostics, "provider_request", request)
    result = await yandex_diagnostics.compare_routes()
    assert len(result["checks"]) == 6
    assert request.await_count == budget.await_count == 6
    for check in result["checks"]:
        assert check["ok"] is (check["route"] == "ipv4")
    assert "private-test-key" not in json.dumps(result)
    assert "private-proxy-address" not in json.dumps(result)


async def test_diagnostics_respects_daily_budget_before_any_provider_call(monkeypatch):
    for name in ("yandex_geocoder_api_key", "yandex_suggest_api_key"):
        monkeypatch.setattr(yandex_diagnostics.settings, name, "private-test-key")
    monkeypatch.setattr(yandex_diagnostics.settings, "openai_proxy_address", "")
    monkeypatch.setattr(yandex_diagnostics, "budget", AsyncMock(side_effect=HTTPException(429, "limit")))
    provider = AsyncMock()
    monkeypatch.setattr(yandex_diagnostics, "provider_request", provider)
    result = await yandex_diagnostics.compare_routes()
    assert len(result["checks"]) == 4
    assert all(check["reason"] == "local_budget" for check in result["checks"])
    provider.assert_not_awaited()
