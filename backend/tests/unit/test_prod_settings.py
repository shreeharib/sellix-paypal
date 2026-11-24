"""Production hides the API's own docs and the simulator page; render.yaml runs prod safely."""

from typing import Any

import pytest
import yaml
from fastapi.testclient import TestClient

from app.core.config import BACKEND_DIR, get_settings
from app.main import create_app

HIDDEN_IN_PROD = ("/docs", "/redoc", "/openapi.json", "/simulator")


def test_prod_hides_the_docs_and_the_simulator(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(get_settings(), "app_env", "prod")
    client = TestClient(create_app())

    assert {path: client.get(path).status_code for path in HIDDEN_IN_PROD} == dict.fromkeys(
        HIDDEN_IN_PROD, 404
    )
    assert client.get("/health").status_code == 200
    assert client.get("/privacy").status_code == 200


def test_other_environments_keep_them() -> None:
    client = TestClient(create_app())

    assert {path: client.get(path).status_code for path in HIDDEN_IN_PROD} == dict.fromkeys(
        HIDDEN_IN_PROD, 200
    )


def _env(service: dict[str, Any]) -> dict[str, Any]:
    return {var["key"]: var.get("value") for var in service["envVars"]}


def test_render_runs_the_api_and_the_worker_as_prod() -> None:
    blueprint = yaml.safe_load((BACKEND_DIR.parent / "render.yaml").read_text(encoding="utf-8"))
    services = {service["name"]: _env(service) for service in blueprint["services"]}

    assert services["sellix-api"]["APP_ENV"] == "prod"
    assert services["sellix-worker"]["APP_ENV"] == "prod"
    assert services["sellix-api"]["LOG_WEBHOOK_PAYLOADS"] == "false"
    # "*" would let any client choose the address the per-IP limits see.
    trusted = services["sellix-api"]["FORWARDED_ALLOW_IPS"]
    assert "*" not in trusted
