from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock

import httpx
import pytest
from fastapi import HTTPException, Response
from pydantic import ValidationError

from app.api.routes import maps
from app.services import yandex_maps


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
