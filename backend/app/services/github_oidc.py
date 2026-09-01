import asyncio
import hashlib
import time
from collections.abc import Mapping
from typing import Any

import jwt
from jwt import PyJWKClient
from jwt.exceptions import InvalidTokenError, PyJWKClientConnectionError, PyJWTError

from app.services.cache import redis

GITHUB_OIDC_ISSUER = "https://token.actions.githubusercontent.com"
GITHUB_OIDC_JWKS_URL = f"{GITHUB_OIDC_ISSUER}/.well-known/jwks"
GITHUB_OIDC_AUDIENCE = "https://edinburo.ru/v1/internal/deployment/openai-key"
GITHUB_REPOSITORY = "Deels2024/buro"
GITHUB_REPOSITORY_ID = "1329033876"
GITHUB_REPOSITORY_OWNER_ID = "160591824"
GITHUB_ALLOWED_ACTOR_ID = "160591824"
GITHUB_WORKFLOW_REF = (
    "Deels2024/buro/.github/workflows/configure-openai.yml@refs/heads/main"
)

_jwks_client = PyJWKClient(
    GITHUB_OIDC_JWKS_URL,
    cache_keys=False,
    cache_jwk_set=True,
    lifespan=300,
    timeout=10,
)


class GitHubOIDCAuthenticationError(Exception):
    pass


class GitHubOIDCUnavailableError(Exception):
    pass


def _decode_github_oidc_token(token: str) -> dict[str, Any]:
    header = jwt.get_unverified_header(token)
    key_id = header.get("kid")
    if (
        header.get("alg") != "RS256"
        or header.get("typ") != "JWT"
        or not isinstance(key_id, str)
        or not 1 <= len(key_id) <= 128
        or not key_id.isascii()
        or any(not (character.isalnum() or character in "-_.") for character in key_id)
        or any(name in header for name in ("crit", "jku", "x5u"))
    ):
        raise InvalidTokenError("GitHub Actions JWT header is not trusted")
    signing_key = _jwks_client.get_signing_key_from_jwt(token)
    return jwt.decode(
        token,
        signing_key.key,
        algorithms=["RS256"],
        audience=GITHUB_OIDC_AUDIENCE,
        issuer=GITHUB_OIDC_ISSUER,
        leeway=15,
        options={
            "strict_aud": True,
            "require": [
                "actor_id",
                "aud",
                "environment",
                "exp",
                "iat",
                "iss",
                "jti",
                "nbf",
                "ref",
                "repository",
                "repository_id",
                "repository_owner_id",
                "sub",
                "workflow_ref",
            ]
        },
    )


def _validate_github_claims(claims: Mapping[str, Any]) -> None:
    expected_claims = {
        "environment": "production",
        "event_name": "workflow_dispatch",
        "ref": "refs/heads/main",
        "ref_type": "branch",
        "repository": GITHUB_REPOSITORY,
        "runner_environment": "github-hosted",
        "workflow_ref": GITHUB_WORKFLOW_REF,
    }
    if any(claims.get(name) != expected for name, expected in expected_claims.items()):
        raise GitHubOIDCAuthenticationError("GitHub Actions claims are not trusted")
    if str(claims.get("repository_id")) != GITHUB_REPOSITORY_ID:
        raise GitHubOIDCAuthenticationError("GitHub repository identity is not trusted")
    if str(claims.get("repository_owner_id")) != GITHUB_REPOSITORY_OWNER_ID:
        raise GitHubOIDCAuthenticationError("GitHub owner identity is not trusted")
    if str(claims.get("actor_id")) != GITHUB_ALLOWED_ACTOR_ID:
        raise GitHubOIDCAuthenticationError("GitHub workflow actor is not trusted")

    allowed_subjects = {
        "repo:Deels2024/buro:environment:production",
        "repo:Deels2024@160591824/buro@1329033876:environment:production",
    }
    if claims.get("sub") not in allowed_subjects:
        raise GitHubOIDCAuthenticationError("GitHub Actions subject is not trusted")

    jti = claims.get("jti")
    expires_at = claims.get("exp")
    if not isinstance(jti, str) or not jti or not isinstance(expires_at, int):
        raise GitHubOIDCAuthenticationError("GitHub Actions token claims are incomplete")


async def verify_github_oidc_token(token: str) -> dict[str, Any]:
    if not token or len(token) > 16_384:
        raise GitHubOIDCAuthenticationError("GitHub Actions token is invalid")
    try:
        claims = await asyncio.to_thread(_decode_github_oidc_token, token)
    except PyJWKClientConnectionError as exc:
        raise GitHubOIDCUnavailableError("GitHub OIDC verification is unavailable") from exc
    except PyJWTError as exc:
        raise GitHubOIDCAuthenticationError("GitHub Actions token is invalid") from exc
    except Exception as exc:
        raise GitHubOIDCUnavailableError("GitHub OIDC verification is unavailable") from exc

    _validate_github_claims(claims)
    expires_at = int(claims["exp"])
    ttl_seconds = max(expires_at - int(time.time()) + 15, 1)
    replay_value = f"{GITHUB_OIDC_ISSUER}|{claims['jti']}"
    replay_digest = hashlib.sha256(replay_value.encode()).hexdigest()
    try:
        accepted = await redis.set(
            f"bureau:github-oidc:{replay_digest}",
            "used",
            ex=ttl_seconds,
            nx=True,
        )
    except Exception as exc:
        raise GitHubOIDCUnavailableError("OIDC replay protection is unavailable") from exc
    if not accepted:
        raise GitHubOIDCAuthenticationError("GitHub Actions token was already used")
    return claims
