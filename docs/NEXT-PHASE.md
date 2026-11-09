# Next phase

Written 8 Nov 2026 and updated 9 Nov 2026 for the next Claude session. It says what to do next, in order, with enough detail to start without the previous conversation. [HANDOFF.md](HANDOFF.md) is the long record of what exists; this file is the plan. Keep both true (see "How to keep this" at the end).

## 0. Start here (10 minutes)

1. Read [CLAUDE.md](../CLAUDE.md), then [HANDOFF.md](HANDOFF.md) sections 1, 3 (how to run and check everything on this PC, and the traps, now up to 13), 4.6 to 4.10 (what was built on 8 and 9 Nov) and 7 (open items), then this file.
2. `git status` and `git log -3`. **All of 8 and 9 Nov is uncommitted: 95 entries in `git status`** on branch `feat/preorders-and-agent-hardening` (58 backend, 31 Flutter, plus docs, the evals datasets and one migration). The user's rule: commit only when they say so, show the diff first, never push.
3. The running dev servers are **older builds**. Nothing from 8 Nov is live until the user restarts them (they use Windows **Command Prompt**, not Git Bash):
   - API: `D:\Tools\sellix\restart-sellix-api.cmd` (real PayPal sandbox) or `D:\Tools\sellix\restart-sellix-api.cmd simulator` (the Accept / Reject page). Claude is not allowed to kill their processes: ask them to run it.
   - Web app: `D:\Tools\sellix\run-sellix-web.cmd`. It runs the Flutter code from the copy at `D:\Android\cache\tmp\sellix_copy`, so first `cp -r lib test /d/Android/cache/tmp/sellix_copy/` from `frontend/flutter_app` (synced on 9 Nov after the last change).
   - The migration `supabase/migrations/20261108000000_payment_simulator_provider.sql` is already applied to the dev DB `sellix`.
4. Do the checks in section 5 once, to know the starting point is green: backend 521 passed, Flutter 402 passed (20 skipped), `ruff` and `basedpyright` clean.

## 1. Where things stand

**Product:** an Instagram DM assistant plus a Flutter merchant app for small online shops (HANDOFF section 1). Demo shop "Sweet Crumbs" (a bakery), merchant id `88fa6847-ea60-48d3-9be7-4877c2073130`, DB `sellix`, engine v2.

**Built and tested on 8 Nov (uncommitted):**
- PayPal for a rupee shop: the order stays in ₹, PayPal charges dollars at a live rate (`payments/fx.py`). The real sandbox rejects INR, so this was the only way.
- Payment retries: cooldown, max attempts, time window (`payments.service._retry_policy`), a "New payment link" button handled in code, the order cancelled when tries or time run out.
- A built-in payment simulator (`PAYMENT_PROVIDER=simulator`): a page with Accept and Reject buttons that sends a signed webhook through the real inbox and job. PayPal has no such page (docs checked); the real PayPal path stays the default.
- The cancel bug: `cancel_order` and `resend_payment_link` could never work with the real model (no order id in its context). Fixed, and the playbook that told the model to ask the owner was rewritten (`payment_problem@2`).
- Fixed messages when the model is down for payment-received and order-expired events.
- Shop-type templates (`shop_profile/shop_types.yaml`: bakery, jewellery, beauty, plants, handmade_gifts, dress_shop, other) and the Flutter add-product form that follows them. Shelf life is asked only for fresh-batch shops.
- "1 week / until sold" was silently dropped by the API: fixed. `/v1/today` rows now carry the stock type.

**Built and tested on 9 Nov (uncommitted, HANDOFF 4.10):** a typed "ok" no longer places an order (Confirm tap or a clear "confirm" only); off-topic messages and insults get `abuse_or_off_topic`; the profile and the app no longer carry "Introduce yourself" or "Sir or madam" (Sweet Crumbs re-saved, profile v5); "+" on the stock screens works in the web app again (a web-only bug: `-1 << 31` is positive on the web) and its count is exposed to screen readers. Marking an order ready / packed / delivered / sent now messages the customer (fixed templates; it was never built). Backend 521 passed, Flutter 402 passed; live evals 37/37 twice (one earlier run 36/37 on a too-strict check) and owner answers + pre-orders 11/11 twice.

