import logging
from typing import Any

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


def _smsc_request_data(phone: str, code: str) -> dict[str, str]:
    """Build a UTF-8, JSON-response request for the SMSC HTTP API."""
    data = {
        "phones": phone.removeprefix("+"),
        "mes": f"Код Бюро находок: {code}",
        "charset": "utf-8",
        "fmt": "3",
    }
    data["login"] = settings.smsc_login
    data["psw"] = settings.smsc_password
    if settings.smsc_sender:
        data["sender"] = settings.smsc_sender
    return data


def _smsc_message_id(payload: Any) -> str:
    if not isinstance(payload, dict):
        raise RuntimeError("SMSC вернул некорректный ответ")
    if payload.get("error") or payload.get("error_code"):
        raise RuntimeError(f"SMSC отклонил отправку: {payload.get('error', 'unknown error')}")
    message_id = payload.get("id")
    if message_id in (None, "", 0, "0"):
        raise RuntimeError("SMSC не подтвердил отправку SMS")
    return str(message_id)


async def send_otp(phone: str, code: str) -> None:
    if not settings.smsc_is_configured:
        logger.warning("Development SMS code for %s: %s", phone[-4:], code)
        return
    async with httpx.AsyncClient(timeout=10) as client:
        response = await client.post(
            settings.smsc_url,
            data=_smsc_request_data(phone, code),
        )
        response.raise_for_status()
        message_id = _smsc_message_id(response.json())
        logger.info("SMSC accepted OTP for %s, message_id=%s", phone[-4:], message_id)
