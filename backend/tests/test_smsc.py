import pytest

from app.core.config import settings
from app.services import sms


def test_smsc_request_uses_api_key_and_normalizes_phone(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "smsc_api_key", "smsc-api-key")
    monkeypatch.setattr(settings, "smsc_login", "")
    monkeypatch.setattr(settings, "smsc_password", "")
    monkeypatch.setattr(settings, "smsc_sender", "EDINBURO")

    assert sms._smsc_request_data("+79991234567", "123456") == {
        "apikey": "smsc-api-key",
        "phones": "79991234567",
        "mes": "Код Бюро находок: 123456",
        "charset": "utf-8",
        "fmt": "3",
        "sender": "EDINBURO",
    }


def test_smsc_request_falls_back_to_login_and_password(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(settings, "smsc_api_key", "")
    monkeypatch.setattr(settings, "smsc_login", "bureau-login")
    monkeypatch.setattr(settings, "smsc_password", "bureau-password")
    monkeypatch.setattr(settings, "smsc_sender", "")

    data = sms._smsc_request_data("+79991234567", "123456")

    assert data["login"] == "bureau-login"
    assert data["psw"] == "bureau-password"
    assert "apikey" not in data
    assert "sender" not in data


def test_smsc_response_requires_a_message_id() -> None:
    assert sms._smsc_message_id({"id": 123456, "cnt": 1}) == "123456"
    with pytest.raises(RuntimeError, match="недостаточно средств"):
        sms._smsc_message_id({"error": "недостаточно средств", "error_code": 8})