**Verified on 8 Nov:** backend 470 passed; the 4 real PayPal sandbox tests; Flutter `analyze` clean and 400 passed; the app's 18 live contract tests against the new backend code; live evals (real model) 31/31 twice and 11/11 (owner answers, pre-orders). **Not verified:** nobody has looked at the new screens in a real browser; no real sandbox buyer has paid with the converted dollar amount; the simulator pages have not been seen by eye.

## 2. The deadline and what the judges need

PayPal AI Hackathon on Devpost: submissions close **12 Nov 2026, 12:00 PM Pacific**. In November that is PST (UTC-8), so about **1:30 AM IST on 13 Nov** (check this yourself). The user's internal demo freeze was about 9 Nov. Source: `https://paypalaihackathon.devpost.com/rules`, read via the WebFetch tool (GitHub and Devpost are blocked from command-line clients on this laptop, but SSH to GitHub works and Chrome reaches Devpost).

A valid submission needs:
- a text description of the features;
- a **functional** demo: judges must be able to run it from setup instructions in the repo, or from a hosted URL (a mock-up does not count);
- a **public** repository with an open source licence file (the repo has AGPL-3.0, good);
- a demo video under 3 minutes, public on YouTube, showing it working on the device it was built for;
- test access if anything is private.
PayPal must be central and the sandbox is the expected environment. There is a "Best Use of Agentic Commerce" prize. Judging is five equal criteria: technology, design, impact, idea, presentation; judges may judge from the text, images and video alone, so the video matters most.

## 3. Tasks, in order

Each task lists the files, what done means, and how to check it. T1 to T3 were done on 9 Nov (HANDOFF 4.10). Rules that apply to every task: a change to a prompt, playbook, tool, context or output check needs a row in `backend/app/modules/agent/prompts/CHANGELOG.md` and the live evals run **twice** (HANDOFF section 3, trap 7b); a new database change is a **new** migration file, never an edit to a merged one; modules import only each other's `service` and `schemas` (a unit test enforces it).

