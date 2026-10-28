# sellix development checklist (Omnichannel Enterprise SaaS)

> **ARCHITECTURAL STANDARD: Omnichannel Enterprise SaaS**
> All roadmap items and development deliverables must adhere to the **Omnichannel Enterprise SaaS** architecture (`docs/database-schema.md` & `conflicts.md`).
> Specifically:
> 1. **Channels:** Unified support for Instagram DMs, WhatsApp Cloud API, and Counter POS.
> 2. **Stock & Holds:** Multi-mode stock (`daily`, `inventory`, `made_to_order`, `unlimited`, `serialized`) and standalone `stock_holds` with `release_expired_holds()`.
> 3. **Order Status:** Orthogonal triple-status updates (`status`, `payment_status`, `fulfilment_status`) ensuring database triggers and analytics views fire properly.
> 4. **Escalations:** Structured `escalation_rules` SQL table persistence with dynamic prompt compilation.
> 5. **Tenancy:** Citus-ready `merchant_id` tenant isolation on all tables.
>
> Finish the product before planning the launch. Work top to bottom; each item is done only when its **Done when** line works end-to-end. Tick the box in the pull request that finishes it.
>
> **Who:** P = platform and channels · AI = agent · A = Flutter app · C = commerce and data · F = founder


## 1. Development setup

- [ ] **1.1 Code on GitHub** (P). Push the repo, add teammates, turn on the CI in `.github/workflows`, fill in `.github/CODEOWNERS`.
  Done when: a pull request shows green checks.
- [ ] **1.2 Meta developer app** (F). Create the sellix app with "Instagram API with Instagram login"; add teammates as developers.
  Done when: the app ID and secret are in the team password manager and in each developer's `backend/.env`.
- [ ] **1.3 Test shop account** (F). An Instagram professional (Business or Creator) account for testing, plus one personal account to act as the customer; add the shop account as an Instagram tester on the Meta app and accept the invite in Instagram.
  Done when: the shop account shows as an accepted tester.
- [ ] **1.4 Public https address for local development** (P). A tunnel to the local API (`cloudflared tunnel --url http://localhost:8000`, or the Docker command in `commands.md`); put the URL in `PUBLIC_BASE_URL`. Later replaced by a shared dev server.
  Done when: `<tunnel>/health` returns `ok` from a phone.
- [ ] **1.5 Wire the Meta app** (P). Webhook URL `<tunnel>/webhooks/meta` with `META_VERIFY_TOKEN`, fields `messages` and `messaging_postbacks`; OAuth redirect `<tunnel>/oauth/instagram/callback`.
  Done when: Meta's webhook verification succeeds.
- [ ] **1.6 Shared dev server** (P). Deploy from `render.yaml` with a managed Postgres; deploys automatically on each merge to `main`; point the Meta app at it instead of a laptop.
  Done when: the whole team tests against one server without tunnels.

## 2. Instagram connection, end to end

- [ ] **2.1 Real sign-in** (P + A). "Continue with Instagram" with the test shop account from the web app.
  Done when: the app lands on onboarding and Settings shows the account as active.
- [ ] **2.2 First real reply** (AI). DM the test shop from the personal account.
  Done when: the agent replies correctly within about 5 seconds.
- [ ] **2.3 Echoes** (P). Reply by hand from the Instagram app in a chat.
  Done when: the agent stops replying in that chat; the payload is recorded in `meta-payloads.md`.
- [ ] **2.4 Returning merchant** (P). Sign out and sign in again.
  Done when: the same shop opens, no duplicate, and onboarding is not shown again.
- [ ] **2.5 Token refresh** (P). Force a token near expiry and run the refresh job.
  Done when: the token is replaced and the agent still sends.
- [ ] **2.6 Deauthorize callback** (P). When the merchant removes sellix in Instagram settings, mark the connection revoked and stop replying; the app shows "reconnect".
  Done when: removing the app in Instagram flips the status, covered by a test.
