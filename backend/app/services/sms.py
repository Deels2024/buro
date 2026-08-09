import logging

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


async def send_otp(phone: str, code: str) -> None:
    if not settings.sms_provider_url:
        logger.warning("Development SMS code for %s: %s", phone[-4:], code)
        return
    headers = {"Authorization": f"Bearer {settings.sms_provider_token}"}
    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.post(
            settings.sms_provider_url,
            json={"phone": phone, "message": f"Код Бюро находок: {code}"},
            headers=headers,
        )
        response.raise_for_status()
