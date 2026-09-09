import asyncio
import logging
from typing import Any

import httpx
from fastapi import HTTPException
from openai import APIConnectionError, APIStatusError, APITimeoutError, AsyncOpenAI

from app.core.config import settings
from app.schemas import AIItemDescription
from app.services.openai_client import build_openai_client

logger = logging.getLogger(__name__)


class AIService:
    def __init__(self) -> None:
        self.openai = build_openai_client(settings.openai_api_key) if settings.openai_api_key else None
        self._retired_openai_clients: list[AsyncOpenAI] = []

    @property
    def openai_configured(self) -> bool:
        return self.openai is not None

    def configure_openai(self, api_key: str) -> None:
        # Attribute replacement is atomic. Requests already using the previous
        # client can finish while all new requests immediately use this key.
        previous_client = self.openai
        self.openai = build_openai_client(api_key)
        if previous_client:
            self._retired_openai_clients.append(previous_client)

    async def close(self) -> None:
        if self.openai:
            await self.openai.close()
        for client in self._retired_openai_clients:
            await client.close()
        self._retired_openai_clients.clear()

    async def describe_item(
        self,
        image_url: str,
        kind: str,
        user_hint: str = "",
    ) -> AIItemDescription:
        if not self.openai:
            raise HTTPException(503, "ИИ-описание не настроено. Заполните описание вручную. [AI_CONFIG]")

        prompt = (
            "Проанализируй фотографию потерянной или найденной вещи для российского бюро находок. "
            "Пиши по-русски. Не угадывай персональные данные. Отдели публичные признаки от деталей, "
            "которые лучше скрыть и использовать для проверки владельца. Если признак не виден, верни "
            "пустой массив, не выдумывай. "
            f"Тип публикации: {kind}. Подсказка пользователя: {user_hint or 'нет'}."
        )
        try:
            async with asyncio.timeout(45):
                response = await self.openai.with_options(timeout=40, max_retries=0).responses.parse(
                    model=settings.openai_model,
                    input=[
                        {
                            "role": "user",
                            "content": [
                                {"type": "input_text", "text": prompt},
                                {"type": "input_image", "image_url": image_url, "detail": "auto"},
                            ],
                        }
                    ],
                    text_format=AIItemDescription,
                    store=False,
                )
        except (APITimeoutError, TimeoutError) as exc:
            raise HTTPException(504, "ИИ не успел обработать фото. Попробуйте ещё раз. [AI_TIMEOUT]") from exc
        except APIConnectionError as exc:
            raise HTTPException(503, "Нет связи с ИИ. Можно заполнить описание вручную. [AI_CONNECTION]") from exc
        except APIStatusError as exc:
            # Never expose upstream response bodies, credentials, or image URLs.
            logger.warning("OpenAI description failed: status=%s request_id=%s", exc.status_code, exc.request_id)
            code = {401: "AI_AUTH", 403: "AI_ACCESS", 404: "AI_MODEL", 429: "AI_LIMIT", 400: "AI_INPUT"}.get(exc.status_code, "AI_UPSTREAM")
            message = "Лимит ИИ временно исчерпан." if exc.status_code == 429 else "ИИ временно недоступен."
            raise HTTPException(503, f"{message} Можно заполнить описание вручную. [{code}]") from exc
        except ValueError as exc:
            raise HTTPException(502, "ИИ вернул некорректное описание. Попробуйте ещё раз. [AI_FORMAT]") from exc
        if not response.output_parsed:
            raise HTTPException(502, "ИИ не смог описать это фото. Попробуйте другое. [AI_EMPTY]")
        return response.output_parsed

    async def image_embedding(self, image_url: str) -> list[float] | None:
        if not settings.openclip_url:
            return None
        try:
            async with httpx.AsyncClient(timeout=settings.openclip_timeout_seconds) as client:
                response = await client.post(
                    f"{settings.openclip_url.rstrip('/')}/v1/embed/image",
                    json={"image_url": image_url},
                )
                response.raise_for_status()
                data: dict[str, Any] = response.json()
                return [float(value) for value in data["embedding"]]
        except (httpx.HTTPError, KeyError, TypeError, ValueError):
            logger.exception("OpenCLIP image embedding failed")
            return None

    async def text_embedding(self, text: str) -> list[float] | None:
        if not settings.openclip_url:
            return None
        try:
            async with httpx.AsyncClient(timeout=settings.openclip_timeout_seconds) as client:
                response = await client.post(
                    f"{settings.openclip_url.rstrip('/')}/v1/embed/text",
                    json={"text": text},
                )
                response.raise_for_status()
                data: dict[str, Any] = response.json()
                return [float(value) for value in data["embedding"]]
        except (httpx.HTTPError, KeyError, TypeError, ValueError):
            logger.exception("OpenCLIP text embedding failed")
            return None


ai_service = AIService()
