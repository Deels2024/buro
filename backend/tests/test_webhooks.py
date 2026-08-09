import pytest

from app.services.webhooks import validate_webhook_url


def test_webhook_url_requires_public_https() -> None:
    validate_webhook_url("https://example.org/hooks/bureau")
    with pytest.raises(ValueError):
        validate_webhook_url("http://example.org/hook")
    with pytest.raises(ValueError):
        validate_webhook_url("https://127.0.0.1/hook")
    with pytest.raises(ValueError):
        validate_webhook_url("https://10.0.0.5/hook")
