import hashlib
from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, HTTPException, Request, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

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

router = APIRouter(tags=["internal-deployment"])
github_bearer = HTTPBearer(auto_error=False)


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
