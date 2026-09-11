from unittest.mock import AsyncMock, Mock

import httpx
import pytest

from app.core.config import settings
from app.services import sms


def test_smsc_request_uses_login_password_and_normalizes_phone(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "smsc_login", "bureau-login")
    monkeypatch.setattr(settings, "smsc_password", "bureau-password")
    monkeypatch.setattr(settings, "smsc_sender", "EDINBURO")

    assert sms._smsc_request_data("+79991234567", "123456") == {
        "login": "bureau-login",
        "psw": "bureau-password",
        "phones": "79991234567",
        "mes": "Код Бюро находок: 123456",
        "charset": "utf-8",
        "fmt": "3",
        "sender": "EDINBURO",
    }
def test_smsc_response_requires_a_message_id() -> None:
    assert sms._smsc_message_id({"id": 123456, "cnt": 1}) == "123456"
    with pytest.raises(sms.SMSDeliveryError, match="SMSC_8"):
        sms._smsc_message_id({"error": "недостаточно средств", "error_code": 8})


@pytest.mark.parametrize("failure,expected", [
    (httpx.ConnectTimeout("private connection details"), "SMS_TIMEOUT"),
    (httpx.ConnectError("private connection details"), "SMS_NETWORK"),
    (httpx.HTTPStatusError("private response details", request=httpx.Request("POST", "https://smsc.ru/sys/send.php"),
        response=httpx.Response(403)), "SMS_HTTP_403"),
])
async def test_transport_failure_exposes_only_safe_code(monkeypatch, failure, expected):
    monkeypatch.setattr(settings, "smsc_login", "private-login")
    monkeypatch.setattr(settings, "smsc_password", "private-password")
    client = AsyncMock()
    client.__aenter__.return_value = client
    client.post.side_effect = failure
    monkeypatch.setattr(sms.httpx, "AsyncClient", Mock(return_value=client))
    with pytest.raises(sms.SMSDeliveryError) as captured:
        await sms.send_otp("+79991234567", "123456")
    assert str(captured.value) == expected


def test_provider_error_never_exposes_raw_response():
    with pytest.raises(sms.SMSDeliveryError) as captured:
        sms._smsc_message_id({"error": "private-login private-password 123456", "error_code": 2})
    assert str(captured.value) == "SMSC_2"
