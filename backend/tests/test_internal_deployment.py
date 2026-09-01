from unittest.mock import AsyncMock

from fastapi.testclient import TestClient

from app.api.routes import internal_deployment
from app.main import app

TEST_KEY = b"sk-test-value-0000000000000000000000000000000000000000"


def test_internal_configuration_requires_github_oidc() -> None:
    with TestClient(app) as client:
        response = client.post(
            "/v1/internal/deployment/openai-key",
            content=TEST_KEY,
            headers={"Content-Type": "application/octet-stream"},
        )
    assert response.status_code == 401


def test_internal_configuration_returns_verified_fingerprint(monkeypatch) -> None:
    monkeypatch.setattr(
        internal_deployment,
        "verify_github_oidc_token",
        AsyncMock(return_value={"repository": "Deels2024/buro"}),
    )
    configure = AsyncMock(return_value="gpt-5.6")
    monkeypatch.setattr(internal_deployment, "configure_openai_key", configure)

    with TestClient(app) as client:
        response = client.post(
            "/v1/internal/deployment/openai-key",
            content=TEST_KEY,
            headers={
                "Authorization": "Bearer signed-token",
                "Content-Type": "application/octet-stream",
            },
        )

    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert response.json() == {
        "status": "configured",
        "model": "gpt-5.6",
        "fingerprint_sha256": "fd7079e4a53b6c45bd31dc0ce2ab6d00cf98ac5f02dd31e2be34dcd2bd2c97ef",
    }
    configure.assert_awaited_once_with(TEST_KEY.decode("ascii"))


def test_internal_configuration_rejects_other_content_types(monkeypatch) -> None:
    monkeypatch.setattr(
        internal_deployment,
        "verify_github_oidc_token",
        AsyncMock(return_value={"repository": "Deels2024/buro"}),
    )
    configure = AsyncMock(return_value="gpt-5.6")
    monkeypatch.setattr(internal_deployment, "configure_openai_key", configure)

    with TestClient(app) as client:
        response = client.post(
            "/v1/internal/deployment/openai-key",
            content=TEST_KEY,
            headers={
                "Authorization": "Bearer signed-token",
                "Content-Type": "text/plain",
            },
        )

    assert response.status_code == 415
    configure.assert_not_awaited()
