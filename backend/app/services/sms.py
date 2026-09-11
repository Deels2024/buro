import logging
from typing import Any

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)


class SMSDeliveryError(RuntimeError):
    """A bounded diagnostic code; never the provider body or credentials."""

    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


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
        raise SMSDeliveryError("SMS_RESPONSE_FORMAT")
    if payload.get("error") or payload.get("error_code"):
        code = str(payload.get("error_code", ""))
        raise SMSDeliveryError(f"SMSC_{code}" if code in {str(n) for n in range(1, 10)} else "SMS_PROVIDER_REJECTED")
    message_id = payload.get("id")
    if message_id in (None, "", 0, "0"):
        raise SMSDeliveryError("SMS_NOT_ACCEPTED")
    return str(message_id)


async def send_otp(phone: str, code: str) -> None:
    if not settings.smsc_is_configured:
        logger.warning("Development SMS code for %s: %s", phone[-4:], code)
        return
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.post(
                settings.smsc_url,
                data=_smsc_request_data(phone, code),
            )
            response.raise_for_status()
            message_id = _smsc_message_id(response.json())
            logger.info("SMSC accepted OTP for %s, message_id=%s", phone[-4:], message_id)
    except httpx.TimeoutException:
        raise SMSDeliveryError("SMS_TIMEOUT") from None
    except httpx.HTTPStatusError as exc:
        raise SMSDeliveryError(f"SMS_HTTP_{exc.response.status_code}") from None
    except httpx.RequestError:
        raise SMSDeliveryError("SMS_NETWORK") from None
    except ValueError:
        raise SMSDeliveryError("SMS_RESPONSE_FORMAT") from None
