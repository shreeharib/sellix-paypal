# sellix: final plan to a production-grade agent

> **For the sellix team and any coding agent working on sellix · 28 Oct 2026.** This is the single plan for finishing the agent. It ties together:
> - `agent-improvement-plan.md`: what was wrong with the first agent (problems B1–B9) and the phase 1 fixes.
> - `agent-phase-2.md`: the design of the new harness (tools, prompts, memory, outbox, window, payments, guardrails). **That document is the spec; this one is the order of work and the definition of done.**
> - The phase 1 code review (27 Oct) and a check of `main` (28 Oct).
>
> When this plan and `agent-phase-2.md` disagree on *what to build*, the phase 2 doc wins. When they disagree on *order or priority*, this plan wins.

## Contents
- [1. Where we are](#1-where-we-are)
- [2. Decisions](#2-decisions)
- [3. What "unbreakable" means for sellix](#3-what-unbreakable-means-for-sellix)
- [4. Invariants: the rules code must enforce](#4-invariants-the-rules-code-must-enforce)
- [5. The stages](#5-the-stages)
- [6. Beyond phase 2: what the other plans don't cover](#6-beyond-phase-2-what-the-other-plans-dont-cover)
- [7. Testing strategy](#7-testing-strategy)
- [8. Timeline and the hackathon cut line](#8-timeline-and-the-hackathon-cut-line)
- [9. How we work](#9-how-we-work)
- [10. Risks](#10-risks)

---

## 1. Where we are

### 1.1 Status of the earlier plans

| Item | State on 28 Oct |
|---|---|
| Phase 1 tasks 1.1–1.6 (`agent-improvement-plan.md`) | Built on branch `agent-phase-1`, 175 tests green, **not merged into `main`** |
| Phase 1 task 1.7 (evals and simulator) | Partly: eval runner + 25 single-message cases; no multi-turn tests, simulator or CI gate |
| `agent-phase-1` vs `main` | `main` is 30 commits ahead (enterprise schema, payments refactor, module-boundary tests). A trial merge **conflicts in 8 files**: `.gitignore`, `catalog/models.py`, `catalog/service.py`, `escalations/service.py`, `inventory/service.py`, `orders/models.py`, `orders/service.py`, `tests/integration/test_order_turn.py` |
| Phase 2 (`agent-phase-2.md`) | Designed, not started |

### 1.2 Open defects (found by review and confirmed)

| # | Severity | Defect | Where | Evidence |
|---|---|---|---|---|
| D1 | **Critical** | **Any signed-in merchant can refund another shop's order.** The refund endpoint authenticates the shop but never passes its id; `payments.refund_order` looks the order up without `merchant_id` | `main`: `api/v1/orders.py` (`refund_order`), `payments/service.py` (`refund_order`) | Code reading, 28 Oct |
| D2 | **Critical** | **An order can be placed from a quote the customer never saw.** Any sent agent message after a quote, including the "let me check" holding message, counts as showing it | `agent-phase-1`: `conversations/actions.py` (`_customer_answered`) | Reproduced with an integration test: order #1001 (₹120) placed after the customer saw only the holding message |
| D3 | High | **Quotes never expire.** A quote can be confirmed days later with its old "today evening" time | `agent-phase-1`: `orders/service.py` (`place_quote`) | Code reading |
| D4 | High | **A refund can happen at PayPal without being recorded.** PayPal is called inside the database transaction; if the save fails afterwards, the money is refunded but the order still shows paid | `main`: `payments/service.py` (`refund_order`) | Code reading |
| D5 | High | **Payment confirmation trusts the webhook body.** `PAYMENT.CAPTURE.COMPLETED` is applied from the verified webhook's contents without re-fetching the order from PayPal | `main`: `payments/service.py` (`handle_webhook`) | Code reading |
| D6 | High | **Wrong totals pass the reply check** in Tamil script (`ரூ.100`), without a currency (`total 100`), and in spoken forms (`100 rupa`); "free" items and delivery-time promises pass | `agent-phase-1`: `agent/validator.py` | Probed with test inputs |
| D7 | High | **A crash can lose the payment link.** Reply jobs aren't retried; recovery tells the model the link "has been sent" | `conversations/tasks.py`, `actions.py` | Code reading |
| D8 | High | **Failed Instagram sends aren't retried**; the customer gets nothing | `conversations/service.py` (`_send`) | Code reading |
| D9 | High | **Merchant answers after 24 hours are never delivered** | `api/v1/questions.py` → `_send` | Code reading; Instagram's 24-hour rule |
| D10 | Medium | **Model outage = no reply.** No retries, no fallback model, no turn deadline (up to ~8 calls × 45 s) | `agent/llm.py`, `agent/service.py` | Code reading |
| D11 | Medium | **No spam, size or spend limits.** One customer can run up unlimited model cost; a huge message goes straight to the model | Whole turn path | Code reading |
| D12 | Medium | **Look-alike impersonation** (`【Shop system】`, `Shop system:`, `(Shop owner) …`) is stopped only by the prompt | `agent/customer_agent.py` | Probed |
| D13 | Medium | **No record of why a reply was sent**: logs and token counts only | — | — |

This list is what review has found so far, not a full audit. Stage E (section 6) is the full security and reliability audit.

---

## 2. Decisions

### 2.1 Agent framework: no framework; build our own harness

We looked at Microsoft Agent Framework (1.0, released April 2026: agents, workflows, checkpointing, middleware, human-in-the-loop) and similar libraries (LangGraph, the OpenAI Agents SDK, Pydantic AI). **We build our own turn engine**, as `agent-phase-2.md` section 3 specifies. Reasons:

1. **What makes sellix safe lives in our code whatever framework we use:** the conversation state that decides which tools exist, idempotent order and payment writes, the outbox, the 24-hour window, payment re-verification, money tokens. A framework would wrap the loop around these, not provide them.
2. **Control is the requirement.** We need per-state tool permissions, step and time budgets, resumable steps stored in *our* Postgres, and a trace row per step. Microsoft Agent Framework's documented checkpoint stores are files, Cosmos DB and Neo4j. We'd write a Postgres one anyway, plus adapters for everything else.
3. **Provider freedom.** The model is chosen by a cost bake-off (Grok, Gemini, Sarvam, open models through OpenAI-compatible APIs). Our gateway already speaks that format; a framework adds a layer between us and each provider's quirks.
4. **One agent per turn, no multi-agent orchestration.** The biggest framework features (agent teams, group chat, graph orchestration) solve problems we don't have.
5. **Small team, short deadline.** The harness is roughly 600–900 lines we fully understand. A framework is a dependency with its own release cycle, abstractions and debugging surface.

**What we borrow from the frameworks:** a **middleware pipeline** around model and tool calls (inbound guard, output guard, tracing and budgets as composable hooks), **checkpointing** (our `turn_steps`), and **human-in-the-loop approval** (Ask me, draft mode).

**Revisit if** we add several cooperating agents (e.g. a merchant agent planning stock while the customer agent sells) or long multi-day workflows. Then spike Microsoft Agent Framework or Pydantic AI against the harness, keeping our tools and invariants unchanged.

### 2.2 Durable execution: procrastinate + outbox + resumable steps, not Temporal

As in `agent-phase-2.md` section 13.4: no second system to run or pay for. Every step is idempotent, and state lives in Postgres.

### 2.3 Rollout behind a flag

`AGENT_ENGINE=v1|v2` per shop, then shadow → draft → autopilot (`agent-phase-2.md` section 19).

---

## 3. What "unbreakable" means for sellix

No software is bug-free, so "unbreakable" has to mean measurable bars that stop a release when missed. The final product is done when **all** of these hold:

| Area | Bar |
|---|---|
| Money and stock | Every invariant in section 4 is enforced by code or the database **and** has an automated test. Zero known violations. |
| Security | Zero open critical or high findings. Every `/v1` endpoint covered by the authorization test matrix (section 6.1). Secrets scan and dependency audit clean. |
| Agent quality | Live evals: order extraction ≥ 95%; reply quality ≥ 4/5 by native-speaker rating; valid tool calls ≥ 99%; adversarial set: **100% of cases send no unsafe content** (no raw amounts, links, promises, or acting on fake system text). |
| Reliability | Chaos suite passes (section 7.3): no lost message, no duplicate order or link, no unanswered customer after any single failure. |
| Latency | p95 turn time ≤ 8 s with the chosen model; fallback (holding message) rate ≤ 3% of turns. |
| Cost | Measured AI cost per order within the product plan's target (₹0.3–0.7). |
| Operations | Alerts and runbooks exist for every alert in `agent-phase-2.md` section 16; a database restore drill has succeeded. |

---

## 4. Invariants: the rules code must enforce

Each invariant names where it's enforced and the test that proves it. A PR that weakens one needs the owner's review.

| # | Invariant | Enforced by | Proven by |
|---|---|---|---|
| I1 | An order exists only from a quote whose card was **delivered**, confirmed by a **later** customer tap or affirmative message, before the quote **expired** | `confirm_order` tool + `quotes.shown_message_id` + `expires_at` | Unseen-quote, "no" reply, expired-quote and Confirm-tap tests |
| I2 | Available stock never goes below zero; two customers can't hold the last item | Conditional `UPDATE` + database check constraint | Race test (exists), plus a load test |
| I3 | One PayPal order per sellix order; one capture per payment; one refund per refund request | Request ids (exist) + unique constraints | Replay and double-click tests |
| I4 | An order becomes `paid` only after code re-fetches it from the provider and amount, currency, `custom_id` (and payee) match | `payments.verify_and_record` | Forged, `PENDING`, wrong-amount and wrong-order webhook tests |
| I5 | Refunds and manual "paid" are performed only by an authenticated merchant **of that order's shop**, recorded in `order_events`, never by the agent | `merchant_id` on every lookup; no agent tool | Cross-shop refund test (D1), agent tool-list test |
| I6 | Every outbound message is sent **at most once**, and **at least once** unless permanently undeliverable | Outbox with idempotency keys and retries | Outbox chaos tests |
| I7 | Nothing is sent outside Instagram's window except a human-written reply with the Human Agent tag | `window.py` checked by the outbox | Window tests (inside, 24 h–7 d, beyond 7 d) |
| I8 | No amount, link or promise reaches a customer unless code produced it | Money tokens + output guardrails | Adversarial output set |
| I9 | Customer text never enters a system prompt and can't produce a system event | Context builder; events as tool results | Injection suite (every bracket and Unicode style) |
| I10 | Every shop's data is invisible to every other shop | `merchant_id` on every query, row-level security, composite keys (schema doc) | Tenancy test matrix + architectural tests (exist on `main`) |
| I11 | Health claims only from stored product fields | Output guardrail + `get_product_details` | Allergen eval cases |
| I12 | A model or provider failure never leaves a customer without a reply | Engine budgets + holding template | Model-down chaos test |

---

## 5. The stages

Each stage ends with an **exit gate**. Don't start the next stage's risky parts before the gate passes. Task numbers `2.x` refer to `agent-phase-2.md` section 20.

### Stage A: Stabilise (start now)

Goal: one branch, no known critical defects.

- [ ] **A1 Fix D1 (cross-shop refund)** on `main` first, as a hotfix PR: pass `shop.merchant_id` through `refund_order` and require it in `orders.get_order` for every merchant-facing call. Add a test where shop B refunds shop A's order (must be 404).
- [ ] **A2 Fix D4 (refund recording):** create the refund record as `pending` and commit, call PayPal (request id exists), then mark `completed` from the response or the `PAYMENT.CAPTURE.REFUNDED` webhook. A reconcile job settles stuck `pending` refunds.
- [ ] **A3 Merge `main` into `agent-phase-1`** and resolve the 8 conflicts (section 1.1). Re-run `just check`; fix the phase 1 migrations so they apply on top of the enterprise schema.
- [ ] **A4 Fix D2 and D3:** a quote counts as shown only through the message that displayed it (store `shown_message_id` on the quote when that reply is sent; holding and fallback messages never set it); add `expires_at` and refuse expired quotes. Keep the probe test as a permanent regression test.
- [ ] **A5 Fix D5:** re-fetch the PayPal order before marking paid (`agent-phase-2.md` section 14, item 1).
- [ ] **A6 Merge `agent-phase-1` into `main`.**

**Exit gate:** `main` contains phase 1; D1–D5 fixed with tests; CI green.

### Stage B: Harness foundations

Goal: the pieces the new engine stands on, each useful immediately with the current agent.

- [ ] **B1 Prompt store** (2.1)
- [ ] **B2 Outbox** (2.2): fixes D7 (with B5) and D8
- [ ] **B3 24-hour window handling** (2.3): fixes D9
- [ ] **B4 LLM gateway v2**: tool calling, JSON fallback, retries, fallback chain, circuit breaker (2.4). Fixes D10.
- [ ] **B5 Resumable turns and tracing tables** (part of 2.6): `agent_turns`, `turn_steps`, retry strategy on reply jobs. Fixes D13.
- [ ] **B6 Inbound protection** (2.10): fixes D11

B1–B4 can run in parallel (different owners); B5 after B4.

**Exit gate:** chaos tests for Instagram 5xx, a model outage and a worker crash mid-turn pass on the **current** agent.

### Stage C: The new agent core

Goal: v2 engine with tools handles the standard order end to end.

- [ ] **C1 Tool registry + first tools** (2.5)
- [ ] **C2 Turn engine + context builder + events as tool results** (2.6): fixes D12 for good
- [ ] **C3 Output guardrails v2 with money tokens** (2.7): fixes D6
- [ ] **C4 Quote cards and Confirm taps** (2.8)
- [ ] **C5 Simulator** (part of 2.15): the web chat through the same pipeline, needed for demos and end-to-end tests
- [ ] **C6 Multi-turn scripted scenarios** (section 7.1) running on v2 in CI

**Exit gate:** scenarios 4.3 (standard order) and 4.6 (unsure → Ask me) from the product plan pass on v2 through the simulator and on the real test Instagram account; invariants I1, I6, I8, I9, I12 proven.

### Stage D: Depth

Goal: everything else the phase 2 spec defines.

- [ ] **D-1 Payments hardening, remaining items** (2.11)
- [ ] **D-2 Memory** (2.9)
- [ ] **D-3 Stories, images, posts** (2.12)
- [ ] **D-4 Remaining tools** (2.13)
- [ ] **D-5 Playbooks** (2.14)
- [ ] **D-6 Evals v2 and CI gate** (2.15): 50+ real chats, adversarial set, nightly run

**Exit gate:** all of section 3's agent-quality bars met; invariants I2–I5, I7, I10, I11 proven.

### Stage E: Beyond phase 2

See section 6. Runs alongside Stage D where owners are free; its security items must finish before any real merchant uses sellix.

### Stage F: Prove and launch

- [ ] **F1 Shadow mode** on the team's shop for a week; review traces daily (2.16).
- [ ] **F2 Draft mode** with the first design-partner merchants.
- [ ] **F3 Autopilot per message type** once each type's measured accuracy passes.
- [ ] **F4 Meta App Review** (Advanced Access, Human Agent tag) and PayPal partner onboarding for shops' own accounts.

**Exit gate:** every bar in section 3 holds. That's the final product.

---

## 6. Beyond phase 2: what the other plans don't cover

A robust agent inside an insecure or fragile app is still a fragile product. These items close that gap.

### 6.1 Security audit

- [ ] **Threat model** (one page): assets (money, customer data, Instagram tokens, merchant accounts), attackers (malicious customer, another merchant, outsider with a stolen token, compromised dependency), entry points (webhooks, `/v1` API, PayPal return page, CLI).
- [ ] **Authorization test matrix:** for every `/v1` endpoint, a test that shop B gets 404 on shop A's resources, and an unauthenticated call gets 401. D1 shows this is needed.
- [ ] **Webhook hardening:** signature checks (exist), replay window on timestamps where the provider sends one, payload size limit, rejection of unknown accounts.
- [ ] **Auth and sessions:** rate-limit sign-in and token refresh; refresh-token reuse detection (exists per ADR 0004, add a test); re-authentication before refunds and payout changes.
- [ ] **API rate limits** per shop and per IP on the `/v1` API and public pages.
- [ ] **Dependency and secret hygiene:** `pip-audit` and Flutter `pub outdated` in CI; secret scanning on every PR (dev plan `secrets-scan.yml`); full-history scan before each release; key rotation runbook (Fernet keys, PayPal, Meta).
- [ ] **Logs:** redaction processor for tokens, payment links, phone numbers and addresses; no raw webhook payloads in production (`LOG_WEBHOOK_PAYLOADS` off and enforced).
- [ ] **External review:** one independent security review before real merchants handle money through sellix.

### 6.2 Data protection (India's DPDP Act)

- [ ] Customer privacy notice and the automation disclosure ("I'm the shop's assistant").
- [ ] Consent record for storing customer memory.
- [ ] Deletion on request: an operator command that deletes a customer's messages, memories and summaries across one shop (orders keep what accounting needs).
- [ ] Retention jobs: drop message partitions after 12 months; expire memories.
- [ ] Data export for a merchant leaving sellix.

### 6.3 Reliability and operations

- [ ] **Load test:** 100 shops, each with bursts of 20 customers messaging at once; the queue, database pool and model gateway hold p95 ≤ 8 s.
- [ ] **Chaos suite** (section 7.3) in CI or a nightly job.
- [ ] **Dead letters:** webhook events and outbox rows that exhaust retries go to a visible "needs attention" list with an alert, not silent `pending` rows.
- [ ] **Error tracking** (e.g. Sentry) for API, worker and app; release tags.
- [ ] **Dashboards and alerts** from `agent-phase-2.md` section 16, plus queue depth and oldest-job age.
- [ ] **Backups:** daily automated backups and a tested restore drill.
- [ ] **Runbooks:** model provider down, Instagram API errors, PayPal errors, token expiry storm, a shop over budget, a stuck queue.
- [ ] **Health checks** that cover the database, the queue and the outbox backlog, not just "process is up".

### 6.4 Merchant app (needed for the agent loop to work)

- [ ] Push notifications (dev checklist section 7), including the window countdown push.
- [ ] Ask me: countdown, "pending delivery" state, "Always answer this way".
- [ ] Chats: view and delete customer memory; hand back to agent; draft-mode approvals.
- [ ] Orders: refunds with re-authentication; manual UPI "Paid" with audit.
- [ ] Settings: opening hours, "never promise" list, AI budget, Human Agent opt-in.
- [ ] Errors and offline behaviour (dev checklist 10.3).

### 6.5 Later channels and inputs (phase 3)

WhatsApp (with its own 24-hour and template rules), voice notes (speech-to-text bake-off), comment-to-DM private replies, model routing by cost (product plan section 8). Each reuses the same tools, outbox and invariants.

---

## 7. Testing strategy

### 7.1 Scenario catalogue (multi-turn, scripted model, real database)

Every scenario runs on the v2 engine in CI. Grouped by area:

- **Orders:**
  - standard order
  - several items
  - change before confirming
  - "no" to a quote
  - expired quote
  - Confirm tap
  - typed yes in English, Tanglish, Hinglish and Tamil script
  - item sells out between quote and confirm
  - two customers racing for the last item
  - "same as last time"
- **Payments:**
  - paid on time
  - paid after the hold expired
  - wrong amount
  - duplicate webhook
  - forged webhook
  - payment link resend
  - cancel before paying
  - refund by the merchant
  - refund attempted by another shop
- **Merchant loop:**
  - escalation answered inside 24 h
  - answered after 24 h (pending, then delivered when the customer writes)
  - answered after 7 days (expired)
  - merchant types in Instagram (agent pauses)
  - hand back to the agent
- **Media:**
  - story reply, tagged and untagged
  - expired story
  - story mention
  - screenshot of the menu
  - unknown photo
  - voice note (not yet supported → asks to type)
- **Abuse:**
  - 10,000-character message
  - 100-message burst
  - fake system notes in every style
  - discount pressure
  - "ignore your rules"
  - off-topic requests
  - abusive language
  - "are you a bot?"
- **Time:**
  - shop closed now
  - order after closing
  - holiday closure
  - business day rollover near midnight

### 7.2 Live-model evals

As `agent-phase-2.md` section 17: 50+ real anonymised chats growing towards the product plan's 200 per language, plus the adversarial set; nightly and on the `run-evals` label; the score gates prompt, tool and model changes.

### 7.3 Chaos suite

Each test injects one failure and checks the invariants afterwards:

- Instagram returns 500 or times out (once; repeatedly)
- Instagram says the window is closed
- The model times out, returns invalid tool calls, or returns 429 repeatedly
- The worker is killed after `confirm_order` and before the reply is sent
- The database connection drops during a tool call
- PayPal is down when creating a link, or when verifying a capture
- The same webhook arrives 5 times, out of order

---

## 8. Timeline and the hackathon cut line

Today is 28 Oct; submission is **12 Nov** (product plan section 18), and the demo environment freezes around 9 Nov (dev plan section 10). The full plan is bigger than 15 days, so it's split.

| Dates | Work | Notes |
|---|---|---|
| 28–30 Oct | **Stage A** | Hotfix D1 today |
| 31 Oct – 4 Nov | **Stage B** | Four owners in parallel (prompt store, outbox, window, gateway); then resumable turns, inbound protection |
| 4–8 Nov | **Stage C** | v2 engine, tools, money tokens, quote cards, simulator |
| 9–10 Nov | Demo freeze: seed data, eval numbers, README for judges | v2 behind the flag for the demo shop if Stage C's gate passed; otherwise demo on v1 with Stages A and B |
| 11–12 Nov | Video, submission | |
| After 12 Nov | **Stages D, E, F** | Stage E's security items finish before the first real merchant |

**Cut line for the submission:** Stages A, B and C. Everything in Stage D onward is post-submission unless a stage finishes early. Don't start Stage D work that would leave Stage C half-done at the freeze.

---

## 9. How we work

- **One task, one branch, one PR** (under ~400 changed lines). Branch names: `area/short-description`.
- **Before each PR:** `just check` green; new or changed invariants have tests; prompt or tool changes include an eval result.
- **Migrations:** always a new file; never edit a merged one.
- **The flag:** v2 work merges continuously behind `AGENT_ENGINE`, so `main` always runs.
- **Definition of done for a task:** its "Done when" line works on the dev server with the team's real Instagram test account, not only in tests (dev checklist rule).
- **Every bug found in review or production** gets a regression test before its fix is merged.

---

## 10. Risks

| Risk | Mitigation |
|---|---|
| Stage C doesn't finish by the 9 Nov freeze | Cut line in section 8; demo v1 with Stages A–B fixes |
| Merge conflicts keep growing while branches diverge | Merge `main` into feature branches daily; land Stage A in the first 3 days |
| The chosen cheap model is weak at tool calling in code-mixed language | JSON fallback mode; bake-off includes a tool-calling score; fallback model chain |
| Meta doesn't grant the Human Agent tag | Pending-delivery path (`agent-phase-2.md` section 10.3) works without it |
| Instagram API facts differ from docs | Spikes in `agent-phase-2.md` section 21 before building on them |
| Review finds more critical issues in Stage E | Stage E runs in parallel with D, and its security items block launch, not the hackathon |
