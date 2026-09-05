from pathlib import Path

import pytest
from pydantic import ValidationError

from app.core.config import Settings


def test_openai_key_can_be_loaded_from_secret_file(tmp_path: Path) -> None:
    secret_file = tmp_path / "openai_api_key"
    secret_file.write_text("sk-test-file-value-0000000000000000000000000000\n", encoding="utf-8")

    loaded = Settings(
        _env_file=None,
        openai_api_key="",
        openai_api_key_file=str(secret_file),
    )

    assert loaded.openai_api_key == "sk-test-file-value-0000000000000000000000000000"


def test_secret_file_takes_precedence_over_explicit_openai_key(tmp_path: Path) -> None:
    secret_file = tmp_path / "openai_api_key"
    secret_file.write_text("sk-test-file-value-0000000000000000000000000000\n", encoding="utf-8")

    loaded = Settings(
        _env_file=None,
        openai_api_key="sk-test-environment-value-000000000000000000000000",
        openai_api_key_file=str(secret_file),
    )

    assert loaded.openai_api_key == "sk-test-file-value-0000000000000000000000000000"


def test_smsc_login_and_password_configure_provider() -> None:
    assert Settings(_env_file=None, smsc_login="login", smsc_password="password").smsc_is_configured
    assert not Settings(_env_file=None, smsc_login="login").smsc_is_configured


def test_smsc_url_must_be_https() -> None:
    assert Settings(_env_file=None, smsc_url="https://smsc.ru/sys/send.php").smsc_url_is_secure
    assert not Settings(_env_file=None, smsc_url="http://smsc.ru/sys/send.php").smsc_url_is_secure
    assert not Settings(_env_file=None, smsc_url="not-a-url").smsc_url_is_secure


def test_legacy_public_deployment_uses_https_without_changing_credentials() -> None:
    loaded = Settings(
        _env_file=None,
        environment="development",
        public_api_url="http://5.183.191.139:8088/v1",
        s3_public_endpoint="http://5.183.191.139:9000",
        app_secret="a" * 32,
        lookup_pepper="b" * 32,
        pii_fernet_key="c" * 43 + "=",
        s3_secret_key="storage-test-password",
        smsc_login="existing-login",
        smsc_password="existing-password",
    )
    assert loaded.is_production
    assert loaded.public_api_url == "https://edinburo.ru/v1"
    assert loaded.s3_public_endpoint == "https://edinburo.ru"
    assert loaded.cors_origins == ["https://edinburo.ru", "https://admin.edinburo.ru"]
    assert loaded.smsc_password == "existing-password"
    assert loaded.app_secret == "a" * 32


def test_public_address_cannot_enable_development_sms_with_missing_credentials() -> None:
    with pytest.raises(ValidationError, match="Production secrets"):
        Settings(_env_file=None, public_api_url="https://edinburo.ru/v1")


def test_local_development_remains_available() -> None:
    loaded = Settings(_env_file=None)
    assert not loaded.is_production
    assert loaded.s3_public_endpoint == "http://localhost:9000"
