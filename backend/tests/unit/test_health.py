from fastapi.testclient import TestClient

from app.main import create_app


def test_health() -> None:
    response = TestClient(create_app()).get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "env": "test"}


def test_browser_calls_are_allowed_only_from_the_web_app() -> None:
    client = TestClient(create_app())
    preflight = {"Access-Control-Request-Method": "GET"}

    allowed = client.options("/v1/today", headers={"Origin": "http://localhost:8080", **preflight})
    other = client.options("/v1/today", headers={"Origin": "https://evil.test", **preflight})

    assert allowed.headers.get("access-control-allow-origin") == "http://localhost:8080"
    assert "access-control-allow-origin" not in other.headers
