import logging
from typing import Any

import httpx
from openai import AsyncOpenAI

from app.core.config import settings
from app.schemas import AIItemDescription

logger = logging.getLogger(__name__)


class AIService:
    def __init__(self) -> None:
        self.openai = AsyncOpenAI(api_key=settings.openai_api_key) if settings.openai_api_key else None
        self._retired_openai_clients: list[AsyncOpenAI] = []

    @property
    def openai_configured(self) -> bool:
        return self.openai is not None

    def configure_openai(self, api_key: str) -> None:
        # Attribute replacement is atomic. Requests already using the previous
        # client can finish while all new requests immediately use this key.
        previous_client = self.openai
        self.openai = AsyncOpenAI(api_key=api_key)
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
            return self._fallback_description(kind, user_hint)

        prompt = (
            "Проанализируй фотографию потерянной или найденной вещи для российского бюро находок. "
            "Пиши по-русски. Не угадывай персональные данные. Отдели публичные признаки от деталей, "
            "которые лучше скрыть и использовать для проверки владельца. Если признак не виден, верни "
            "пустой массив, не выдумывай. "
            f"Тип публикации: {kind}. Подсказка пользователя: {user_hint or 'нет'}."
        )
        response = await self.openai.responses.parse(
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
        )
        if not response.output_parsed:
            raise RuntimeError("ИИ не вернул структурированное описание")
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

    @staticmethod
    def _fallback_description(kind: str, hint: str) -> AIItemDescription:
        clean_hint = hint.strip() or "Вещь без дополнительного описания"
        return AIItemDescription(
            title=clean_hint[:80],
            category="Другое",
            description=clean_hint,
            tags=[kind, "требует уточнения"],
            colors=[],
            distinctive_features=[],
            sensitive_details_to_hide=[],
            confidence=0.2,
        )


ai_service = AIService()
