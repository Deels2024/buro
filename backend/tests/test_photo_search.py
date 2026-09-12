from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.api.routes import listings
from app.schemas import AIPhotoSearchRequest
from app.services.listing_search import words


@pytest.mark.parametrize('status,expected', [('uploaded',409), ('processing',409), ('rejected',422), ('blocked',422)])
async def test_unvalidated_photo_never_reaches_embedding_or_consumes_search_limit(monkeypatch, status, expected):
    user = SimpleNamespace(id=uuid4())
    media = SimpleNamespace(owner_id=user.id, mime_type='image/jpeg', status=status)
    db = SimpleNamespace(get=AsyncMock(return_value=media))
    embedding = AsyncMock()
    limit = AsyncMock()
    monkeypatch.setattr(listings.ai_service, 'image_embedding', embedding)
    monkeypatch.setattr(listings, 'rate_limit', limit)
    with pytest.raises(HTTPException) as error:
        await listings.search_by_photo(AIPhotoSearchRequest(media_id=uuid4()), db, user)
    assert error.value.status_code == expected
    embedding.assert_not_awaited()
    limit.assert_not_awaited()


def test_search_words_do_not_interpret_operators_or_wildcards():
    assert words('РЮКЗАК & "чёрный" рюкзак:* %_') == ['рюкзак', 'черный']
    assert words(' %_&|! ') == []
