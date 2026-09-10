import logging
import math

import httpx
from fastapi import HTTPException

from app.core.config import settings

# Provider keys and private address queries are URL parameters: never log URLs.
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpcore").setLevel(logging.WARNING)


async def provider_request(service: str, params: dict) -> dict:
    key = settings.yandex_suggest_api_key if service == "suggest" else settings.yandex_geocoder_api_key
    if not key:
        raise HTTPException(503, "Поиск адресов пока недоступен. Введите адрес вручную. [MAPS_CONFIG]")
    url = "https://suggest-maps.yandex.ru/v1/suggest" if service == "suggest" else "https://geocode-maps.yandex.ru/v1/"
    try:
        async with httpx.AsyncClient(timeout=8, trust_env=False) as client:
            response = await client.get(url, params={**params, "apikey": key})
        if response.status_code in (401, 403):
            raise HTTPException(503, "Сервис адресов отклонил ключ или его ограничения. Введите адрес вручную. [MAPS_ACCESS]")
        if response.status_code == 429:
            raise HTTPException(429, "Лимит поиска адресов исчерпан. Можно ввести адрес вручную. [MAPS_LIMIT]")
        response.raise_for_status()
        result = response.json()
        if not isinstance(result, dict):
            raise ValueError("Invalid provider response")
        return result
    except (httpx.HTTPError, ValueError) as exc:
        raise HTTPException(503, "Не удалось получить адрес. Попробуйте позже или введите вручную. [MAPS_UNAVAILABLE]") from exc


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
