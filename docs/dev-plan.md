# sellix: development plan

> **For the sellix team · 25 Oct 2026.** How we structure the code, split the work, and merge safely while building the Flutter app and the agent backend in parallel. The product itself is described in `product-plan.md`; this document is about *how we build it*.

## Contents
- [1. Principles](#1-principles)
- [2. What the hackathon rules mean for us](#2-what-the-hackathon-rules-mean-for-us)
- [3. System overview](#3-system-overview)
- [4. Repository structure](#4-repository-structure)
- [5. Backend (the agent app)](#5-backend-the-agent-app)
- [6. Flutter app](#6-flutter-app)
- [7. The contract between app and backend](#7-the-contract-between-app-and-backend)
- [8. Database and migrations](#8-database-and-migrations)
- [9. Developing without waiting on Meta](#9-developing-without-waiting-on-meta)
- [10. Environments and secrets](#10-environments-and-secrets)
- [11. Testing and CI](#11-testing-and-ci)
- [12. Git workflow](#12-git-workflow)
- [13. Team split](#13-team-split)
- [14. Milestones](#14-milestones)
- [15. Week-1 tasks](#15-week-1-tasks)
- [16. Team decisions](#16-team-decisions)

---

## 1. Principles

1. **One repo, two apps, clear owners.** A monorepo with the Flutter app and the Python backend side by side. Each folder has an owner, so most pull requests touch only one person's area.
2. **A modular monolith, not microservices.** One backend codebase, run as two processes (API and worker). Modules talk to each other only through their public service functions.
3. **Contract first.** The backend's API is described automatically as an OpenAPI spec, and the Flutter API client is generated from it. App and backend developers agree on an endpoint, merge a stub, and then work in parallel.
4. **Nobody waits on Meta.** A built-in **customer chat simulator** and recorded webhook payloads let everyone build and test without a live Instagram or WhatsApp connection.
5. **Small pull requests, merged daily.** Short-lived branches, CI on every PR, one review, squash merge.
6. **Production quality from day one.** Multi-tenant (every row has a `merchant_id`), tested, logged, no secrets in code. The hackathon build is the first slice of the real product.

---

## 2. What the hackathon rules mean for us

| Rule | What we do |
|---|---|
| "Must meaningfully use both PayPal and AI"; "PayPal integration is central" | **PayPal is the payment rail for the whole demo** (sandbox), and we use several PayPal capabilities, not just one link (table below). UPI appears as the next adapter behind the same payment interface. |
| Judging: "How thoroughly and skillfully does the project use the PayPal Developer Platform and AI tools?" | Deep PayPal use + a real multi-layer AI system (routing, code-mixed language, image understanding, escalations) |
| "Judges must be able to actually run or interact with a working build" | **Hosted demo on Render:** the customer chat simulator + a demo login to the merchant web app, with seeded data. An Instagram app in development mode only answers tester accounts, so judges can't DM our test shop; the simulator goes through the exact same agent pipeline. |
| Public repo with an open-source licence visible at the top | Develop in a private repo; scan for secrets and make it public before submission ([12](#12-git-workflow)). Licence: see [16](#16-team-decisions). |
| "Tools": identify the AI models and services used and how | A "Tools and models" section in the README, generated from our model config |
| Demo video under 3 minutes, on the device it was built for, no unlicensed music or trademarks | Android phone (merchant app) + Instagram DMs; royalty-free or no music; keep third-party logos incidental |
| New or existing projects, with meaningful progress during the hackathon | All work happens in the hackathon window; commit history shows it |

### PayPal capabilities we use

| sellix feature | PayPal capability | Notes |
|---|---|---|
| Payment link + QR in the chat | Invoicing API (payer link + QR code) or Orders API (approval link) | The customer agent's `create_payment` tool |
| "Paid" only when PayPal confirms (fake-screenshot protection) | Webhooks (e.g. invoice paid / payment capture completed), with signature verification | Drives `payment_pending → paid` and the stock update |
| Advance payment for custom cakes | Invoicing partial payments (minimum amount due) | After the merchant answers an escalation |
| Refunds | Refund API, triggered only after the merchant approves in the app | Merchant handles refunds; sellix executes them on approval |
| Merchant asks the AI about money ("How much came in through PayPal this week?") | Transaction search / reporting APIs, exposed as read-only tools to the merchant agent | Shows "PayPal + AI" beyond checkout |
| Agentic commerce | PayPal's agent tooling (Agent Toolkit / MCP server; check the current docs) to expose PayPal actions as agent tools, wrapped by our own rules (amounts always come from the database) | Targets "Best Use of Agentic Commerce" |
| Each merchant connects their own PayPal | Partner onboarding (Partner Referrals), sandbox only for the demo | Real-product requirement; demo if time allows |

**Spike in week 1:** sandbox business account set to India receiving from a sandbox buyer abroad. Confirm the currency behaviour (USD paid, INR settled?), partial payments and refunds before building on them.

### Prizes worth targeting

| Prize | Why we fit |
|---|---|
| 1st–3rd overall, Most Impactful, Best Demo Delivery | Real problem, real merchant, end-to-end working demo |
| Best Use of PayPal + AI | Payments are inside the AI conversation; the AI also answers money questions using PayPal data |
| Best Use of Agentic Commerce | An agent that sells, takes payment and escalates on its own |
| Best Use of Render | We host on Render anyway (API, worker, web app, simulator) |
| Best Use of AG Grid (1st: $5,000) | Optional: an AG Grid order book page embedded in the web app ([16](#16-team-decisions)) |

---

## 3. System overview

```
              ┌──────────────────────── Meta ────────────────────────┐
Customers ──► │ Instagram DMs / story replies     WhatsApp Business   │
              └───────────────┬──────────────────────────┬───────────┘
                              │ webhooks                 │
  Customer chat simulator ────┤ (web chat, same pipeline)│
                              ▼                          ▼
        ┌─────────────────────────── backend/ (Python) ───────────────────────────┐
        │  api process:    webhooks (Meta, PayPal) · REST /v1 for the app ·        │
        │                  simulator page                                          │
        │  worker process: message batching · agent turns · timers (hold expiry,   │
        │                  escalation reminders, morning reminder) · nightly insights│
        │  modules: channels · conversations · agent · catalog · inventory ·       │
        │           orders · payments · escalations · shop_profile · stories ·     │
        │           insights · notifications                                       │
        └───────┬──────────────────────────────┬──────────────────────┬────────────┘
                │ SQL                          │ LLM gateway          │ PayPal API
                ▼                              ▼                      ▼
        Postgres (Render or Neon;      Model providers         PayPal sandbox
        host still to decide)          (chosen by bake-off)
                │                  ▲ REST /v1 (signed-in merchant only)
                ▼                  │
        ┌──────────── app/ (Flutter: Android + web) ────────────┐
        │ onboarding · Today · Ask me · Orders · Chats ·        │ ◄── push (FCM)
        │ Insights · Catalog · Settings                          │
        └────────────────────────────────────────────────────────┘
```

---

## 4. Repository structure

```
sellix/
├── README.md                    # what it is, hosted demo link, video, judge test steps, tools and models
├── CONTRIBUTING.md              # the short version of the workflow rules
├── LICENSE                      # AGPL-3.0-only
├── justfile                     # common commands: just dev, just test, just gen-client, just seed
├── render.yaml                  # Render blueprint: api, worker, web app, (demo env)
├── .github/
│   ├── workflows/               # backend.yml · app.yml · evals.yml · secrets-scan.yml
│   ├── CODEOWNERS               # folder → owner, so the right person reviews
│   ├── pull_request_template.md
│   └── ISSUE_TEMPLATE/
├── docs/
│   ├── product-plan.md
│   ├── dev-plan.md              # (this file)
│   ├── meta-payloads.md         # what Instagram/WhatsApp actually send: story replies, echoes, media
│   └── adr/                     # one short file per architecture decision
├── backend/
│   ├── pyproject.toml           # managed with uv
│   ├── app/
│   │   ├── main.py              # FastAPI app (api process)
│   │   ├── worker.py            # job worker process
│   │   ├── core/                # config, db session, logging, auth, errors, money/time helpers
│   │   ├── api/v1/              # routers used by the Flutter app (thin; call module services)
│   │   ├── webhooks/            # meta.py, paypal.py: verify → store raw event → enqueue → 200
│   │   └── modules/
│   │       ├── channels/        # instagram/ · whatsapp/ · webchat/ → one IncomingMessage type; senders
│   │       ├── conversations/   # threads, messages, batching, agent on/off per chat
│   │       ├── agent/           # router · llm gateway · prompts/ · customer_agent · merchant_agent · vision · stt
│   │       ├── catalog/         # products, variants, aliases, images
│   │       ├── inventory/       # daily stock ledger, atomic holds
│   │       ├── orders/          # order state machine, order events
│   │       ├── payments/        # PaymentProvider interface · paypal/ · upi/ (later)
│   │       ├── escalations/     # Ask me cards, answers, saved rules
│   │       ├── shop_profile/    # onboarding answers → Markdown shop profile (versioned)
│   │       ├── stories/         # story registry, fingerprints
│   │       ├── insights/        # SQL metrics, nightly recommendations
│   │       └── notifications/   # FCM push, WhatsApp fallback alerts
│   ├── simulator/               # static customer chat page served at /simulator
│   └── tests/
│       ├── unit/ · integration/
│       └── fixtures/            # meta/*.json, paypal/*.json: real recorded payloads (anonymised)
├── app/                         # Flutter (Android + web)
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/                # theme and UI kit, routing, l10n, auth, api + realtime setup
│   │   └── features/
│   │       ├── onboarding/ · today/ · ask_me/ · orders/ · chats/
│   │       └── insights/ · catalog/ · settings/
│   ├── l10n/                    # app_en.arb, app_ta.arb
│   ├── packages/sellix_api/     # GENERATED from the backend's OpenAPI: never edit by hand
│   └── test/
├── supabase/
│   ├── migrations/              # SQL migrations, one new file per change
│   └── seed.sql                 # demo bakery: catalog, 6–8 weeks of orders, stories
└── evals/
    ├── datasets/                # anonymised code-mixed messages + expected results
    ├── images/                  # product and story images for the vision tests
    └── run.py                   # bake-off and regression runner; writes a score report
```

---

## 5. Backend (the agent app)

### Stack

| Need | Choice |
|---|---|
| Language and API | Python 3.12, FastAPI, Pydantic v2 |
| Database access | SQLAlchemy 2 (async) on psycopg 3, against Supabase Postgres. One driver for both the app and the job queue. |
| Background jobs and timers | procrastinate, a job queue stored in Postgres: no Redis to run or pay for. Retries, per-chat locks and periodic jobs ([ADR 0003](adr/0003-job-queue-and-webhook-inbox.md)) |
| LLM calls | Our own thin gateway (`agent/llm.py`) for any OpenAI-compatible API: provider-neutral; every call is logged in `ai_usage` for the cost meter |
| Secrets in the database | Channel access tokens are encrypted with Fernet keys kept outside the database (`TOKEN_ENCRYPTION_KEYS`, rotatable) |
| Operator tools | `python -m app.cli`: create merchants, load shop profiles and stock, print the Instagram connect link. Used until onboarding exists, then kept for support. |
| Agent framework | **None.** Code runs the state machine; each turn is one structured model call validated with Pydantic. Heavy agent frameworks would add complexity we don't need. |
| HTTP client, logging | httpx, structlog (JSON logs with merchant and conversation IDs) |
| Tooling | uv, ruff (lint + format), basedpyright (types; the same checker as VS Code's Pylance, installed from PyPI with no Node download), pytest |

### Module rules

1. Each module has the same shape: `models.py` (tables) · `schemas.py` (types other modules may use) · `service.py` (**the public interface**) · `tasks.py` (job entry points, if any) · `router.py` (endpoints, if any).
2. A module may use another module's `service.py`, `schemas.py` and `tasks.py`. It may read another module's tables through its `models.py` in a query (e.g. a join), but **every change goes through the owning module's service**. Other internal files are off limits. This keeps changes local and merge conflicts rare. (The `merchants` module holds accounts and the global agent switch.)
3. Shared vocabulary (order states, channel names, money and time helpers) lives in `core/` and changes only through a PR reviewed by its owner.
4. **Money is stored as integer minor units** (paise / cents) with a currency code. Never floats.
5. **Times are stored in UTC**, and shown in the merchant's time zone (IST). The "business day" follows the merchant's closing time.

### How a customer message flows

```
1. webhooks/meta.py     verify signature → save raw event (idempotent by event ID) → enqueue → return 200 fast
2. channels/instagram   parse → IncomingMessage {merchant, customer, text, media, reply_to_story, is_echo}
3. conversations        append message; if echo from the merchant → agent off for this chat;
                        if agent off → log only; else schedule a turn in ~3 s (batched, one per chat)
4. agent/router         layer 0 (taps, story registry, fingerprints) → stt / vision if needed → small model
5. agent/customer_agent build context (shop profile + relevant stock + order so far + last messages)
                        → one structured model call → validate with services (price, stock, date)
                        → actions: hold_stock / create_order / create_payment / ask_merchant
6. channels/*.send      reply in the customer's language
7. payments webhook     PayPal confirms → orders: paid → inventory: sold → notify merchant app
```

### Prompts are code

Prompts live as versioned text files in `agent/prompts/`, are reviewed in PRs like code, and any PR that changes a prompt or the model config must include an eval run result ([11](#11-testing-and-ci)).

---

## 6. Flutter app

| Need | Choice |
|---|---|
| Targets | Android (first) and web, from one codebase; iOS later |
| State | Riverpod 3 (plain providers, no code generation: one less build step) |
| Navigation | go_router: bottom navigation on phones, side rail on wide screens; each tab keeps its own stack |
| API | A typed client (`lib/core/api/`) over dio, mirroring `backend/app/api/v1/schemas.py` |
| Sign-in | "Continue with Instagram" via flutter_web_auth_2 with PKCE; sessions in flutter_secure_storage ([ADR 0004](adr/0004-sign-in-with-instagram.md)) |
| Live updates | Pull-to-refresh now; FCM "something changed" pushes later |
| Push | firebase_messaging (Firebase also for Crashlytics and web hosting) |
| Languages | flutter_localizations with ARB files in `lib/l10n/` (English, Tamil) |
| Charts | fl_chart (or the AG Grid page, if chosen) |
| Media | image_picker (stock photos), record (voice notes) |
| Lints | flutter_lints, enforced in CI |

**Folders.** `lib/core/` holds the API client, sign-in, router, theme and shared widgets; each screen lives in `lib/features/<feature>/` with its providers. Shared widgets, colours and spacing come from `lib/core/`, so screens built by different people look consistent.

**Builds:** the API address comes from `--dart-define=API_BASE_URL=...`. On this team's managed Windows laptops Flutter runs through the native launcher `D:\Android\flutter-direct.cmd` (see `app/README.md`).

---

## 7. The contract between app and backend

| Direction | How | Rule |
|---|---|---|
| App → backend | REST API under `/v1` with a 15-minute access token (refresh tokens rotate) | The app **never touches the database**; every query is scoped to the signed-in merchant's shop |
| Backend → phone (alerts) | FCM push (to come) | New question, paid order, low stock, morning reminder |

**Adding an endpoint, without blocking each other:**
1. A backend developer opens a small PR with the route and its request/response types in `app/api/v1/schemas.py`; the OpenAPI spec at `/openapi.json` updates itself.
2. The app developer adds the matching model and method in `lib/core/api/` and builds the screen.
3. If the hand-written client starts drifting from the spec, switch to generating it from `/openapi.json`.

---

## 8. Database and migrations

- **Postgres** (any host: Render or Neon for dev and production, decision pending). Migrations are plain SQL files in `supabase/migrations/` (the folder keeps its name until the host is decided; if Supabase isn't the host, it becomes `db/migrations/` with a `python -m app.cli migrate` command).
- **One migration per PR, never edit a merged migration**, always add a new one. Timestamped file names avoid most conflicts.
- Every business table has `merchant_id` and row-level security (harmless off Supabase, protective on it).
- Local development: Postgres in Docker (`just db-up`, `just db-reset`). The tests build their own database from the migrations.

---

## 9. Developing without waiting on Meta

| Tool | What it's for |
|---|---|
| **Customer chat simulator** (`/simulator`) | A web chat that behaves like a customer DM: text, images, "reply to story". Goes through the same pipeline as Instagram and WhatsApp. Used daily by developers, by end-to-end tests, and by judges. |
| **Recorded payloads** (`tests/fixtures/meta/`) | Real webhook payloads captured once from our test account (text, image, voice note, story reply, echo), anonymised. Tests replay them. |
| **Shared dev deployment** | The dev environment on Render receives the real Meta and PayPal webhooks, connected to our Instagram test account and the PayPal sandbox |
| **Tunnel for debugging real webhooks locally** | Point the Meta app's webhook URL at your laptop with a tunnel (cloudflared or ngrok) when needed. One person at a time; post in the team chat. |
| **Fake model for unit tests** | Deterministic responses, so unit tests are free and stable; real models are only used in eval runs |

### Week-1 spikes (findings go into `docs/meta-payloads.md` and fixtures)

| Spike | Steps | Answers |
|---|---|---|
| **Story replies** | Connect the test Instagram account; post a story; reply to it from a teammate's account; log the raw webhook | Which fields identify the story? Is there a media URL, and how long does it last? Do video stories, highlights and story mentions look different? |
| **Echo events** | Reply from the Instagram app (as the shop) to a customer chat; log what arrives | Does a copy of the merchant's own reply arrive? How do we tell it apart from messages sellix sent through the API? (Track the IDs of messages we send.) |
| **PayPal sandbox** | India business account + buyer abroad: invoice or order, partial payment, webhook, refund | Currency behaviour, webhook events, refund flow |
| **Model bake-off harness** | `evals/run.py` running the first 50 test messages against 2–3 models | The harness works; first cost and accuracy numbers |

---

## 10. Environments and secrets

| Environment | What | Used by |
|---|---|---|
| **local** | Supabase in Docker, backend, simulator, Flutter dev build | Each developer |
| **dev** | Render (api, worker, web app) + a Supabase dev project + the Meta test app + PayPal sandbox. Auto-deploys from `main`. | The team, every day |
| **demo** | A copy of dev with seeded data, frozen for judges from about 9 Nov | Judges, the video |
| **prod** | Created after the hackathon | Real merchants |

**Secrets:** `.env.example` is committed with every variable name and no values. Real values live in Render environment groups and a shared password manager. Each developer's model API key has a spending cap. Secret scanning runs in CI on every PR, and the full history is scanned again before the repo goes public.

---

## 11. Testing and CI

| Workflow | Runs | Checks |
|---|---|---|
| `backend.yml` | Every PR touching `backend/` or `supabase/` | ruff, basedpyright, pytest against a Postgres service (the tests build a fresh database from `supabase/migrations`, so a broken migration fails CI), and later: generated Dart client is up to date |
| `app.yml` | Every PR touching `app/` | `flutter analyze`, `flutter test`, web build |
| `evals.yml` | PRs touching `agent/prompts/` or model config, when the `run-evals` label is added (it costs money) | Runs the eval set; posts accuracy, language score and cost per order on the PR; fails if below the bar |
| `secrets-scan.yml` | Every PR | No keys or tokens committed |

**Must-have tests:** two customers racing for the last item (atomic holds); every order state transition; webhook replay with recorded payloads (Meta and PayPal, including duplicates); the full scenario 4.3 through the simulator against the dev environment.

---

## 12. Git workflow

| Rule | Detail |
|---|---|
| Branches | `main` is protected. Work on short-lived branches named `area/short-description`, e.g. `backend/inventory-holds`, `app/today-screen`. |
| Pull requests | Small (aim for under ~400 changed lines), one approval from the area owner (CODEOWNERS), CI green, **squash merge**, delete the branch |
| PR titles | Conventional style: `feat:`, `fix:`, `chore:`, `docs:`, so the history reads well for judges |
| PR template | What and why · plan section it implements (e.g. "4.3") · how it was tested · screenshots for UI |
| Keeping in sync | Pull `main` at least daily; rebase your branch before asking for review |
| Planning | GitHub Projects board: Backlog → This week → In progress → Review → Done. Each issue has acceptance criteria and an owner. |
| Rhythm | 15-minute check-in daily (a chat message is fine); integration demo on the dev environment every Monday, Wednesday and Friday using the simulator |
| Repo visibility | Private while building; scan the full history for secrets, add the licence and make it public by 10 Nov |

**Merge-conflict hotspots and how we avoid them:**

| Hotspot | Rule |
|---|---|
| Migrations | Always a new file; never edit a merged one |
| Generated Dart client | Never edit by hand; run `just gen-client` after pulling |
| Translation files (`.arb`) | Keys prefixed by feature (`today_…`, `orders_…`), kept in alphabetical order |
| Shared enums and order states (`core/`) | Changed only through a PR reviewed by the commerce owner (role 5) |
| Lock files (`uv.lock`, `pubspec.lock`) | Never hand-merge; regenerate |
| Prompts and model config | Owned by the AI role (role 2); changes need an eval result |

---

## 13. Team split

**The team is 4–5 people; roles aren't assigned yet.** Five roles are below, with the skills each one needs, so people can pick by strength. With **4 people**, roles 3 and 4 merge into one Flutter role (and the AG Grid page is dropped or moved to whoever finishes first). Once assigned, put the GitHub usernames in `.github/CODEOWNERS`.

| Role | Skills needed | Owns (CODEOWNERS) | Main deliverables |
|---|---|---|---|
| **1. Platform and channels** | Python, HTTP/webhooks, a little DevOps (GitHub Actions, Render) | `backend/app/webhooks`, `modules/channels`, `modules/conversations`, `modules/notifications`, `backend/simulator`, `.github/`, `render.yaml`, `justfile` | CI and environments; Meta app; Instagram then WhatsApp adapters; message batching; agent on/off and echoes; customer chat simulator; push notifications; story-reply and echo spikes |
| **2. AI** | Python, prompting, careful testing; ideally reads Tamil or Hindi | `modules/agent`, `modules/stories`, `evals/` | Model gateway and cost meter; router; customer agent turn; merchant agent (stock from voice, text and photos); story identification; speech-to-text; test set and bake-off |
| **3. App: daily screens** | Flutter / Dart | `app/` (everything not listed under role 4) | Create the Flutter project; UI kit; login; navigation; Today; Ask me; Orders; Chats; push handling; Tamil/English |
| **4. App: setup screens and web** | Flutter / Dart; JavaScript/TypeScript for the AG Grid page | `app/lib/features/onboarding`, `settings`, `catalog`, `insights` | Onboarding (skippable steps); Settings and shop profile forms; Catalog; Insights charts; web layout; the AG Grid page (if chosen) |
| **5. Commerce and data** | Python, SQL/Postgres, payment APIs | `backend/app/core`, `modules/catalog`, `inventory`, `orders`, `payments`, `escalations`, `shop_profile`, `insights`, `supabase/` | Data model and migrations; inventory ledger; order state machine; PayPal adapter (payments, partial payments, refunds, reporting); escalation backend; shop profile generator; insights SQL; demo data |

**Also pick one integration lead** (any role, often the person who knows the product best): reviews cross-area PRs, runs the Monday/Wednesday/Friday integration demos, owns the demo environment, the README for judges and the video.

Shared by everyone: README, the plan documents, the demo script.

---

## 14. Milestones

Dates match section 18 of the product plan.

| Milestone | Dates | Done when |
|---|---|---|
| **M0 Skeleton** | 25–26 Oct | Repo, CI and dev environment live; an Instagram DM and a story reply reach the dev server; schema v1 merged; stub `/v1` endpoints; Flutter app logs in and shows empty screens; spikes written up |
| **M1 First sale** | 27 Oct – 1 Nov | Scenario 4.3 works end to end on Instagram and in the simulator with a PayPal sandbox payment; atomic holds; bake-off done; the Today screen shows live stock |
| **M2 Merchant loop** | 2–5 Nov | Escalations with push and Ask me; story registry and replies; stock from photos; onboarding; agent on/off with echo detection; WhatsApp standard order |
| **M3 Depth and polish** | 6–8 Nov | Insights and recommendations; cost meter; PayPal advances and refunds; merchant asks the AI about PayPal income; edge cases from the product plan (section 14); optional AG Grid page |
| **M4 Prove it** | 9–10 Nov | Shadow test on real anonymised chats; accuracy and cost numbers; demo environment seeded; README with judge steps; repo public |
| **M5 Ship** | 11–12 Nov | Video uploaded, submission form complete, submitted a day early |

---

## 15. Week-1 tasks

Role numbers refer to [13](#13-team-split).

| # | Task | Role | Depends on | Status |
|---|---|---|---|---|
| 1 | Repo skeleton: structure, licence, README, CONTRIBUTING, justfile, CODEOWNERS template, PR and issue templates, CI workflows, backend skeleton with the Meta webhook endpoint and tests | 1 | — | ✅ Done locally; not yet pushed to GitHub |
| 2 | Supabase dev project + `supabase init`; Render dev service from `render.yaml` | 1 + 5 | 1 | 🟡 `render.yaml` drafted |
| 3 | Meta developer app; connect the team's Instagram account; point its webhook at dev `/webhooks/meta` (the endpoint exists) | 1 | 2 | ⬜ |
| 4 | Spike: story replies and echo events → `docs/meta-payloads.md` (template ready) + fixtures | 1 | 3 | ⬜ |
| 5 | Schema v1 migration: merchants, shop_profiles, channels, products, variants, daily_stock, stock_events, customers, conversations, messages, orders, order_items, order_events, payments, escalations, stories, ai_usage | 5 | 2 | ⬜ |
| 6 | Inventory ledger with atomic holds + the race test | 5 | 5 | ⬜ |
| 7 | Order state machine + order events | 5 | 5 | ⬜ |
| 8 | Spike: PayPal sandbox (India seller, buyer abroad, partial payment, webhook, refund) | 5 | — | ⬜ |
| 9 | Model gateway with cost logging + fake model for tests | 2 | 1 | ⬜ |
| 10 | Start the test set: export the Instagram account's DMs, anonymise, label the first 50 messages | 2 | — | ⬜ |
| 11 | Bake-off harness `evals/run.py` on the first 50 messages, 2–3 models | 2 | 9, 10 | ⬜ |
| 12 | Customer chat simulator page + webchat channel adapter | 1 | 2 | ⬜ |
| 13 | Stub `/v1` endpoints for Today, Orders, Ask me + generated Dart client | 5 + 1 | 5 | ⬜ |
| 14 | Create the Flutter project (`app/README.md`), login, navigation, UI kit, empty Today / Orders / Ask me screens | 3 | — (13 for real data) | ⬜ |
| 15 | Onboarding screens (all steps skippable) + `shop_profile` generator | 4 + 5 | 5 | ⬜ |

---

## 16. Team decisions

| Decision | Status |
|---|---|
| **Licence** | ✅ **AGPL-3.0-only**: `LICENSE` added; reasoning in `docs/adr/0002-licence-agpl.md` |
| **Team size** | ✅ 4–5 people |
| **Roles** | ⬜ Assign roles 1–5 ([13](#13-team-split)) and the integration lead; fill in `.github/CODEOWNERS` |
| **Code ownership** | ⬜ Several friends are contributing to a product you plan to commercialise. Agree in writing who owns the code (e.g. a future company) before the repo goes public, so it can be commercialised or relicensed later without chasing everyone's consent. Get advice if unsure. |
| **AG Grid page** | ⬜ See below. Suggestion: yes with 5 people (role 4); with 4, only if ahead of schedule by 6 Nov |
| **Name and app ID** | ⬜ Choose the final Android application ID before the first release. Check that "sellix" is free to use as a product name: an e-commerce platform called Sellix already exists. |
| **Model budget** | ⬜ Spending cap per developer key and for eval runs (eval runs only with the `run-evals` label) |
| **Meta and PayPal admin** | ⬜ One owner each for the Meta developer app and the PayPal developer account, with teammates added as developers |

### What the AG Grid page is

**AG Grid** is a JavaScript library, and one of the hackathon's sponsors, for Excel-like tables in a web page: sort, filter, search, group, edit cells, export, and it stays fast with thousands of rows.

**The AG Grid page** would be one screen in the merchant web app: an **order book** with every order in a single spreadsheet-like table. The merchant can filter by date, product, channel or status, group by product to see totals, and export to a spreadsheet. A second grid could let the merchant edit today's stock like a spreadsheet. It replaces the diary or Excel sheet many merchants keep today.

| | |
|---|---|
| **Why consider it** | AG Grid prizes: 1st $5,000, 2nd $2,000, 3rd $1,000 (three winners), and AG Grid's community manager is a judge. It also gives judges a strong view of the data. |
| **The catch** | AG Grid is JavaScript, so Flutter can't use it directly. It would be a small separate TypeScript page, shown inside the Flutter web app (embedded) and in a web view on the phone, calling the same `/v1` API. That's roughly 2–3 days for one person who knows JavaScript/TypeScript. |
| **Free or paid** | The Community edition is free (MIT licence). Some features (Excel export, row grouping, pivoting, built-in charts) are in the paid Enterprise edition. Check whether the hackathon gives out Enterprise keys; otherwise use Community features (sorting, filtering, editing, CSV export). |