- [ ] **2.7 Data deletion callback** (P). Meta's signed request deletes the merchant's data and returns a status URL.
  Done when: registered in the Meta app, covered by a test.

## 3. Onboarding and Settings

- [x] **3.1 Onboarding screens and shop profile generator** (A + C). Done 25 Oct 2026.
- [ ] **3.2 Payments step** (A + C). Store the merchant's UPI ID during onboarding.
  Done when: saved and visible in Settings.
- [ ] **3.3 Alerts step** (A + C). Morning reminder time, quiet hours.
  Done when: saved and visible in Settings.
- [ ] **3.4 Settings as forms** (A). Settings edits the same answers as onboarding (shop, products, persona, policies), not raw Markdown; the profile regenerates on save.
  Done when: a change in Settings shows up in the agent's next reply.
- [ ] **3.5 Test chat** (A + AI). From onboarding, the merchant can chat with their own agent as a customer would, without Instagram.
  Done when: the test chat answers from the shop's profile and stock.

## 4. Stock (Today screen)

- [x] **4.1 Opening stock and live counts** (C + A). Built.
- [x] **4.2 Restock** (C + A). Add quantity to an item during the day (`POST /v1/today/restock`). Built & tested.
- [x] **4.3 Sold out** (C + A). Mark an item sold out in one tap (`POST /v1/today/sold-out`). Built & tested.
- [x] **4.4 Counter sale** (C + A). Record a sale made in the shop (`POST /v1/today/counter-sale`). Built & tested.
- [x] **4.5 Stock by text** (AI + A). Type "10 choc cookies 60rs, 5 brownies 90" and confirm the parsed list (`POST /v1/today/parse-stock-text`). Built & tested.
- [x] **4.6 Leftovers & Daily Ledger Rollover** (C + DB). Stored procedure `rollover_daily_stock()` auto-rolls forward perpetual `inventory` and multi-day items (`shelf_life_days > 1`). `GET /v1/today/leftovers` and `POST /v1/today/rollover` empower merchants to customize exact carryover quantities (e.g. 4 out of 10 yesterday leftovers) for today's opening stock. Built & tested.
- [x] **4.7 Dual-Engine Catalog Architecture & Fuzzy AI Search** (C + AI + DB). Bridges fast-path morning stock entries with enterprise multi-category enrichment (`attributes JSONB`, `compare_at_price_minor`, `cost_price_minor`, auto-SKU generation, and `pg_trgm` GIN-indexed fuzzy search `/v1/products/search`). Built & tested.

## 5. Orders and payments

- [x] **5.1 Orders, 15-minute holds and expiry** (C). Built & Wired. `stock_holds` established as single source of truth across Python and PostgreSQL `release_expired_holds()`, with full lifecycle tests.

- [x] **5.2 PayPal checkout and webhook** (C). Built (sandbox).
- [x] **5.3 UPI payment request** (C + AI). For INR orders the agent sends the merchant's UPI ID and the exact amount; the order waits as "payment pending".
  Done when: a DM order shows the UPI message.
- [x] **5.4 "Paid" button & Dual-Rail Settlement** (C + A). The merchant taps **Paid** in Orders (with optional payment method e.g. 'upi' or 'cash' and reference ID): creates a formal `payments` record (`provider IN ('upi_manual', 'cash', 'manual')`, `method`, `kind = 'full'`), sets `status = 'paid'` and `payment_status = 'paid'`, stock sold, customer gets a confirmation, database triggers fire (`trg_order_paid` CRM customer metrics, `trg_order_timeline` audit logging).
  Done when: full UPI and cash counter sales drop stock, persist Payment records, and update CRM analytics.
- [ ] **5.5 Customer says "paid"** (C + AI). Keep the hold while waiting for the merchant to check; don't let it expire.
  Done when: covered by a test.
