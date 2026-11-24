"""The Razorpay client: signatures, the requests it sends, and how it reads Razorpay's answers."""

import time

import httpx2
import pytest

from app.modules.payments import razorpay
from tests.conftest import RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET
from tests.integration.fake_razorpay import FakeRazorpay

pytestmark = pytest.mark.anyio

KEYS = razorpay.Credentials(RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET)


def test_the_callback_signature_matches_razorpays_published_example() -> None:
    # The example in Razorpay's Payment Links docs (Java sample): fields joined with "|".
    assert razorpay.verify_callback(
        link_id="plink_IH3cNucfVEgV68",
        reference_id="TSsd1989",
        status="paid",
        payment_id="pay_IH3d0ara9bSsjQ",
        signature="07ae18789e35093e51d0a491eb9922646f3f82773547e5b0f67ee3f2d3bf7d5b",
        key_secret="EnLs21M47BllR3X8PSFtjtbd",
    )
    assert not razorpay.verify_callback(
        link_id="plink_IH3cNucfVEgV68",
        reference_id="TSsd1989",
        status="paid",
        payment_id="pay_SOMEONE_ELSE",
        signature="07ae18789e35093e51d0a491eb9922646f3f82773547e5b0f67ee3f2d3bf7d5b",
        key_secret="EnLs21M47BllR3X8PSFtjtbd",
    )


def test_a_webhook_is_genuine_only_with_the_hmac_of_its_exact_body() -> None:
    body = b'{"event":"payment_link.paid"}'
    signature = FakeRazorpay.sign(body, "whsec")
    assert razorpay.verify_webhook(body, signature, "whsec")
    assert not razorpay.verify_webhook(body + b" ", signature, "whsec")
    assert not razorpay.verify_webhook(body, signature, "other-secret")
    assert not razorpay.verify_webhook(body, "", "whsec")
    assert not razorpay.verify_webhook(body, signature, "")


@pytest.mark.parametrize(
    ("key_id", "mode"),
    [
        ("rzp_test_1DP5mmOlF5G5ag", "test"),
        ("rzp_live_ILgsfZCZoFIKMb", "live"),
        (" rzp_test_1DP5mmOlF5G5ag ", "test"),
        ("rzp_prod_1DP5mmOlF5G5ag", None),
        ("pk_test_123456", None),
        ("rzp_test_", None),
    ],
)
def test_the_mode_comes_from_the_key_ids_prefix(key_id: str, mode: str | None) -> None:
    assert razorpay.mode_of(key_id) == mode


def test_the_key_hint_shows_only_the_last_four_characters() -> None:
    from app.modules.payments.accounts import key_id_hint

    assert key_id_hint("rzp_test_1DP5mmOlF5G5ag") == "rzp_test_••••G5ag"


async def test_a_link_is_created_with_only_documented_fields(fake_razorpay: FakeRazorpay) -> None:
    expire_by = int(time.time()) + 20 * 60
    link = await razorpay.create_link(
        KEYS,
        amount_minor=18000,
        currency="INR",
        reference_id="SX1004-" + "a" * 40,  # longer than Razorpay allows: cut to 40
        description="Sweet Crumbs order #1004",
        expire_by=expire_by,
        callback_url="https://sellix.test/payments/razorpay/return",
        notes={"sellix_order_id": "o-1", "long": "x" * 300},
    )

    method, path, key_id, body = fake_razorpay.requests[-1]
    assert (method, path, key_id) == ("POST", "/v1/payment_links", RAZORPAY_KEY_ID)
    assert body["amount"] == 18000 and body["expire_by"] == expire_by
    assert body["notify"] == {"sms": False, "email": False}
    assert body["callback_method"] == "get" and body["accept_partial"] is False
    assert len(body["reference_id"]) == 40 and len(body["notes"]["long"]) == 255
    assert link.id.startswith("plink_") and link.short_url.startswith("https://rzp.io/")
    assert link.status == "created" and link.order_id == ""  # create says no order id


