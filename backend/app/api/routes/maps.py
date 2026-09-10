from datetime import UTC, datetime
from typing import Literal

from fastapi import APIRouter, HTTPException, Response
from pydantic import BaseModel, Field, model_validator

from app.api.deps import CurrentUser
from app.core.config import settings
from app.services.cache import rate_limit
from app.services.yandex_maps import parse_geocode, parse_suggestions, provider_request

router = APIRouter()


class SuggestInput(BaseModel):
    query: str = Field(min_length=2, max_length=240)
    kind: Literal["city", "address"] = "address"


class ResolveInput(BaseModel):
    query: str | None = Field(default=None, min_length=2, max_length=500)
    uri: str | None = Field(default=None, max_length=2048)
    latitude: float | None = Field(default=None, ge=-90, le=90, allow_inf_nan=False)
    longitude: float | None = Field(default=None, ge=-180, le=180, allow_inf_nan=False)
    city_only: bool = False

    @model_validator(mode="after")
    def one_location(self):
        coordinates = self.latitude is not None or self.longitude is not None
        if coordinates and (self.latitude is None or self.longitude is None):
            raise ValueError("Both coordinates are required")
        if sum([bool(self.query), bool(self.uri), coordinates]) != 1:
            raise ValueError("Provide an address, URI or coordinates")
        if self.uri and not self.uri.startswith("ymapsbm1://"):
            raise ValueError("Invalid Yandex object URI")
        return self


async def budget(user_id, service: str) -> None:
    if not await rate_limit(f"maps:user:{user_id}", 60, 60):
        raise HTTPException(429, "Слишком много запросов адреса. Подождите минуту.")
    today = datetime.now(UTC)
    remaining = 86400 - today.hour * 3600 - today.minute * 60 - today.second
    if not await rate_limit(f"maps:daily:{service}:{today:%Y%m%d}", settings.yandex_daily_limit, remaining):
        raise HTTPException(429, "Дневной лимит подсказок исчерпан. Введите адрес вручную. [MAPS_LIMIT]")


@router.post("/suggest")
async def suggest(payload: SuggestInput, user: CurrentUser, response: Response) -> list[dict]:
    response.headers["Cache-Control"] = "no-store"
    await budget(user.id, "suggest")
    return parse_suggestions(await provider_request("suggest", {
        "text": payload.query.strip(), "types": "locality,province" if payload.kind == "city" else "geo",
        "countries": "ru", "lang": "ru", "results": 5, "highlight": 0, "print_address": 1, "attrs": "uri",
    }))


@router.post("/resolve")
async def resolve(payload: ResolveInput, user: CurrentUser, response: Response) -> dict:
    response.headers["Cache-Control"] = "no-store"
    await budget(user.id, "geocoder")
    params = {"format": "json", "lang": "ru_RU", "results": 1}
    if payload.uri:
        params["uri"] = payload.uri
    else:
        params["geocode"] = payload.query or f"{payload.longitude},{payload.latitude}"
    if payload.city_only:
        params["kind"] = "locality"
    return parse_geocode(await provider_request("geocoder", params))