- [x] **5.6 Complete, advance stages, and cancel** (C + A). Mark an order through enterprise fulfillment stages (`confirmed` -> `ready` -> `delivered` -> `completed`, via `/v1/orders/{id}/status`) or cancelled (stock returns). Automatically logs transitions in `order_timeline` via `trg_order_timeline` and updates CRM customer lifetime metrics via `trg_order_paid`.
  Done when: works from Orders, timeline logged, and updates Today.
- [ ] **5.7 PayPal end to end with a real DM** (C). Sandbox buyer pays from the link the agent sent.
  Done when: the order turns paid by the webhook alone.

## 6. Ask me (escalations)

- [x] **6.1 Questions backend and screen** (C + A). Built.
- [ ] **6.2 End to end with a real DM** (AI + C). Ask for a custom cake; the agent asks the merchant; the merchant's answer reaches the customer.
  Done when: works in one session.
- [ ] **6.3 Save answer as a rule** (C + A). Offer "Always answer this way"; approved answers persist into the `escalation_rules` SQL table and compile dynamically into the prompt.
  Done when: the same question later is answered without asking.

## 7. Push notifications

- [ ] **7.1 Firebase setup** (P + A). Cloud Messaging in the app; device token saved on sign-in, removed on sign-out.
  Done when: a test push reaches an Android phone.
- [ ] **7.2 Customer says they paid** (C). Done when: arrives within 10 seconds and opens the order.
- [ ] **7.3 New Ask me question** (C). Done when: tapping it opens the question.
- [ ] **7.4 Low stock** (C). Triggers when stock $\le 2$ or reaches the merchant's percentage threshold (e.g. $\le 20\%$). Done when: fires once per threshold event.

- [ ] **7.5 Morning stock reminder** (C). At the time set in 3.3, in the merchant's time zone. Done when: arrives on time.

## 8. Story replies

- [ ] **8.1 Save the story** (P). On the first reply to a story, download the media before its link expires.
  Done when: stored and linked to the conversation.
- [ ] **8.2 Tag stories to products** (A + C). On Today, the merchant links a story to a product.
  Done when: the link is saved.
- [ ] **8.3 Agent uses it** (AI). "How much is this?" on a story gets the right product and price; an untagged story makes the agent ask.
  Done when: both cases work with a real story.

## 9. Agent quality

- [ ] **9.1 Test set** (AI). 50 real chats (anonymised) in Tamil-English, Hinglish and English, each with the correct outcome; stored in `evals/`.
  Done when: committed.
- [ ] **9.2 Accuracy** (AI). Run the agent on all 50 and fix prompts until 90% or better.
  Done when: score recorded here: ____%.
- [ ] **9.3 Guard prompt changes** (AI). CI runs the test set when prompts change; no merge if the score drops.
  Done when: CI enforces it.
- [ ] **9.4 Cost per conversation** (AI). Logged per merchant.
  Done when: estimated cost for 300 orders a month is under ₹250.
- [ ] **9.5 Honest about being an assistant** (AI). When asked, says it is the shop's assistant and a person is available.
  Done when: in the test set.

## 10. Finished-product check

- [ ] **10.1 Android build** (A). Debug APK runs on a real phone against the dev server, including sign-in.
  Done when: a full sale works on the phone.
- [ ] **10.2 Tamil** (A). Every screen reviewed in Tamil by a native speaker.
  Done when: no English left and no wrong words.
- [ ] **10.3 Errors and empty states** (A). Every screen handles no internet, server errors and empty lists.
  Done when: checked with the API stopped.
- [ ] **10.4 Full run** (all). On the dev server, in one session: sign-in, onboarding, stock, a UPI sale, a PayPal sale, an Ask me question, a story reply, a hand reply that pauses the agent.
  Done when: all pass without fixes. **Then plan the launch.**

## Already built

Continue with Instagram (token, webhook subscription, shop creation) · webhook inbox, deduplication, 3-second batching · customer agent · stock holds and expiry · orders · PayPal (sandbox) · Ask me backend and screen · Today, Orders, Chats, Settings screens · per-chat and shop-wide agent switch · onboarding and shop profile generator · clear error when Instagram sign-in isn't configured.
