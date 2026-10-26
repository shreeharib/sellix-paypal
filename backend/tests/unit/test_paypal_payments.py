from typing import Any

import pytest

from app.modules.payments import paypal


@pytest.mark.anyio
async def test_create_order_includes_guest_checkout_for_cards(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(paypal, "configured", lambda: True)

    captured_request: dict[str, Any] = {}

    async def mock_request(
        method: str, path: str, *, json: Any = None, request_id: Any = None
    ) -> dict[str, Any]:
        captured_request["method"] = method
        captured_request["path"] = path
        captured_request["json"] = json
        return {
            "id": "ORDER-123",
            "links": [
                {
                    "rel": "approve",
                    "href": "https://www.sandbox.paypal.com/checkoutnow?token=ORDER-123",
                }
            ],
        }

    monkeypatch.setattr(paypal, "_request", mock_request)

    created = await paypal.create_order(
        reference_id="order-ref-1",
        description="Cake Order #1001",
        amount_minor=2500,
        currency="USD",
        brand_name="Sweet Crumbs",
        return_url="https://sellix.local/return",
        cancel_url="https://sellix.local/cancel",
    )

    assert created.paypal_order_id == "ORDER-123"
    assert "checkoutnow" in created.approve_url
    assert captured_request["path"] == "/v2/checkout/orders"
    experience = captured_request["json"]["payment_source"]["paypal"]["experience_context"]
    # Check that guest checkout is enabled for Debit/Credit cards
    assert experience["landing_page"] == "GUEST_CHECKOUT"


@pytest.mark.anyio
async def test_create_invoice(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(paypal, "configured", lambda: True)

    captured_request: dict[str, Any] = {}

    async def mock_request(
        method: str, path: str, *, json: Any = None, request_id: Any = None
    ) -> dict[str, Any]:
        captured_request["method"] = method
        captured_request["path"] = path
        captured_request["json"] = json
        return {"id": "INV2-TEST-INVOICE-ID"}

    monkeypatch.setattr(paypal, "_request", mock_request)

    invoice_id = await paypal.create_invoice(
        reference_id="order-cake-99",
        invoice_number="INV-1099",
        description="Custom Birthday Cake",
        items=[{"name": "2kg Theme Cake", "unit_price_minor": 5000, "quantity": 1}],
        total_minor=5000,
        currency="USD",
        brand_name="Sweet Crumbs",
        customer_name="Priya",
        customer_email="priya@example.com",
    )

    assert invoice_id == "INV2-TEST-INVOICE-ID"
    assert captured_request["path"] == "/v2/invoicing/invoices"
    payload = captured_request["json"]
    assert payload["amount"]["value"] == "50.00"
    assert payload["primary_recipients"][0]["billing_info"]["name"]["given_name"] == "Priya"


@pytest.mark.anyio
async def test_send_invoice_returns_payer_view_url(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(paypal, "configured", lambda: True)

    async def mock_request(
        method: str, path: str, *, json: Any = None, request_id: Any = None
    ) -> dict[str, Any]:
        return {
            "links": [
                {
                    "rel": "self",
                    "href": "https://api-m.sandbox.paypal.com/v2/invoicing/invoices/INV2-123",
                },
                {
                    "rel": "payer-view",
                    "href": "https://www.sandbox.paypal.com/invoice/p/#INV2-123",
                },
            ]
        }

    monkeypatch.setattr(paypal, "_request", mock_request)

    link = await paypal.send_invoice("INV2-123")
    assert link == "https://www.sandbox.paypal.com/invoice/p/#INV2-123"


@pytest.mark.anyio
async def test_refund_capture_calls_refund_api(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(paypal, "configured", lambda: True)

    captured: dict[str, Any] = {}

    async def mock_request(
        method: str, path: str, *, json: Any = None, request_id: Any = None
    ) -> dict[str, Any]:
        captured["path"] = path
        captured["json"] = json
        return {
            "id": "REFUND-999",
            "status": "COMPLETED",
            "amount": {"value": "25.00", "currency_code": "USD"},
        }

    monkeypatch.setattr(paypal, "_request", mock_request)

    result = await paypal.refund_capture(
        "CAPTURE-888",
        amount_minor=2500,
        currency="USD",
        note="Customer cancelled order",
    )

    assert result.refund_id == "REFUND-999"
    assert result.status == "COMPLETED"
    assert result.amount_minor == 2500
    assert result.currency == "USD"
    assert captured["path"] == "/v2/payments/captures/CAPTURE-888/refund"
    assert captured["json"]["note_to_payer"] == "Customer cancelled order"