async def test_razorpay_errors_carry_its_description(fake_razorpay: FakeRazorpay) -> None:
    with pytest.raises(razorpay.RazorpayError) as raised:
        await razorpay.create_link(
            KEYS,
            amount_minor=18000,
            currency="INR",
            reference_id="SX1",
            description="x",
            expire_by=int(time.time()) + 60,  # too soon
            callback_url="https://sellix.test/r",
            notes={},
        )
    assert raised.value.status == 400
    assert "15 minutes" in raised.value.description
    assert not raised.value.retryable


async def test_wrong_keys_are_reported_as_bad_keys(fake_razorpay: FakeRazorpay) -> None:
    with pytest.raises(razorpay.RazorpayError) as raised:
        await razorpay.check_keys(razorpay.Credentials(RAZORPAY_KEY_ID, "WrongSecret123456"))
    assert raised.value.bad_keys and raised.value.status == 401
    await razorpay.check_keys(KEYS)  # the right ones pass


async def test_a_look_up_is_retried_after_a_server_error_but_a_new_link_is_not(
    fake_razorpay: FakeRazorpay,
) -> None:
    link = await razorpay.create_link(
        KEYS,
        amount_minor=18000,
        currency="INR",
        reference_id="SX2",
        description="x",
        expire_by=int(time.time()) + 20 * 60,
        callback_url="https://sellix.test/r",
        notes={},
    )
    fake_razorpay.fail_next = [(502, "Bad gateway"), (503, "Unavailable")]
    fetched = await razorpay.fetch_link(KEYS, link.id)
    assert fetched.id == link.id

    fake_razorpay.fail_next = [(502, "Bad gateway")]
    with pytest.raises(razorpay.RazorpayError) as raised:
        await razorpay.create_link(
            KEYS,
            amount_minor=18000,
            currency="INR",
            reference_id="SX3",
            description="x",
            expire_by=int(time.time()) + 20 * 60,
            callback_url="https://sellix.test/r",
            notes={},
        )
    assert raised.value.retryable
    assert [r[1] for r in fake_razorpay.requests].count("/v1/payment_links") == 2


async def test_a_network_failure_is_a_retryable_error(monkeypatch: pytest.MonkeyPatch) -> None:
    def refuse(request: httpx2.Request) -> httpx2.Response:
        raise httpx2.ConnectError("no route", request=request)

    monkeypatch.setattr(razorpay, "_RETRY_DELAYS", (0.0, 0.0))
    razorpay.use_transport(httpx2.MockTransport(refuse))
    try:
        with pytest.raises(razorpay.RazorpayError) as raised:
            await razorpay.fetch_link(KEYS, "plink_1")
    finally:
        razorpay.use_transport(None)
    assert raised.value.status == 0 and raised.value.retryable


def test_a_link_without_notes_or_payments_reads_cleanly() -> None:
    link = razorpay.link_from(
        {"id": "plink_1", "status": "created", "amount": 100, "notes": [], "payments": None}
    )
    assert link.notes == {} and link.payments == () and link.captured_payment is None


async def test_refunds_are_idempotent_by_their_key(fake_razorpay: FakeRazorpay) -> None:
    link = await razorpay.create_link(
        KEYS,
        amount_minor=18000,
        currency="INR",
        reference_id="SX4",
        description="x",
        expire_by=int(time.time()) + 20 * 60,
        callback_url="https://sellix.test/r",
        notes={},
    )
    payment_id = fake_razorpay.pay(link.id)

    first = await razorpay.create_refund(
        KEYS, payment_id, amount_minor=18000, idempotency_key="refund-key-0001"
    )
    again = await razorpay.create_refund(
        KEYS, payment_id, amount_minor=18000, idempotency_key="refund-key-0001"
    )

    assert first.id == again.id and first.status == "processed"
    assert len(fake_razorpay.refunds) == 1
    headers_sent = [r for r in fake_razorpay.requests if r[1].endswith("/refund")]
    assert len(headers_sent) == 2
    assert [r.receipt for r in await razorpay.payment_refunds(KEYS, payment_id)] == [
        "refund-key-0001"
    ]
