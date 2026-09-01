import time

import pytest

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
