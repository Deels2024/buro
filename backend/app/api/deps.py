from collections.abc import Callable
from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import TokenError, decode_access_token, hash_secret
from app.db.models import Organization, OrganizationApiKey, User
from app.db.session import get_db

bearer = HTTPBearer(auto_error=False)
DB = Annotated[AsyncSession, Depends(get_db)]


async def current_user(
    db: DB,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> User:
    if not credentials:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Нужна авторизация")
    try:
        payload = decode_access_token(credentials.credentials)
        user_id = UUID(payload["sub"])
    except (TokenError, ValueError, KeyError) as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Недействительный токен") from exc
    user = await db.get(User, user_id)
    if not user or user.status != "active":
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Аккаунт недоступен")
    if user.role in {"admin", "moderator"} and user.admin_2fa_enabled and not payload.get("mfa"):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Требуется двухфакторная авторизация")
    return user


CurrentUser = Annotated[User, Depends(current_user)]


def require_roles(*roles: str) -> Callable:
    async def dependency(user: CurrentUser) -> User:
        if user.role not in roles:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Недостаточно прав")
        return user

    return dependency


AdminUser = Annotated[User, Depends(require_roles("admin", "moderator"))]


async def organization_api_key(
    db: DB,
    value: Annotated[str, Header(alias="X-Organization-Key")],
) -> OrganizationApiKey:
    key = await db.scalar(
        select(OrganizationApiKey).where(OrganizationApiKey.key_hash == hash_secret(value))
    )
    now = datetime.now(UTC)
    if not key or key.status != "active" or (key.expires_at and key.expires_at <= now):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Недействительный API-ключ")
    organization = await db.get(Organization, key.organization_id)
    if not organization or organization.status != "verified" or not organization.api_enabled:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="API организации отключён")
    key.last_used_at = now
    return key


OrganizationKey = Annotated[OrganizationApiKey, Depends(organization_api_key)]
