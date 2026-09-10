"""Release-time maps probe using a public city, never user location data."""
import asyncio
import json
import re

from fastapi import HTTPException

from app.api.routes.maps import budget
from app.core.config import settings
from app.services.yandex_maps import parse_geocode, parse_suggestions, provider_request


async def main() -> None:
    configured = {
        "javascript": bool(settings.yandex_maps_js_api_key),
        "geocoder": bool(settings.yandex_geocoder_api_key),
        "suggest": bool(settings.yandex_suggest_api_key),
    }
    if not settings.is_production or not any(configured.values()):
        print(json.dumps({"yandex_maps": "skipped", "reason": "no_production_keys"}))
        return
    result = {"javascript": "configured" if configured["javascript"] else "missing"}
    for service in ("geocoder", "suggest"):
        if not configured[service]:
            result[service] = "missing"
            continue
        try:
            async with asyncio.timeout(12):
                await budget("release-probe", service)
                if service == "geocoder":
                    data = await provider_request(service, {"geocode": "Москва", "format": "json", "results": 1})
                    parsed = parse_geocode(data)
                    if not parsed["region"]:
                        raise ValueError("No city")
                else:
                    data = await provider_request(service, {
                        "text": "Москва", "types": "locality", "countries": "ru", "lang": "ru",
                        "results": 1, "print_address": 1, "attrs": "uri",
                    })
                    if not parse_suggestions(data):
                        raise ValueError("No suggestions")
            result[service] = "ok"
        except HTTPException as exc:
            match = re.search(r"\[MAPS_[A-Z_]+\]", str(exc.detail))
            result[service] = match.group(0) if match else "MAPS_ERROR"
        except Exception:
            result[service] = "MAPS_PROBE_ERROR"
    ok = result == {"javascript": "configured", "geocoder": "ok", "suggest": "ok"}
    print(json.dumps({"yandex_maps": "ok" if ok else "failed", **result}))
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    asyncio.run(main())
