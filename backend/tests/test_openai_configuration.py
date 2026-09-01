from pathlib import Path
from unittest.mock import AsyncMock, Mock

import pytest

from app.services import deployment_secrets
from app.services.deployment_secrets import OpenAIConfigurationError, configure_openai_key

TEST_KEY = "sk-test-value-0000000000000000000000000000000000000000"


async def test_failed_validation_preserves_existing_secret(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    destination = tmp_path / "openai_api_key"
    destination.write_text("working-key", encoding="ascii")
    monkeypatch.setattr(deployment_secrets.settings, "openai_api_key_file", str(destination))
    monkeypatch.setattr(
        deployment_secrets,
        "validate_openai_key",
        AsyncMock(side_effect=OpenAIConfigurationError("invalid")),
    )
    configure_client = Mock()
    monkeypatch.setattr(deployment_secrets.ai_service, "configure_openai", configure_client)

    with pytest.raises(OpenAIConfigurationError):
        await configure_openai_key(TEST_KEY)

    assert destination.read_text(encoding="ascii") == "working-key"
    configure_client.assert_not_called()
