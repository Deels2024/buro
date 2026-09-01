import asyncio
import logging
import os
import tempfile
from pathlib import Path

from openai import AsyncOpenAI

from app.core.config import settings
from app.services.ai import ai_service

logger = logging.getLogger(__name__)


class OpenAIConfigurationError(Exception):
    pass


class SecretPersistenceError(Exception):
    pass


def validate_openai_key_format(api_key: str) -> None:
    if not 40 <= len(api_key) <= 512 or not api_key.startswith("sk-"):
        raise OpenAIConfigurationError("OpenAI key format is invalid")
    if not api_key.isascii() or any(not (character.isalnum() or character in "-_") for character in api_key):
        raise OpenAIConfigurationError("OpenAI key format is invalid")


async def validate_openai_key(api_key: str) -> None:
    client = AsyncOpenAI(api_key=api_key, timeout=30, max_retries=1)
    try:
        response = await client.responses.create(
            model=settings.openai_model,
            input="Reply with exactly OK.",
            max_output_tokens=32,
            store=False,
        )
        if not response.id:
            raise OpenAIConfigurationError("OpenAI validation returned no response")
    except OpenAIConfigurationError:
        raise
    except Exception as exc:
        logger.warning("OpenAI key validation failed (%s)", type(exc).__name__)
        raise OpenAIConfigurationError("OpenAI key could not be validated") from exc
    finally:
        await client.close()


def persist_openai_key(api_key: str, destination: Path | None = None) -> None:
    target = destination or (Path(settings.openai_api_key_file) if settings.openai_api_key_file else None)
    if target is None:
        raise SecretPersistenceError("OpenAI secret storage is not configured")
    if not target.parent.is_dir():
        raise SecretPersistenceError("OpenAI secret directory is unavailable")

    descriptor = -1
    temporary_name = ""
    try:
        descriptor, temporary_name = tempfile.mkstemp(
            dir=target.parent,
            prefix=f".{target.name}.",
        )
        os.fchmod(descriptor, 0o400)
        with os.fdopen(descriptor, "wb") as secret_file:
            descriptor = -1
            secret_file.write(api_key.encode("ascii"))
            secret_file.flush()
            os.fsync(secret_file.fileno())
        os.replace(temporary_name, target)
        temporary_name = ""
        directory_descriptor = os.open(target.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    except OSError as exc:
        raise SecretPersistenceError("OpenAI secret could not be persisted") from exc
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if temporary_name:
            try:
                os.unlink(temporary_name)
            except FileNotFoundError:
                pass


async def configure_openai_key(api_key: str) -> str:
    validate_openai_key_format(api_key)
    await validate_openai_key(api_key)
    await asyncio.to_thread(persist_openai_key, api_key)
    ai_service.configure_openai(api_key)
    return settings.openai_model
