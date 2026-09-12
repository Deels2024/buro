"""Bounded production checks: public city only, no keys or provider bodies in output."""
import asyncio
import time

from fastapi import HTTPException

from app.api.routes.maps import budget
from app.core.config import settings
from app.services.yandex_maps import (
    MapsProviderError,
    MapsRoute,
    parse_geocode,
    parse_suggestions,
    provider_request,
)


async def _check(service: str, route: MapsRoute) -> dict:
    result = {"service": service, "route": route, "ok": False, "http_status": None}
    started = time.monotonic()
    try:
        async with asyncio.timeout(12):
            await budget("route-diagnostics", service)
            if service == "geocoder":
                data = await provider_request(service, {
                    "geocode": "Москва", "lang": "ru_RU", "format": "json", "results": 1,
                }, route=route)
                valid = bool(parse_geocode(data)["region"])
            else:
                data = await provider_request(service, {
                    "text": "Москва", "types": "locality", "countries": "ru", "lang": "ru",
                    "results": 1, "print_address": 1, "attrs": "uri",
                }, route=route)
                valid = bool(parse_suggestions(data))
            result.update(ok=valid, http_status=200, reason="ok" if valid else "empty_result")
    except MapsProviderError as exc:
        result.update(reason=exc.reason, http_status=exc.provider_status)
    except HTTPException as exc:
        result["reason"] = "local_budget" if exc.status_code == 429 else "invalid_result"
    except TimeoutError:
        result["reason"] = "total_timeout"
    except Exception:
        result["reason"] = "diagnostic_error"
    result["elapsed_ms"] = round((time.monotonic() - started) * 1000)
    return result


async def compare_routes() -> dict:
    configured = {
        "javascript": bool(settings.yandex_maps_js_api_key),
        "geocoder": bool(settings.yandex_geocoder_api_key),
        "suggest": bool(settings.yandex_suggest_api_key),
    }
    routes: list[MapsRoute] = ["auto", "ipv4"]
    if settings.openai_proxy_address.strip():
        routes.append("proxy")
    checks = await asyncio.gather(*[
        _check(service, route)
        for service in ("geocoder", "suggest") if configured[service]
        for route in routes
    ])
    return {
        "release_sha": settings.release_sha,
        "configured": configured,
        "application_route": "ipv4",
        "checks": checks,
    }
