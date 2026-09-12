import time
from types import SimpleNamespace

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from app.services import github_oidc
from app.services.github_oidc import (
    GITHUB_REPOSITORY,
    GITHUB_REPOSITORY_ID,
    GITHUB_REPOSITORY_OWNER_ID,
    GITHUB_WORKFLOW_REF,
    GitHubOIDCAuthenticationError,
    _validate_github_claims,
    verify_github_oidc_token,
)


def trusted_claims() -> dict:
    now = int(time.time())
    return {
        "actor_id": github_oidc.GITHUB_ALLOWED_ACTOR_ID,
        "aud": github_oidc.GITHUB_OIDC_AUDIENCE,
        "environment": "production",
        "event_name": "workflow_dispatch",
        "exp": now + 300,
        "iat": now,
        "iss": github_oidc.GITHUB_OIDC_ISSUER,
        "jti": "unique-token-id",
        "nbf": now - 1,
        "ref": "refs/heads/main",
        "ref_type": "branch",
        "repository": GITHUB_REPOSITORY,
        "repository_id": GITHUB_REPOSITORY_ID,
        "repository_owner_id": GITHUB_REPOSITORY_OWNER_ID,
        "runner_environment": "github-hosted",
        "sub": "repo:Deels2024@160591824/buro@1329033876:environment:production",
        "workflow_ref": GITHUB_WORKFLOW_REF,
    }


def test_github_claims_are_bound_to_repository_workflow_and_main() -> None:
    _validate_github_claims(trusted_claims())
    for name, value in {
        "actor_id": "3",
        "environment": "staging",
        "repository_id": "1",
        "repository_owner_id": "2",
        "ref": "refs/heads/feature",
        "workflow_ref": "Deels2024/buro/.github/workflows/other.yml@refs/heads/main",
    }.items():
        claims = trusted_claims()
        claims[name] = value
        with pytest.raises(GitHubOIDCAuthenticationError):
            _validate_github_claims(claims)


async def test_github_oidc_token_is_single_use(monkeypatch: pytest.MonkeyPatch) -> None:
    claims = trusted_claims()
    monkeypatch.setattr(github_oidc, "_decode_github_oidc_token", lambda _: claims)

    class FakeRedis:
        def __init__(self) -> None:
            self.used = False

        async def set(self, *args, **kwargs):
            if self.used:
                return None
            self.used = True
            return True

    monkeypatch.setattr(github_oidc, "redis", FakeRedis())
    assert await verify_github_oidc_token("signed-token") == claims
    with pytest.raises(GitHubOIDCAuthenticationError):
        await verify_github_oidc_token("signed-token")


def test_maps_diagnostics_identity_cannot_configure_openai():
    claims = trusted_claims()
    with pytest.raises(GitHubOIDCAuthenticationError):
        _validate_github_claims(claims, yandex_diagnostics=True)
    claims.update(aud=github_oidc.YANDEX_DIAGNOSTICS_AUDIENCE,
                  workflow_ref=github_oidc.YANDEX_DIAGNOSTICS_WORKFLOW_REF, event_name="workflow_run")
    _validate_github_claims(claims, yandex_diagnostics=True)
    with pytest.raises(GitHubOIDCAuthenticationError):
        _validate_github_claims(claims)
    for name, value in {"ref": "refs/heads/feature", "actor_id": "3", "event_name": "pull_request",
                        "repository_id": "1", "environment": "staging"}.items():
        with pytest.raises(GitHubOIDCAuthenticationError):
            _validate_github_claims({**claims, name: value}, yandex_diagnostics=True)


def test_signed_token_audience_is_isolated_between_diagnostics_and_key_installation(monkeypatch):
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    monkeypatch.setattr(github_oidc._jwks_client, "get_signing_key_from_jwt",
                        lambda _: SimpleNamespace(key=private_key.public_key()))
    claims = trusted_claims()
    token = jwt.encode(claims, private_key, algorithm="RS256", headers={"kid": "test-key"})
    assert github_oidc._decode_github_oidc_token(token)["aud"] == github_oidc.GITHUB_OIDC_AUDIENCE
    with pytest.raises(jwt.InvalidAudienceError):
        github_oidc._decode_yandex_diagnostics_token(token)
    claims["aud"] = github_oidc.YANDEX_DIAGNOSTICS_AUDIENCE
    token = jwt.encode(claims, private_key, algorithm="RS256", headers={"kid": "test-key"})
    assert github_oidc._decode_yandex_diagnostics_token(token)["aud"] == github_oidc.YANDEX_DIAGNOSTICS_AUDIENCE
    with pytest.raises(jwt.InvalidAudienceError):
        github_oidc._decode_github_oidc_token(token)


def test_administrator_identity_is_isolated_and_keeps_production_owner_gates(monkeypatch):
    claims = trusted_claims()
    with pytest.raises(GitHubOIDCAuthenticationError):
        _validate_github_claims(claims, configure_admin=True)
    claims.update(aud=github_oidc.ADMIN_CONFIGURATION_AUDIENCE,
                  workflow_ref=github_oidc.ADMIN_CONFIGURATION_WORKFLOW_REF)
    _validate_github_claims(claims, configure_admin=True)
    for options in ({}, {"yandex_diagnostics": True}):
        with pytest.raises(GitHubOIDCAuthenticationError):
            _validate_github_claims(claims, **options)
    for key, value in {"actor_id": "3", "environment": "staging", "event_name": "push",
                       "ref": "refs/heads/feature", "repository_id": "1",
                       "workflow_ref": github_oidc.GITHUB_WORKFLOW_REF,
                       "sub": "repo:Deels2024/buro:ref:refs/heads/main"}.items():
        with pytest.raises(GitHubOIDCAuthenticationError):
            _validate_github_claims({**claims, key: value}, configure_admin=True)
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    monkeypatch.setattr(github_oidc._jwks_client, "get_signing_key_from_jwt",
                        lambda _: SimpleNamespace(key=private_key.public_key()))
    token = jwt.encode(claims, private_key, algorithm="RS256", headers={"kid": "test-key"})
    assert github_oidc._decode_admin_configuration_token(token)["aud"] == github_oidc.ADMIN_CONFIGURATION_AUDIENCE
    for decoder in (github_oidc._decode_github_oidc_token, github_oidc._decode_yandex_diagnostics_token):
        with pytest.raises(jwt.InvalidAudienceError):
            decoder(token)


async def test_administrator_oidc_cannot_be_replayed(monkeypatch):
    from fakeredis.aioredis import FakeRedis

    claims = trusted_claims()
    claims.update(aud=github_oidc.ADMIN_CONFIGURATION_AUDIENCE,
                  workflow_ref=github_oidc.ADMIN_CONFIGURATION_WORKFLOW_REF)
    monkeypatch.setattr(github_oidc, "_decode_admin_configuration_token", lambda _: claims)
    async with FakeRedis(decode_responses=True) as redis:
        monkeypatch.setattr(github_oidc, "redis", redis)
        assert await verify_github_oidc_token("signed-admin-token", configure_admin=True) == claims
        with pytest.raises(GitHubOIDCAuthenticationError):
            await verify_github_oidc_token("signed-admin-token", configure_admin=True)
