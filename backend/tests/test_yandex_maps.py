from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import httpx
import pytest
from fastapi import HTTPException, Response
from pydantic import ValidationError

from app.api.routes import maps
from app.services import yandex_maps, yandex_probe


def test_geocoder_longitude_latitude_order_and_city():
    data = {"response": {"GeoObjectCollection": {"featureMember": [{"GeoObject": {
        "Point": {"pos": "30.31 59.93"},
        "metaDataProperty": {"GeocoderMetaData": {"text": "Санкт-Петербург, Невский проспект, 1",
            "precision": "exact", "Address": {"Components": [
                {"kind": "province", "name": "Санкт-Петербург"},
                {"kind": "locality", "name": "Санкт-Петербург"}]}}}}}]}}}
    result = yandex_maps.parse_geocode(data)
    assert result["latitude"] == 59.93
    assert result["longitude"] == 30.31
    assert result["region"] == "Санкт-Петербург"


def test_suggestion_keeps_city_and_unique_provider_reference():
    result = yandex_maps.parse_suggestions({"results": [{"title": {"text": "Выборг"},
        "subtitle": {"text": "Ленинградская область"}, "uri": "ymapsbm1://geo?data=test",
        "address": {"formatted_address": "Россия, Ленинградская область, Выборг",
                    "component": [{"kind": ["LOCALITY"], "name": "Выборг"}]}}]})
    assert result[0]["city"] == "Выборг"
    assert result[0]["uri"].startswith("ymapsbm1://")
    assert "Ленинградская" in result[0]["query"]


@pytest.mark.parametrize("payload", [{}, {"latitude": 55}, {"latitude": 91, "longitude": 30},
    {"query": "Москва", "latitude": 55, "longitude": 30}, {"uri": "https://attacker.invalid"}])
def test_invalid_or_ambiguous_location_rejected(payload):
    with pytest.raises(ValidationError):
        maps.ResolveInput(**payload)


async def test_reverse_geocoder_sends_lon_first(monkeypatch):
    request = AsyncMock(return_value={})
    monkeypatch.setattr(maps, "budget", AsyncMock())
    monkeypatch.setattr(maps, "provider_request", request)
    monkeypatch.setattr(maps, "parse_geocode", lambda data: {})
    await maps.resolve(maps.ResolveInput(latitude=59.9, longitude=30.3), SimpleNamespace(id="user"), Response())
    assert request.call_args.args[1]["geocode"] == "30.3,59.9"


async def test_budget_prevents_provider_request(monkeypatch):
    request = AsyncMock()
    monkeypatch.setattr(maps, "rate_limit", AsyncMock(return_value=False))
    monkeypatch.setattr(maps, "provider_request", request)
    with pytest.raises(HTTPException) as exc:
        await maps.suggest(maps.SuggestInput(query="Москва"), SimpleNamespace(id="user"), Response())
    assert exc.value.status_code == 429
    request.assert_not_awaited()


async def test_provider_rejection_does_not_expose_key(monkeypatch):
    monkeypatch.setattr(yandex_maps.settings, "yandex_suggest_api_key", "private-key")
    client = AsyncMock()
    client.__aenter__.return_value = client
    client.get.return_value = httpx.Response(403, text="private-key secret body",
        request=httpx.Request("GET", "https://suggest-maps.yandex.ru/"))
    factory = Mock(return_value=client)
    monkeypatch.setattr(yandex_maps.httpx, "AsyncClient", factory)
    with pytest.raises(HTTPException) as exc:
        await yandex_maps.provider_request("suggest", {"text": "Москва"})
    assert "MAPS_ACCESS" in exc.value.detail
    assert "private-key" not in exc.value.detail
    assert factory.call_args.kwargs["trust_env"] is False


