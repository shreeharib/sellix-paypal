# Connecting a shop to Razorpay

Who this is for: a shop owner (or whoever sets up a shop) connecting the shop's own Razorpay
account to sellix, and the team testing payments.

Each shop uses **its own** Razorpay account. Customers pay on Razorpay's page (UPI, cards, net
banking, wallets), and the money settles straight into the shop's bank account. sellix never holds
the money.

## 1. Get the keys (5 minutes)

1. Sign up or sign in at <https://dashboard.razorpay.com>. **Test mode works without KYC**, so
   you can try everything before activating the account.
2. Pick the mode with the switch at the top of the dashboard. Test mode keys start with
   `rzp_test_`; live mode keys (after Razorpay activates your account) start with `rzp_live_`.
3. Open **Account & Settings → API Keys → Generate Key**. Copy the **Key ID** and the
   **Key Secret**. Razorpay shows the secret only once; if you lose it, regenerate it.

## 2. Connect in the sellix app

1. In the app: **Profile → Payments → Razorpay**.
2. Paste the Key ID and the Key Secret, then tap **Connect**. sellix checks them with Razorpay
   first. If Razorpay refuses them, the app says so; check that both come from the same mode.
3. The card then shows **Test** or **Live**, and the end of your key id.

Only the shop's owner can connect, change or disconnect Razorpay. The secret is stored encrypted
on the server and is never shown again.

## 3. Add the webhook (recommended, 3 minutes)

Without a webhook, payments still confirm: sellix asks Razorpay about every open link each
minute. With the webhook they confirm within seconds.

1. In the app's Razorpay card, copy the **Webhook URL** and the **Webhook secret**.
2. In Razorpay Dashboard (same mode as your keys): **Account & Settings → Webhooks → Add New
   Webhook**.
3. Paste the URL and the secret. Under **Active Events**, tick:
   - `payment_link.paid`
   - `payment_link.expired`
   - `payment_link.cancelled`
   - `payment.failed`
   - `refund.processed`
   - `refund.failed`
4. Save. After the next payment, the app's card says "Webhooks working".

Test mode and live mode have separate webhook lists in Razorpay: add the webhook in each mode you
use. The same URL and secret work for both. "New webhook secret" in the app makes a new secret;
paste it into Razorpay too.

## 4. What the customer sees

- After they confirm an order, the chat gets: "Order #1004 is placed: ₹180. Pay here (UPI, card or
  net banking): https://rzp.io/…". The items are held for 15 minutes.
- They pay on Razorpay's page. Back in the chat, sellix confirms the payment, and the order shows
  as paid in the app.
- If a try fails (a declined card, a cancelled UPI request), the same link still works. If the
  order is still unpaid about 90 seconds later, sellix sends one message with the same link.
- If the hold runs out, the stock goes back on sale and sellix cancels the link at Razorpay.

## 5. Refunds

On a paid order, tap **Refund**. sellix asks Razorpay to send the full amount back; it usually
reaches the customer in 5 to 7 working days. Razorpay takes refunds from your Razorpay balance: if
the balance is too low, Razorpay refuses and the app shows why.

Orders you marked paid yourself (UPI you saw on your phone, cash) are refunded by you; sellix only
records the refund.

## 6. Testing with test keys

On Razorpay's test page:

- **Card:** `4100 2800 0000 1007` (Visa), any future expiry, any CVV. On the bank page, an OTP of
  4 to 10 digits succeeds, and a shorter one fails.
- **UPI:** `success@razorpay` succeeds and `failure@razorpay` fails.
- Razorpay allows a limited number of payment links per business in test mode (the docs say 30).

No real money moves in test mode.

## If something goes wrong

| What you see | Why, and what to do |
|---|---|
| "Razorpay didn't accept these keys" | Wrong secret, or the Key ID and secret are from different modes. Regenerate the key in the dashboard and paste both again |
| "Couldn't reach Razorpay" | A network problem between the server and Razorpay. Try again in a minute |
| Customers get a `upi://` link instead of a Razorpay link | Razorpay isn't connected (or was disconnected): the shop's UPI ID is the fallback, and you confirm those payments yourself with **Mark paid** |
| Paid in Razorpay, but the order still says unpaid after 2 minutes | Check the order's Payments section in the app, and the server logs (`payments.settle_failed`). The webhook isn't needed for this, but the server must reach `api.razorpay.com` |
| "The Razorpay account this order was paid into isn't connected any more" on a refund | The shop changed or removed its keys. Reconnect the old keys, or refund from the Razorpay dashboard |
