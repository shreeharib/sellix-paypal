# API changes, 24 Nov 2026 (Razorpay and launch fixes)

The contract the backend and the Flutter app are built against in this round. All paths are under
`/v1` and need the merchant's bearer token unless marked otherwise. Times are ISO 8601 with offset.
Money is in minor units (paise). Error bodies are FastAPI's `{"detail": "<plain sentence for the
merchant>"}`; the app shows `detail` as is.

## 1. Payments: Razorpay replaces PayPal

PayPal is gone (no `/payments/paypal/*`, no `/webhooks/paypal`, no `POST /orders/{id}/invoice`).
Each shop connects its **own** Razorpay account; customers pay on Razorpay's page (UPI, card, net
banking, wallets). An order is paid only when Razorpay's own record says so.

### `GET /payments/account` -> `PaymentAccount`

```json
{
  "provider": "razorpay",
  "source": "own",                 // own | shared | simulator | none: where new payment links come from
  "payments_ready": true,          // false only when source is "none"
  "connected": true,               // the shop's own Razorpay account is connected
  "key_id_hint": "rzp_test_••••ab12",
  "mode": "test",                  // test | live | null
  "webhook_url": "https://api.example.com/webhooks/razorpay/Xy3...",   // null when not connected
  "webhook_secret": "k2J...",      // null when not connected, and for staff (owner only)
  "webhook_events": ["payment_link.paid", "payment_link.expired", "payment_link.cancelled",
                     "payment.failed", "refund.processed", "refund.failed"],
  "last_webhook_at": null,         // last verified webhook delivery; null: none yet
  "connected_at": "2026-11-24T10:00:00+05:30"
}
```

- `source: "shared"` means the server's own Razorpay keys (local testing only, never in production).
- `source: "simulator"` is the dev Accept/Reject page.

### `PUT /payments/account` body `{"key_id": "rzp_test_...", "key_secret": "..."}` -> `PaymentAccount`

- The server checks the keys with Razorpay first.
- 422: malformed keys, or keys Razorpay refused (the `detail` says which).
- 502: Razorpay couldn't be reached.
- 403: the caller is staff, not the owner.
- Reconnecting, including switching test to live, keeps the same `webhook_url` and `webhook_secret`.
- The key secret is never returned.

### `DELETE /payments/account` -> 204 (owner only)

New links fall back to the shop's UPI ID, or to "the shop will share payment details".

### `POST /payments/account/webhook-secret` -> `PaymentAccount`

Returns a new secret (owner only). 404 if not connected.

### Webhook setup the app explains to the owner

1. In Razorpay Dashboard, open Accounts & Settings, then Webhooks, then Add New Webhook.
2. Paste `webhook_url` and `webhook_secret`.
3. Tick the `webhook_events`.

Webhooks are optional: sellix also asks Razorpay about every open link each minute, so payments confirm within about a minute without them. With webhooks they confirm in seconds. `last_webhook_at` shows whether webhooks arrive.

Razorpay's test mode is set up separately from live mode in Razorpay's dashboard. The same URL and secret work for both.

### `GET /orders/{id}/payments` -> `OrderPayments`

```json
{
  "payments": [{
    "id": "uuid", "provider": "razorpay",      // razorpay | simulator | upi_manual | cash | manual
    "method": "upi",                           // upi | card | netbanking | wallet | emi | cardless_emi | paylater | bank_transfer | other | cash | simulator | null (unpaid)
    "status": "completed",                     // created (link open) | completed | refunded | cancelled | expired | denied | failed
    "amount_minor": 18000, "currency": "INR",
    "fee_minor": 425,                          // Razorpay's fee when known, else 0
    "link": null,                              // the payment link while status is "created"
    "provider_payment_id": "pay_ABC",          // Razorpay payment id, or the reference typed in on Mark paid
    "paid_at": "...", "created_at": "..."
  }],
  "refund": {"status": "pending", "amount_minor": 18000, "reason": "Out of stock",
             "provider_refund_id": "rfnd_X", "created_at": "..."},     // or null
  "refundable": true,
  "refund_mode": "razorpay"   // razorpay: money goes back automatically | manual: you return it, sellix records it | simulator | null
}
```