@pytest.mark.parametrize("rejected", [False, True])
async def test_release_probe_checks_real_results_without_logging_keys(monkeypatch, capsys, rejected):
    monkeypatch.setattr(yandex_probe.settings, "environment", "production")
    for name in ("yandex_maps_js_api_key", "yandex_geocoder_api_key", "yandex_suggest_api_key"):
        monkeypatch.setattr(yandex_probe.settings, name, "private-test-key")
    monkeypatch.setattr(yandex_probe, "budget", AsyncMock())
    request = AsyncMock(return_value={})
    if rejected:
        request.side_effect = HTTPException(503, "[MAPS_ACCESS] private-test-key")
    monkeypatch.setattr(yandex_probe, "provider_request", request)
    monkeypatch.setattr(yandex_probe, "parse_geocode", lambda data: {"region": "Москва"})
    monkeypatch.setattr(yandex_probe, "parse_suggestions", lambda data: [{"title": "Москва"}])
    if rejected:
        with pytest.raises(SystemExit):
            await yandex_probe.main()
    else:
        await yandex_probe.main()
    output = capsys.readouterr().out
    assert '"yandex_maps": "failed"' in output if rejected else '"yandex_maps": "ok"' in output
    assert "private-test-key" not in output
    assert request.await_count == 2


@pytest.mark.parametrize("route", ["auto", "ipv4", "proxy"])
async def test_maps_route_is_explicit_and_ignores_environment_proxy(monkeypatch, route):
    monkeypatch.setenv("HTTPS_PROXY", "http://unrelated.invalid:8080")
    monkeypatch.setattr(yandex_maps.settings, "yandex_suggest_api_key", "test-private-key")
    monkeypatch.setattr(yandex_maps.settings, "openai_proxy_address", "proxy.example")
    monkeypatch.setattr(yandex_maps, "openai_proxy_url", lambda _: "http://user:password@proxy.example:8080")
    calls = []

    def respond(request):
        calls.append(request)
        assert request.url.host == "suggest-maps.yandex.ru"
        assert request.url.params["apikey"] == "test-private-key"
        return httpx.Response(200, json={"results": []})

    transport = Mock(side_effect=lambda **kwargs: httpx.MockTransport(respond))
    monkeypatch.setattr(yandex_maps.httpx, "AsyncHTTPTransport", transport)
    assert await yandex_maps.provider_request("suggest", {"text": "Москва"}, route=route) == {"results": []}
    assert len(calls) == 1
    assert transport.call_args.kwargs == {
        "proxy": "http://user:password@proxy.example:8080" if route == "proxy" else None,
        "local_address": "0.0.0.0" if route == "ipv4" else None,
        "retries": 0, "trust_env": False,
    }


@pytest.mark.parametrize("body,reason", [
    ("Invalid api key: test-private-key", "invalid_key"),
    ("IP address is not allowed for test-private-key", "ip_restricted"),
    ("Referer is not allowed for test-private-key", "referer_restricted"),
    ("Forbidden test-private-key", "access_denied"),
])
async def test_access_rejection_is_classified_without_retry_or_key_disclosure(monkeypatch, body, reason):
    monkeypatch.setattr(yandex_maps.settings, "yandex_suggest_api_key", "test-private-key")
    calls = []

    def respond(request):
        calls.append(request)
        return httpx.Response(403, text=body)

    monkeypatch.setattr(yandex_maps.httpx, "AsyncHTTPTransport", lambda **kwargs: httpx.MockTransport(respond))
    with pytest.raises(yandex_maps.MapsProviderError) as exc:
        await yandex_maps.provider_request("suggest", {"text": "Москва"})
    assert exc.value.reason == reason
    assert exc.value.provider_status == 403
    assert "test-private-key" not in str(exc.value)
    assert len(calls) == 1


async def test_network_timeout_is_not_reported_as_a_bad_key(monkeypatch):
    monkeypatch.setattr(yandex_maps.settings, "yandex_suggest_api_key", "test-private-key")

    def respond(request):
        raise httpx.ConnectTimeout("test-private-key in private URL", request=request)

    monkeypatch.setattr(yandex_maps.httpx, "AsyncHTTPTransport", lambda **kwargs: httpx.MockTransport(respond))
    with pytest.raises(yandex_maps.MapsProviderError) as exc:
        await yandex_maps.provider_request("suggest", {"text": "Москва"})
    assert exc.value.reason == "connect_timeout"
    assert exc.value.provider_status is None
    assert "MAPS_TIMEOUT" in exc.value.detail
    assert "test-private-key" not in str(exc.value)
