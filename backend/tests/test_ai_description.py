import base64
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock
from uuid import uuid4

import httpx
import pytest
from fastapi import HTTPException
from openai import APIConnectionError, APIStatusError, APITimeoutError

from app.api.routes import listings
from app.schemas import AIDescribeRequest, AIItemDescription
from app.services.ai import AIService


def service_with_parse(result=None, error=None):
    service = AIService.__new__(AIService)
    service.openai = Mock()
    parse = AsyncMock(return_value=SimpleNamespace(output_parsed=result), side_effect=error)
    service.openai.with_options.return_value.responses.parse = parse
    return service, parse


async def test_description_sends_image_and_disables_response_storage():
    description = AIItemDescription(title="Рюкзак", category="bags", description="Красный рюкзак",
        tags=[], colors=["красный"], distinctive_features=[], sensitive_details_to_hide=[], confidence=0.9)
    service, parse = service_with_parse(description)
    image = "data:image/png;base64,cGhvdG8="
    assert await service.describe_item(image, "found") == description
    sent = parse.call_args.kwargs
    assert sent["input"][0]["content"][1]["image_url"] == image
    assert sent["store"] is False
    service.openai.with_options.assert_called_once_with(timeout=40, max_retries=0)


async def test_missing_key_is_not_reported_as_success():
    service, _ = service_with_parse()
    service.openai = None
    with pytest.raises(HTTPException) as error:
        await service.describe_item("data:image/png;base64,cGhvdG8=", "found")
    assert error.value.status_code == 503
    assert "AI_CONFIG" in error.value.detail


@pytest.mark.parametrize("status,code", [(400,"AI_INPUT"),(401,"AI_AUTH"),(403,"AI_ACCESS"),(404,"AI_MODEL"),(429,"AI_LIMIT"),(500,"AI_UPSTREAM")])
async def test_upstream_errors_are_safe_and_do_not_log_the_user_out(status, code):
    response = httpx.Response(status, request=httpx.Request("POST","https://api.openai.com/v1/responses"))
    upstream = APIStatusError("private upstream body", response=response, body={"error":"private"})
    service, _ = service_with_parse(error=upstream)
    with pytest.raises(HTTPException) as error:
        await service.describe_item("private-image-url", "found")
    assert error.value.status_code == 503
    assert code in error.value.detail
    assert "private" not in error.value.detail


@pytest.mark.parametrize("kind,code,status", [(APIConnectionError,"AI_CONNECTION",503),(APITimeoutError,"AI_TIMEOUT",504)])
async def test_transport_failure_is_actionable(kind, code, status):
    service, _ = service_with_parse(error=kind(request=httpx.Request("POST","https://api.openai.com/v1/responses")))
    with pytest.raises(HTTPException) as error:
        await service.describe_item("image", "found")
    assert error.value.status_code == status
    assert code in error.value.detail


async def test_empty_output_is_not_reported_as_success():
    service, _ = service_with_parse()
    with pytest.raises(HTTPException) as error:
        await service.describe_item("image", "found")
    assert "AI_EMPTY" in error.value.detail


@pytest.mark.parametrize("status,expected", [("processing",409),("rejected",422),("blocked",422)])
async def test_unvalidated_photo_never_reaches_openai(monkeypatch, status, expected):
    user = SimpleNamespace(id=uuid4())
    media = SimpleNamespace(owner_id=user.id, mime_type="image/jpeg", status=status)
    db = SimpleNamespace(get=AsyncMock(return_value=media))
    describe = AsyncMock()
    monkeypatch.setattr(listings.ai_service, "describe_item", describe)
    with pytest.raises(HTTPException) as error:
        await listings.describe_with_ai(AIDescribeRequest(media_id=uuid4(),kind="found"),db,user)
    assert error.value.status_code == expected
    describe.assert_not_awaited()


async def test_ready_photo_is_sent_as_bytes_without_a_temporary_url(monkeypatch):
    user = SimpleNamespace(id=uuid4())
    media = SimpleNamespace(owner_id=user.id, mime_type="image/jpeg", status="ready", object_key="clean/photo.jpg")
    db = SimpleNamespace(get=AsyncMock(return_value=media))
    describe = AsyncMock(return_value="description")
    monkeypatch.setattr(listings.ai_service, "describe_item", describe)
    monkeypatch.setattr(listings, "rate_limit", AsyncMock(return_value=True))
    monkeypatch.setattr(listings.storage, "read_bytes", Mock(return_value=b"clean photo"))
    presign = Mock(side_effect=AssertionError("Do not hand temporary URLs to OpenAI"))
    monkeypatch.setattr(listings.storage, "presign_download", presign)
    result = await listings.describe_with_ai(AIDescribeRequest(media_id=uuid4(),kind="found"),db,user)
    assert result == "description"
    image = describe.call_args.args[0]
    assert base64.b64decode(image.split(",",1)[1]) == b"clean photo"
    presign.assert_not_called()
