"""Settings > Payments: the shop's own Razorpay account.

Only the shop's owner (not staff) sees the webhook secret or changes the keys. The key secret is
write-only: it is checked with Razorpay, stored encrypted, and never sent back.
"""

from fastapi import APIRouter, HTTPException, Response

from app.api.v1 import schemas
from app.api.v1.deps import Shop, ShopContext
from app.modules.conversations import service as conversations
from app.modules.payments import service as payments

router = APIRouter(prefix="/payments", tags=["payments"])


@router.get("/account")
async def get_account(shop: Shop) -> schemas.PaymentAccount:
    return _account(await payments.account_status(shop.merchant_id), shop)


@router.put("/account")
async def connect_account(
    shop: Shop, body: schemas.PaymentAccountConnect
) -> schemas.PaymentAccount:
    _owner_only(shop)
    try:
        status = await payments.connect_account(
            shop.merchant_id, key_id=body.key_id, key_secret=body.key_secret
        )
    except payments.AccountKeysRejected as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except payments.ProviderUnreachable as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    for result in status.settled:  # paid on the old keys' links while they were being closed
        await conversations.after_payment(result)
    return _account(status, shop)


@router.delete("/account", status_code=204)
async def disconnect_account(shop: Shop) -> Response:
    _owner_only(shop)
    for result in await payments.disconnect_account(shop.merchant_id):
        await conversations.after_payment(result)
    return Response(status_code=204)


@router.post("/account/webhook-secret")
async def rotate_webhook_secret(shop: Shop) -> schemas.PaymentAccount:
    """A new webhook secret (paste it into Razorpay's webhook too; until then webhooks fail and
    payments still confirm within a minute)."""
    _owner_only(shop)
    try:
        status = await payments.rotate_webhook_secret(shop.merchant_id)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail="Connect Razorpay first.") from exc
    return _account(status, shop)


def _owner_only(shop: ShopContext) -> None:
    if shop.role != "owner":
        raise HTTPException(status_code=403, detail="Only the shop's owner can change payments.")


def _account(status: payments.AccountStatus, shop: ShopContext) -> schemas.PaymentAccount:
    account = status.account
    owner = shop.role == "owner"
    return schemas.PaymentAccount(
        source=status.source,
        payments_ready=status.payments_ready,
        connected=account is not None,
        key_id_hint=account.key_id_hint if account else None,
        mode="live" if account and account.mode == "live" else ("test" if account else None),
        webhook_url=account.webhook_url if account else None,
        webhook_secret=account.webhook_secret if account and owner else None,
        webhook_events=list(payments.WEBHOOK_EVENTS),
        last_webhook_at=account.last_webhook_at if account else None,
        connected_at=account.verified_at if account else None,
    )
