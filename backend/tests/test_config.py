from pathlib import Path

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
