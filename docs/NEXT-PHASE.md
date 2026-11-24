# Next phase: launch

Rewritten 24 Nov 2026. The PayPal hackathon is over; sellix is being prepared for real shops with **Razorpay**
payments and a release APK. [HANDOFF.md](HANDOFF.md) is the record of what exists (section 4 is what changed
on 24 Nov); this file is the plan. Keep both true (see the end).

## 0. Start here (10 minutes)

1. Read [CLAUDE.md](../CLAUDE.md), then HANDOFF sections 1, 2, 3 (how to run things on this PC, traps up to 17), 4 and 7.
2. `git status` and `git log -3`. **The 24 Nov work is not committed** (about 150 files). The user's rule: show the
   diff, commit only when they say, never push. **Nothing may be uploaded from this laptop** (no Artifacts, Docs,
   pushes): keep deliverables as local files.
3. The API contract of the new endpoints: [api-changes-2026-11-24.md](api-changes-2026-11-24.md). Guides for people:
   [razorpay-setup.md](razorpay-setup.md) (a shop connects Razorpay), [DEPLOY.md](DEPLOY.md) (putting sellix online).

## 1. Where things stand (24 Nov)

- **Payments are Razorpay.** Each shop connects its own Razorpay account in the app (onboarding's Payments step,
  or Profile > Payments) by pasting its Key ID and Key Secret, with an in-app guide and an "Open Razorpay sign-up"
  button. The bank account lives in Razorpay. Payment links, verification against Razorpay, the minute-by-minute
  settle job (webhooks optional), refunds, and the "try again" message are built and tested against a fake Razorpay.
  **Never run against the real Razorpay yet** (T1).
- **Launch fixes:**
  - The backend now enforces stock modes (made to order, kept until sold).
  - A cross-shop stock write was closed.
  - New shops start with the assistant off until onboarding is done.
  - Other additions: sign-in survives flaky networks, chat pause and send from the app, saved rules, removing products, deleting a shop, privacy pages, production settings.
- **The app:**
  - Razorpay screens.
  - A server address set at run time ("Server" on sign-in and in Profile).
  - Release signing.
  - The sellix launcher icon.
  - Unfinished features hidden.
  - Local notifications while the app is alive (no push yet).
- **Checks on 24 Nov:**
  - Backend: 637 passed; ruff and basedpyright clean.
  - Flutter: analyze clean, 455 passed (20 skipped).
  - The app's 22 live contract tests pass against the new backend.
  - Release APK built: see HANDOFF 4.3.

## 2. Tasks, in order

### T1. Razorpay with real test keys (from this laptop, about 30 minutes, needs the user)
`api.razorpay.com` is reachable from this laptop. Webhooks can't reach it, but the settle job doesn't need them.

1. The user signs up at dashboard.razorpay.com (test mode, no KYC) and generates test keys.
2. Run the backend (`:8000`) and the web app (`:8080`), see HANDOFF section 3.
   - Sign in with a dev token for a dev shop.
   - In Profile > Payments, connect the test keys. Expect "Test" and the end of the key id.
3. In the simulator chat (`/simulator`), order something and confirm.
   - The payment message must carry an `https://rzp.io/...` link.
   - Open it in Chrome on this laptop and pay with card `4100 2800 0000 1007`, OTP `1234`.
   - The return page says "Thank you", and the order turns paid in the app within a minute.
   - The order's Payments section shows the method, the `pay_...` id and "Test payment".
4. Failure: on a new order, pay with a short OTP so the card fails.
   - After about 90 s the chat gets `payment_try_again` with the same link.
   - Paying it then still works.
5. Refund the paid order in the app. Expect `pending` or `completed`; Razorpay's dashboard shows the refund.
6. Expiry: leave an order unpaid for 17 minutes. The order expires and Razorpay's dashboard shows the link as cancelled.

Write down anything that differs from these expectations. The facts the code relies on are listed at the top of
`backend/app/modules/payments/razorpay.py`.

### T2. Put the backend online (needs the user and accounts; see DEPLOY.md)
The phone app can't work against this laptop (Netskope blocks Instagram; Razorpay and Meta can't call in). The user
chose to decide the host later. Whatever the host:
- a database with the migrations
- the API and the worker
- `APP_ENV=prod`
- an https `PUBLIC_BASE_URL`
- the Meta app's redirect and webhook URLs
- `/privacy` and `/data-deletion` with a real contact line
- rotated secrets

### T3. The phone test
Install `frontend/flutter_app/build/app/outputs/flutter-apk/app-release.apk`. Rebuild with `build_apk.cmd [https://server]`. Then check each of these:

1. The icon reads "sellix" with the logo.
2. On first launch, **Server**: enter the https address, tap **Check**, then **Save**.
3. Sign in with Instagram. The Instagram account needs a role on the Meta app while the app is in development mode.
4. Onboarding, including the Payments step:
   - the guide
   - Open Razorpay sign-up
   - pasting test keys
   - the optional webhook section
5. After "Open home", the assistant is on. Set today's stock, including a made-to-order item and a kept-until-sold item.
6. From another Instagram account, DM the shop. Order, confirm, and pay the Razorpay link with a test card. The order turns paid in the app.
7. Notifications: with the app in the background, a new question or a paid order gives a phone notification. Tapping it opens the right screen.
8. In a chat:
   - "I'll reply myself", the send box, and the pause banner.
   - Turn the assistant back on.
9. Refund an order. Remove a product. Delete a saved rule.
10. Turn airplane mode on for a minute. The app says it can't reach sellix and stays signed in.

The user describes what looks wrong. Never ask for screenshots.

### T4. Push notifications (needs a Firebase project)
Today the app polls every 60 s while it is alive, so nothing arrives once Android kills it. The plan (from the 24 Nov audit):
- **Database:** `merchant_devices`, plus a `notifications_sent` table.
- **API:** `POST /v1/devices`.
- **Job:** a periodic job finds new questions, paid orders, waiting drafts and closing windows, and sends them by FCM HTTP v1 with a route to open.
- **App:** `firebase_messaging` and `google-services.json`. Make the Gradle plugin conditional on the file, so builds without it still work.

### T5. Razorpay Partner (the user's decision on 24 Nov: keys now, Partner later)
The user applies to Razorpay's partner programme. Once approved, add "Connect with Razorpay" (OAuth) next to the
pasted keys:
- no keys to copy
- sellix creates the shop's webhook through the partner API
- the money still goes straight to each shop

Keep the pasted-keys path for shops that already have keys.

### T6. Meta and data
- App Review (advanced messaging access) and business verification.
- Confirm on one real deletion callback which id Meta sends. Both ids are matched now.
- A retention job for `webhook_events` raw payloads. They hold message text and aren't deleted with a shop.

### T7. Live AI evals (ask the user first: they send test chats to the configured model)
Needed after `context@6` (made-to-order wording) and the payment tool change. Run them twice (HANDOFF trap 7b; the
eval shop now also needs `set-agent ... on`).

### T8. Smaller items
1. The v1 prompt `customer_agent.md` says "N left" for made-to-order items.
2. The assistant can't take a made-to-order order for an arbitrary future date (`registry.stock_on`).
3. Tamil and Hindi review of `payment_link@3`, `payment_try_again@1` and the older templates.
4. Older open items: HANDOFF section 7 and 4b.

## 3. Decisions waiting on the user
1. When to commit, and whether to open a pull request (no push from this laptop).
2. Where to host (T2).
3. Whether to run the live AI evals (T7).
4. The contact line for the privacy pages.
5. Turning on `RAZORPAY_LIVE_KEYS_ONLY=true` once real shops take real orders. It refuses test keys, because with test keys customers could "pay" with Razorpay's test cards.

## 4. How to check everything
- **Backend**, from `backend/`:
  - `python -m uv run ruff check . && python -m uv run ruff format --check . && python -m uv run basedpyright`
  - `python -m uv run pytest -q -p no:cacheprovider` (about 11 minutes; run it in the background).
- **Flutter**, from `frontend/flutter_app`: `cmd //c 'D:\Android\flutter-direct.cmd analyze' < /dev/null` and `... test`.
- **The app against a real server:**
  - a throwaway database with every migration
  - `create-merchant`, `set-stock`, `issue-token`
  - the API on its own port with `RUN_WORKER_IN_PROCESS=false` (no model calls)
  - `LIVE_API_URL=... LIVE_TOKEN=... cmd //c 'D:\Android\flutter-direct.cmd test test/api/live_contract_test.dart'`
- **APK:** `frontend/flutter_app/build_apk.cmd` (or `build apk --release` through the launcher). Check the result with `D:\Android\sdk\build-tools\36.0.0\aapt2.exe dump badging <apk>`.

## 5. How to work with this user and on this PC
- The user runs commands in Windows **Command Prompt**: give them `cmd` syntax or a `.cmd` file.
- Bash only for Claude (PowerShell is blocked).
- Plain-language explanations, real test output, honesty about what wasn't checked.
- No screenshots, ever.
- **Helpers (subagents) on the default model work well in parallel:**
  - Give each its own files and its own test database.
  - Give exact contracts.
  - Verify their work yourself.
- Fable 5.2 is blocked by the organisation.
- A helper killed by an SSL error is resumed with SendMessage.

## 6. How to keep this
When a task here is done, delete it from section 2 and record what changed in HANDOFF section 4. Update the dates,
the memory notes (`MEMORY.md`), and never put secrets in either file.
