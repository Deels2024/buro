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


@pytest.mark.parametrize("use_proxy,host,expected_proxy", [
    (True, "proxy.example", "http://user:p%40ss@proxy.example:8080"),
    (False, "proxy.example", None),
    (True, "", None),
])
async def test_sms_outbound_route(monkeypatch, use_proxy, host, expected_proxy):
    monkeypatch.setattr(settings, "smsc_login", "test-login")
    monkeypatch.setattr(settings, "smsc_password", "test-password")
    monkeypatch.setattr(settings, "smsc_use_proxy", use_proxy)
    monkeypatch.setattr(settings, "openai_proxy_address", host)
    monkeypatch.setattr(settings, "openai_proxy_port", "8080")
    monkeypatch.setattr(settings, "openai_proxy_scheme", "http")
    monkeypatch.setattr(settings, "openai_proxy_login", "user")
    monkeypatch.setattr(settings, "openai_proxy_password", "p@ss")
    client = AsyncMock()
    client.__aenter__.return_value = client
    client.post.side_effect = httpx.ReadTimeout("private details")
    factory = Mock(return_value=client)
    monkeypatch.setattr(sms.httpx, "AsyncClient", factory)
    with pytest.raises(sms.SMSDeliveryError) as captured:
        await sms.send_otp("+79991234567", "123456")
    assert str(captured.value) == ("SMS_PROXY_TIMEOUT" if expected_proxy else "SMS_TIMEOUT")
    factory.assert_called_once_with(timeout=10, proxy=expected_proxy, trust_env=False)
    client.post.assert_awaited_once()


async def test_invalid_proxy_does_not_send_sms(monkeypatch):
    monkeypatch.setattr(settings, "smsc_login", "test-login")
    monkeypatch.setattr(settings, "smsc_password", "test-password")
    monkeypatch.setattr(settings, "smsc_use_proxy", True)
    monkeypatch.setattr(settings, "openai_proxy_address", "proxy.example")
    monkeypatch.setattr(settings, "openai_proxy_port", "invalid")
    factory = Mock()
    monkeypatch.setattr(sms.httpx, "AsyncClient", factory)
    with pytest.raises(sms.SMSDeliveryError, match="SMS_PROXY_CONFIG"):
        await sms.send_otp("+79991234567", "123456")
    factory.assert_not_called()