### T4. The "+" button on the stock screens: fixed 9 Nov, waiting for the user to confirm
**Cause and fix (HANDOFF 4.10, trap 14):** `WhyStockRow` passed `min: -1 << 31`, which is +2147483648 on the web, so the stepper refused every +. Now `min: widget.min - 1`. Checked in headless Chrome (`#/morning`: 0 to 1 after one tap). **Left to do:** the user confirms on their screen ("What did you make today?" and Add product's "How many do you have now?"); then delete this task. The history below is kept until then.

#### Before the fix
The user says "+" does nothing in the web app (the "Your list" screen at `/#/morning`, and the add-product count). Widget tests of that exact situation pass; the logic is `WhyStockRow` (`stock_widgets.dart`) over `SxStepper` (`design/widgets/sx_stepper.dart`). A headless-Chrome run (8 Nov) found the buttons (40x44 px) and taps do reach the app, but the count could not be read.
**Done on 9 Nov:** step (2): the count is one `Semantics` node ("Count of Brownie", value "3", live region) and a widget test taps + and − and reads it. The user was asked for the console output after restarting the web app on the new build; no answer yet.
**Do:** (1) ask the user to press F12, tap "+" once, and paste any red console text; also ask whether the number changes, shakes, or shows a red message, and to try without the phone-emulation toolbar. (2) Done (above). (3) Run the headless driver against a web build of the new code and compare the "Count of ..." value before and after a real mouse tap (CDP `Input.dispatchMouseEvent` pressed and released at the "More of ..." node's centre, HANDOFF trap 8). The 9 Nov driver script lived in that session's scratchpad, not the repo. The web app must be served from an origin in `WEB_APP_ORIGINS` (only `http://localhost:8080` by default). (4) If it reproduces, bisect by swapping `SxPressable` for a plain `GestureDetector`, then look at `SxFadeUp`, `SxScrollList` and `HapticFeedback` on web.
**Done:** a regression test, and the user confirms on their screen.

### T5. Demo readiness (this decides the score)
- **Run it end to end once, by a human, with the user watching**, in both modes: simulator (Accept, Reject, new link, cooldown, cancel) and real PayPal (log in once as the sandbox buyer in Chrome on this laptop; the return address is `http://localhost:8000`, so the buyer must approve on this laptop). Note anything that looks wrong; nobody has seen the new screens.
- **Demo data:** a seed command (`python -m uv run python -m app.cli seed-demo ...`, not built) for a bakery and a **dress shop** (a second merchant with `shop_type=dress_shop`, products with sizes and colours, a few chats and orders) so the dashboard is not empty. The app signs in one dev token at a time (`issue-token --minutes 1440`).
- **README for judges:** how to run it from scratch (database, `.env` from `.env.example`, API, web app) with both payment modes. The simulator means a judge can test payments without a PayPal account; the real sandbox path must still be shown, because PayPal has to be central.
- **Video script, under 3 minutes:** the owner sets stock (bakery); a customer orders in the simulator chat; the PayPal link; paying as the sandbox buyer; the paid message; a rejected payment with the new-link button and the cooldown; the dress-shop add-product form with sizes and no shelf life; a mention of the cancel and the fixed messages. It must show the app running on its device.
- **Hosting:** decide laptop-only versus Render. The hackathon gives **$50 of Render credits** (`https://credits-portal-mmdm.onrender.com/claim/paypal-ai-hackathon`; billed at month end). `render.yaml` and the Dockerfile exist but were never run end to end. A deploy needs an https `PUBLIC_BASE_URL`, real secrets in the host's environment, a separate worker, `FORWARDED_ALLOW_IPS`, migrations applied by hand (`supabase db push`), and PayPal webhooks registered for the new address (webhooks cannot reach this laptop).
- **Making the repo public:** scan the history for secrets before it goes public (`git log -p` for keys, tokens, the PayPal client secret). `backend/.env` and `paypal-certificate.txt` are gitignored (the certificate holds a public certificate, no private key). The user said earlier that LLM, PayPal and Instagram secrets were pasted into a chat once: **rotate them before going public.**

### T6. Gaps found by the UI-vs-backend audit (HANDOFF "Still open", item 4)
Pick by demo value. Cheap and visible: the one-day (pre-order) item cannot be edited in the app (backend `PATCH /v1/products` already accepts `available_on` and `order_by_date`); "Remove product" has no backend (`is_active` on the patch); "Same as yesterday" needs a small backend endpoint plus the app button; paging for the customers, insights and orders lists. Larger, probably skip and keep the honest "not active yet" labels: sending a merchant message from a chat, automations, refunds for UPI or cash, a read and delete list for saved rules.

### T7. Native-speaker review
Tamil and Hindi wording needs a native speaker (the user, or someone they ask): the templates `payment_link` (charge line), `payment_declined`, `payment_retry_button`, `payment_retry_wait`, `payment_gave_up`, `event_payment_received`, `event_hold_expired`, `owner_answer_relay`, and the shop-type labels and notes in `shop_types.yaml`.

### T8. Commit hygiene (only when the user says)
Show the diff first. A sensible split: (1) payments: fx, retries, simulator, migration; (2) agent: order references, playbook, fallbacks, templates, prompts CHANGELOG; (3) shop types backend and stock-type fixes; (4) Flutter shop-type form and onboarding; (5) audit fixes; (6) 9 Nov agent work (`affirmation.py`, `context.py` routing, `base@4`, playbooks, `render_profile`, their tests and the prompts CHANGELOG rows); (7) 9 Nov Flutter (onboarding and Settings talk step, `SxStepper` semantics, tests); (8) docs and evals. Never push. Open a pull request only when asked. Note `commands.md` has a block appended at the end that looks like a pasted chat reply ("To run it ..."): it is the user's edit, so ask whether to tidy it.

## 4. Decisions waiting on the user

1. Real PayPal for the demo: decided 9 Nov (the user wants the real sandbox, not the mock page). The dev API runs with `PAYMENT_PROVIDER=paypal`. Still open: delete the simulator code, or keep it off by default for judges without a PayPal account (recommended: keep). A real webhook needs a public https address (T5 hosting).
2. Host on Render with the credits, or demo from the laptop?
3. The words that count as a strong confirmation: done on 9 Nov with the proposed list (confirm, place the order, book it, go ahead, confirm pannunga, order podunga, order kar do, book karo, and the Tamil / Hindi scripts: `affirmation._STRONG`). The user may want to add or remove some.
4. A second demo merchant for the dress shop, or switch the one shop's type during the video?
5. Rotate the secrets now.
6. When to commit, and whether to open a pull request.

## 5. How to check everything

From `backend/` (Git Bash): `python -m uv run ruff check . && python -m uv run ruff format --check . && python -m uv run basedpyright` then `python -m uv run pytest -q --ignore=tests/integration/test_paypal_sandbox.py` (about 6 minutes; run it in the background or split it, a foreground command times out at 10 minutes). The real sandbox: `REQUIRE_PAYPAL_SANDBOX_TESTS=1 python -m uv run pytest tests/integration/test_paypal_sandbox.py`.
Flutter, from `D:\Android\cache\tmp\sellix_copy` after syncing: `cmd //c 'D:\Android\flutter-direct.cmd analyze' < /dev/null` and `... test`. The live contract test (the app's parsers against a real server): `LIVE_API_URL=http://localhost:<port> LIVE_TOKEN=<token> cmd //c 'D:\Android\flutter-direct.cmd test test/api/live_contract_test.dart' < /dev/null`.
Live evals: HANDOFF section 3, trap 7b (a throwaway database `sellix_evals`, a server on port 8001 with `PAYMENT_PROVIDER=simulator`, then `evals/run.py`). Drop the database afterwards and never leave tokens or database URLs in files.

## 6. How to work with this user and on this PC

- PowerShell is blocked: use the Bash tool. The user runs commands in Windows Command Prompt, so give them `cmd` syntax or a `.cmd` file (a script in `D:\Tools\sellix\` is the convention). Python goes through `python -m uv run`; scripts outside `backend/` need `PYTHONPATH=.`; pass `#/route` arguments with `MSYS_NO_PATHCONV=1`; print with `PYTHONIOENCODING=utf-8` (the ₹ sign crashes cp1252).
- Flutter only through `D:\Android\flutter-direct.cmd`, in the synced copy (the installed Dart is older than `pubspec.yaml` asks).
- The permission layer refused when Claude tried to stop a process it did not start; ask the user instead. Do not work around the company network control (Netskope); command-line clients cannot reach github.com, nodejs.org or devpost.com, but the WebFetch tool and Chrome can, and SSH to GitHub works.
- Write code containing backslashes with the Edit and Write tools, not Bash heredocs. Never print or write secrets (`backend/.env`).
- The user wants plain-language explanations, real test output, and honesty about what was not checked. They cannot share screenshots with an AI (company policy): never ask for one, never look at one; ask them to describe what they see.
- Parallel helpers worked well on 8 Nov: a helper for the Flutter side (with the exact API contract in the brief) and a read-only audit helper. Brief them with the files, the rules above, and what "done" means, then verify their work yourself (run `analyze`, `test`, the live contract test). The user allows using smaller models for light reading and a stronger one for hard tasks.

## 7. How to keep this

When a task here is done, delete it from section 3 and record what changed in HANDOFF section 4 (what, where, why, how it was checked, the test counts). Update the "Still open" list in HANDOFF section 7. Update the dates. Keep the memory notes (`MEMORY.md`) pointing at this file and HANDOFF. Never put secrets in either file.
