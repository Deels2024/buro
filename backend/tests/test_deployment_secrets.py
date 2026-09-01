import stat
from pathlib import Path

import pytest

from app.services.deployment_secrets import (
    OpenAIConfigurationError,
    persist_openai_key,
    validate_openai_key_format,
)

TEST_KEY = "sk-test-value-0000000000000000000000000000000000000000"


def test_openai_key_format_accepts_project_style_keys() -> None:
    validate_openai_key_format(TEST_KEY)
    validate_openai_key_format("sk-proj-" + "Abc_123-" * 8)


@pytest.mark.parametrize(
    "value",
    [
        "",
        "not-a-key",
        "sk-too-short",
        "sk-" + "a" * 37 + " ",
        "sk-" + "я" * 40,
    ],
)
def test_openai_key_format_rejects_invalid_values(value: str) -> None:
    with pytest.raises(OpenAIConfigurationError):
        validate_openai_key_format(value)


def test_openai_key_is_replaced_atomically_with_private_mode(tmp_path: Path) -> None:
    destination = tmp_path / "openai_api_key"
    destination.write_text("old-secret", encoding="ascii")

    persist_openai_key(TEST_KEY, destination)

    assert destination.read_text(encoding="ascii") == TEST_KEY
    assert stat.S_IMODE(destination.stat().st_mode) == 0o400
    assert list(tmp_path.iterdir()) == [destination]