### `POST /orders/{id}/refund` body `{"reason": "...", "restock": true}` -> `RefundResponse`

```json
{"order_id": "...", "refund_id": "...", "amount_minor": 18000, "currency": "INR",
 "status": "pending", "mode": "razorpay"}
```

- `status` is `pending`, `completed` or `failed`.
- Razorpay refunds usually come back `pending`; the order turns `refunded` when Razorpay confirms.
- Manual and simulator refunds come back `completed` at once.
- 400 `detail`: not paid, or Razorpay refused (for example, not enough balance in the Razorpay account).
- Refunds are full only.

### Other payment changes

- **`GET /orders/{id}/payment-link`**:
  - `payment_method` is now `razorpay | upi | simulator` (was `upi | paypal`).
  - A link is Razorpay when the shop has an account, else the shop's UPI ID.
  - 409 if the order isn't waiting for payment.
  - 400 if no payment method is set up.
- **`GET /onboarding`**: `payments_ready` is now per shop (its own account, or shared or simulator).
- **Customer messages (code, not the model)**:
  - `payment_link` now says "Pay here (UPI, card or net banking)".
  - The new `payment_try_again` is sent once per order, about 90 s after a failed Razorpay try, if the same link is still unpaid.

## 2. Orders

- `GET /orders/{id}` -> `Order` (the same object as a list item). 404 if not this shop's.
- `GET /orders?before=<created_at of the last row>&limit=50`: paging, newest first. `before` is exclusive. Existing filters still apply.

## 3. Chats

- **`GET /chats?before=<last_message_at of the last row>&limit=50`**: paging, newest first.
- **`Conversation`** gains `agent_paused_until` (datetime or null).
  - A reply the merchant types in Instagram pauses the assistant for that chat with reason `merchant_replied`.
  - The pause lasts `AGENT_RESUME_AFTER_MERCHANT_HOURS` (default 12) and is then lifted on the next customer message.
  - `PUT /chats/{id}/agent {"active": true}` resumes at once.
- **`POST /chats/{id}/messages` body `{"text": "..."}`** (1 to 1000 characters) -> 201 `{"id": "uuid", "text": "...", "status": "queued", "created_at": "..."}`.
  - Sends the merchant's message to the customer through the outbox.
  - Pauses the assistant for that chat the same way as a reply typed in Instagram (reason `merchant_replied`).
  - 409 `detail` when Instagram's 24-hour reply window is closed.

## 4. Shop, rules, products

- **New shops start with the assistant off** (`agent_enabled: false`) on the v2 engine.
  - `PUT /onboarding` with `"complete": true` switches it on.
  - The owner can switch it any time with `PATCH /merchant {"agent_enabled": ...}`.
  - Existing shops are unchanged.
- **`GET /rules`** -> `[{"id": "uuid", "text": "...", "created_at": "..."}]`: the saved "always" answers.
- **`DELETE /rules/{id}`** -> 204.
- **`PATCH /products/{id}`**:
  - Accepts `"is_active": false` to remove a product. It disappears from stock lists, menus and the assistant; past orders keep it.
  - `"is_active": true` brings it back.
  - `name` renames the product without creating a new item.
- **`GET /products`** lists active products only, unless `?include_inactive=true`.
- **Stock modes are enforced on the server**:
  - `made_to_order` and `unlimited` items are always orderable, with no quantity or hold.
  - `inventory` items keep their count from day to day until sold.
  - `daily` items are unchanged.
- **`DELETE /shop`** body `{"confirm_name": "<exact shop name>"}` -> 204 (owner only). Deletes the shop and its data, and signs everyone out. 422 if the name doesn't match.
- **Public, no auth**:
  - `GET /privacy`: privacy policy page.
  - `GET /data-deletion`: how to delete your data.
  - `POST /auth/instagram/data-deletion`: Meta's data-deletion callback.

## 5. Sign-in

- A refresh token that was just rotated is still accepted for 2 minutes.
  - It returns a fresh pair, and the session stays signed in.
  - A lost refresh response on mobile data no longer signs the merchant out.
- Reuse after the 2 minutes still revokes the session.
