import hashlib
from datetime import UTC, datetime
from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, HTTPException, Request, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select, update

from app.api.deps import DB
from app.core.security import normalize_phone, phone_lookup_hash
from app.db.models import RefreshToken, User
from app.services.audit import add_audit
from app.services.deployment_secrets import (
    OpenAIConfigurationError,
    SecretPersistenceError,
    configure_openai_key,
)
from app.services.github_oidc import (
    GitHubOIDCAuthenticationError,
    GitHubOIDCUnavailableError,
    verify_github_oidc_token,
)
from app.services.yandex_diagnostics import compare_routes

router = APIRouter(tags=["internal-deployment"])
github_bearer = HTTPBearer(auto_error=False)


async def trusted_admin_configuration(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(github_bearer)],
) -> dict[str, Any]:
    if not credentials or credentials.scheme.lower() != "bearer":
        raise HTTPException(401, "GitHub Actions authentication is required")
    try:
        return await verify_github_oidc_token(credentials.credentials, configure_admin=True)
    except GitHubOIDCAuthenticationError:
        raise HTTPException(401, "GitHub Actions authentication failed") from None
    except GitHubOIDCUnavailableError:
        raise HTTPException(503, "GitHub Actions authentication is temporarily unavailable") from None


@router.post("/administrator", include_in_schema=False)
async def configure_production_administrator(
    request: Request,
    response: Response,
    db: DB,
    identity: Annotated[dict[str, Any], Depends(trusted_admin_configuration)],
) -> dict[str, str]:
    # Read raw bytes only after authentication. Phone numbers must never appear
    # in validation errors, URLs, workflow inputs or audit payloads.
    if request.headers.get("content-type", "").partition(";")[0].lower() != "application/octet-stream":
        raise HTTPException(415, "Content-Type must be application/octet-stream")
    raw = b""
    async for chunk in request.stream():
        raw += chunk
        if len(raw) > 32:
            raise HTTPException(422, "Administrator phone is invalid")
    try:
        phone = normalize_phone(raw.decode("ascii"))
    except (ValueError, UnicodeDecodeError):
        raise HTTPException(422, "Administrator phone is invalid") from None
    user = await db.scalar(select(User).where(User.phone_hash == phone_lookup_hash(phone)).with_for_update())
    if not user or user.status != "active" or not user.verified_at:
        raise HTTPException(409, "Sign in to the application and verify this phone before granting access")
    if user.role != "admin":
        previous_role = user.role
        user.role = "admin"
        await db.execute(update(RefreshToken).where(
            RefreshToken.user_id == user.id, RefreshToken.revoked_at.is_(None),
        ).values(revoked_at=datetime.now(UTC)))
        add_audit(db, actor_id=None, action="deployment.administrator.grant", entity_type="user",
                  entity_id=user.id, payload={"previous_role": previous_role, "role": "admin",
                                             "github_actor_id": identity["actor_id"], "run_id": identity.get("run_id")})
        await db.commit()
    response.headers["Cache-Control"] = "no-store"
    return {"status": "configured", "role": "admin"}


async def trusted_maps_diagnostics(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(github_bearer)],
) -> dict[str, Any]:
    if not credentials or credentials.scheme.lower() != "bearer":
        raise HTTPException(401, "GitHub Actions authentication is required", headers={"WWW-Authenticate": "Bearer"})
    try:
        return await verify_github_oidc_token(credentials.credentials, yandex_diagnostics=True)
    except GitHubOIDCAuthenticationError:
        raise HTTPException(401, "GitHub Actions authentication failed", headers={"WWW-Authenticate": "Bearer"}) from None
    except GitHubOIDCUnavailableError:
        raise HTTPException(503, "GitHub Actions authentication is temporarily unavailable") from None


@router.post("/yandex-diagnostics", include_in_schema=False)
async def production_maps_diagnostics(
    response: Response,
    _: Annotated[dict[str, Any], Depends(trusted_maps_diagnostics)],
) -> dict:
    response.headers["Cache-Control"] = "no-store"
    return await compare_routes()


async def trusted_github_workflow(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(github_bearer)],
) -> dict[str, Any]:
    if not credentials or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="GitHub Actions authentication is required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    try:
        return await verify_github_oidc_token(credentials.credentials)
    except GitHubOIDCAuthenticationError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="GitHub Actions authentication failed",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except GitHubOIDCUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="GitHub Actions authentication is temporarily unavailable",
        ) from exc


@router.post("/openai-key", include_in_schema=False)
async def configure_production_openai_key(
    request: Request,
    response: Response,
    api_key: Annotated[
        bytes,
        Body(media_type="application/octet-stream", min_length=40, max_length=512),
    ],
    _: Annotated[dict[str, Any], Depends(trusted_github_workflow)],
) -> dict[str, str]:
    content_type = request.headers.get("content-type", "").partition(";")[0].strip().lower()
    if content_type != "application/octet-stream":
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Content-Type must be application/octet-stream",
        )
    try:
        decoded_api_key = api_key.decode("ascii")
    except UnicodeDecodeError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="OpenAI key could not be validated",
        ) from exc
    try:
        model = await configure_openai_key(decoded_api_key)
    except OpenAIConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail="OpenAI key could not be validated",
        ) from exc
    except SecretPersistenceError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="OpenAI secret storage is unavailable",
        ) from exc
    response.headers["Cache-Control"] = "no-store"
    return {
        "status": "configured",
        "model": model,
        "fingerprint_sha256": hashlib.sha256(api_key).hexdigest(),
    }
