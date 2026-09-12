import logging
import math
from typing import Literal

import httpx
from fastapi import HTTPException

from app.core.config import settings
from app.services.openai_client import openai_proxy_url

# Provider keys and private address queries are URL parameters: never log URLs.
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)


MapsRoute = Literal["auto", "ipv4", "proxy"]


class MapsProviderError(HTTPException):
    def __init__(self, detail: str, *, reason: str, provider_status: int | None = None, status_code: int = 503):
        super().__init__(status_code, detail)
        self.reason = reason
        self.provider_status = provider_status


def rejection_reason(response: httpx.Response) -> str:
    # Return only a bounded classification. Provider bodies can contain API keys.
    text = response.text[:4096].lower()
    if any(value in text for value in ("referer", "referrer", "domain not allowed")):
        return "referer_restricted"
    if any(value in text for value in ("ip address", "ip-address", "ip not allowed", "ip is not allowed")):
        return "ip_restricted"
    if any(value in text for value in ("invalid key", "invalid api key", "invalid apikey", "apikey is invalid", "key not found")):
        return "invalid_key"
    if response.status_code == 429:
        return "rate_limit"
    return "access_denied"


async def provider_request(service: str, params: dict, *, route: MapsRoute = "ipv4") -> dict:
    if service not in {"suggest", "geocoder"} or route not in {"auto", "ipv4", "proxy"}:
        raise ValueError("Unknown maps service or route")
    key = settings.yandex_suggest_api_key if service == "suggest" else settings.yandex_geocoder_api_key
    if not key:
        raise MapsProviderError("Поиск адресов пока недоступен. Введите адрес вручную. [MAPS_CONFIG]", reason="missing_key")
    url = "https://suggest-maps.yandex.ru/v1/suggest" if service == "suggest" else "https://geocode-maps.yandex.ru/v1/"
    proxy = None
    if route == "proxy":
        try:
            if not settings.openai_proxy_address.strip():
                raise ValueError("No configured proxy")
            proxy = openai_proxy_url(settings)
        except ValueError:
            raise MapsProviderError("Маршрут карт не настроен. [MAPS_PROXY_CONFIG]", reason="proxy_config") from None
    try:
        # Select the same outbound IPv4 family as SMS. No listening socket is opened.
        transport = httpx.AsyncHTTPTransport(
            proxy=proxy, local_address="0.0.0.0" if route == "ipv4" else None,  # nosec B104
            retries=0, trust_env=False,
        )
        async with httpx.AsyncClient(timeout=httpx.Timeout(8, connect=5), transport=transport, trust_env=False) as client:
            response = await client.get(url, params={**params, "apikey": key})
        if response.status_code in (401, 403):
            raise MapsProviderError(
                "Сервис адресов отклонил ключ или его ограничения. Введите адрес вручную. [MAPS_ACCESS]",
                reason=rejection_reason(response), provider_status=response.status_code,
            )
        if response.status_code == 429:
            raise MapsProviderError(
                "Лимит поиска адресов исчерпан. Можно ввести адрес вручную. [MAPS_LIMIT]",
                reason="rate_limit", provider_status=429, status_code=429,
            )
        response.raise_for_status()
        result = response.json()
        if not isinstance(result, dict):
            raise ValueError("Invalid provider response")
        return result
    except httpx.TimeoutException as exc:
        phase = "connect_timeout" if isinstance(exc, httpx.ConnectTimeout) else "read_timeout" if isinstance(exc, httpx.ReadTimeout) else "timeout"
        raise MapsProviderError("Сервис адресов не ответил вовремя. Введите адрес вручную. [MAPS_TIMEOUT]", reason=phase) from None
    except httpx.HTTPStatusError as exc:
        raise MapsProviderError("Сервис адресов вернул ошибку. Введите адрес вручную. [MAPS_UNAVAILABLE]",
                                reason="provider_http_error", provider_status=exc.response.status_code) from None
    except httpx.RequestError:
        raise MapsProviderError("Не удалось подключиться к сервису адресов. Введите адрес вручную. [MAPS_NETWORK]", reason="network_error") from None
    except ValueError:
        raise MapsProviderError("Сервис вернул неполный адрес. Введите адрес вручную. [MAPS_FORMAT]", reason="invalid_response") from None


def parse_suggestions(data: dict) -> list[dict]:
    results = []
    for item in data.get("results", [])[:5]:
        title = item.get("title", {}).get("text", "")
        if not title:
            continue
        address = item.get("address", {})
        components = address.get("component", [])
        city = next((c.get("name", "") for c in components
                     if "locality" in [k.lower() for k in c.get("kind", [])]), "")
        subtitle = item.get("subtitle", {}).get("text", "")
        results.append({"title": title, "subtitle": subtitle, "city": city,
                        "query": address.get("formatted_address") or ", ".join(filter(None, [subtitle, title])),
                        "uri": item.get("uri", "")})
    return results


def parse_geocode(data: dict) -> dict:
    try:
        members = data["response"]["GeoObjectCollection"]["featureMember"]
        if not members:
            raise HTTPException(404, "Адрес не найден. Уточните запрос или выберите точку на карте.")
        obj = members[0]["GeoObject"]
        lon, lat = map(float, obj["Point"]["pos"].split())
        if not all(map(math.isfinite, (lat, lon))) or not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise ValueError("Invalid coordinates")
        meta = obj["metaDataProperty"]["GeocoderMetaData"]
        parts = meta.get("Address", {}).get("Components", [])
        city = next((c["name"] for c in parts if c.get("kind") == "locality"), "")
        provinces = [c["name"] for c in parts if c.get("kind") == "province"]
        return {"latitude": lat, "longitude": lon, "region": city or (provinces[-1] if provinces else ""),
                "address": meta.get("text", obj.get("name", "")), "precision": meta.get("precision", "other")}
    except (KeyError, TypeError, ValueError, IndexError) as exc:
        raise HTTPException(503, "Сервис вернул неполный адрес. Выберите место вручную. [MAPS_FORMAT]") from exc
