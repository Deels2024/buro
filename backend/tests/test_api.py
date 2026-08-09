from fastapi.testclient import TestClient

from app.main import app


def test_liveness_and_openapi() -> None:
    with TestClient(app) as client:
        response = client.get("/v1/health/live")
        assert response.status_code == 200
        assert response.json() == {"status": "ok", "version": "0.2.0"}
        schema = client.get("/openapi.json").json()
        assert schema["info"]["title"] == "Бюро находок API"
        assert "/v1/listings/ai/search" in schema["paths"]
        assert "/v1/claims/handover/scan" in schema["paths"]
        assert "/v1/admin/analytics/overview" in schema["paths"]
        assert "/v1/admin/support/tickets" in schema["paths"]
        assert "/v1/app/bootstrap" in schema["paths"]
