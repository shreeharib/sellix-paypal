# sellix: agent phase 2, a production harness

> **For the engineer or coding agent building phase 2 · 27 Oct 2026.** Read this whole document before writing code. Phase 1 (`agent-improvement-plan.md`) made the existing agent safer. Phase 2 **replaces the harness**: how a turn runs, how the model acts, where prompts live, how memory works, how messages are delivered, and how failures are survived. The model goes from "one prompt in, one JSON blob out" to **an agent that calls typed tools inside a harness that code controls**.
>
> Treat this as a rebuild of `backend/app/modules/agent/` and the turn loop in `backend/app/modules/conversations/`, not a patch. Keep everything that already works underneath it: the webhook inbox, the job queue, orders, inventory holds and payments.

## Contents
- [0. Before you start](#0-before-you-start)
- [1. What changes, in one table](#1-what-changes-in-one-table)
- [2. Rules that never bend](#2-rules-that-never-bend)
- [3. Architecture](#3-architecture)
- [4. Prompts live in files](#4-prompts-live-in-files)
- [5. Tools](#5-tools)
- [6. The turn engine](#6-the-turn-engine)
- [7. Conversation state](#7-conversation-state)
- [8. Memory](#8-memory)
- [9. Instagram: what the API can and can't do](#9-instagram-what-the-api-can-and-cant-do)
- [10. The 24-hour window and late answers](#10-the-24-hour-window-and-late-answers)
- [11. Stories, images, posts and media](#11-stories-images-posts-and-media)
- [12. Inbound protection: rate limits, size caps, budgets](#12-inbound-protection-rate-limits-size-caps-budgets)
- [13. Reliability: retries, outbox, durable execution](#13-reliability-retries-outbox-durable-execution)
- [14. Payments security](#14-payments-security)
- [15. Output guardrails](#15-output-guardrails)
- [16. Observability](#16-observability)
- [17. Evals and tests](#17-evals-and-tests)
- [18. Database changes](#18-database-changes)
- [19. Rollout](#19-rollout)
- [20. Work plan](#20-work-plan)
- [21. Facts to verify before building on them](#21-facts-to-verify-before-building-on-them)
- [Sources](#sources)

---

## 0. Before you start

1. **Merge `main` into `agent-phase-1` and resolve the conflicts** in `backend/app/modules/orders/models.py` and `orders/service.py` (Dakshna's PayPal invoicing and refunds touched the same files). Merge phase 1 into `main`. Branch `agent-phase-2` from `main`.
2. **Fix the phase 1 review findings first**, because phase 2 builds on the same order code:
   - **An order can be placed from a quote the customer never saw.** `_customer_answered` in `conversations/actions.py` counts any sent agent message after the quote, including the holding message sent when the quote reply fails the checks. Reproduced: the customer saw only "Shop-la check panni seekiram solren.", replied "ok thanks", and order #1001 (₹120) was placed. Add that scenario as a permanent regression test.
   - **Quotes never expire.** A quote can be placed days later with its old "today evening" time.
3. **Read** `CONTRIBUTING.md`, `docs/dev-plan.md` sections 5 and 11, ADR 0001 and 0003, and `docs/agent-improvement-plan.md`.
4. **Ground rules for the code:** small PRs (under ~400 lines), one new migration file per schema change (never edit a merged one), `just check` green, async throughout, every module's public interface in `service.py`.

---

## 1. What changes, in one table

| Area | Today (phase 1) | Phase 2 |
|---|---|---|
| How the model acts | Returns one JSON object with at most one `action` (`quote_order`, `place_order`); up to 3 steps | **Native tool calling** with ~18 typed tools; a turn ends when the model calls `send_reply` |
| Prompts | Python string constants in `customer_agent.py` | **Versioned files** in `agent/prompts/`: base prompt, playbooks, tool descriptions, customer-facing templates per language |
| Turn loop | A `for` loop in `conversations/service.py` | A **turn engine** with step and time budgets, tool permissions per state, a trace of every step, and resumable steps |
| System events | Text notes in the chat marked with a per-turn tag | **Tool results and structured events**; nothing a customer types can look like one |
| Money in replies | The model types prices; a regex checks them | **The model never types an amount.** It writes tokens like `[[price:c1]]` or `[[quote_total]]` and code fills them in |
| Confirming an order | The model judges "the customer agreed" | **A quote card sent by code, with Confirm / Change quick replies.** A tap is proof; a typed yes is checked by code |
| Memory | The last 20 messages + shop profile + today's stock | **Four memory types** (semantic, episodic, procedural, in-context), **per shop and per customer** |
| Delivery | `send_text` once; failure → escalation | **Outbox**: every outbound message is queued, retried, sent once, and checked against the 24-hour window |
| Late merchant answers | Fail silently after 24 hours | Handled: warning before the window closes, Human Agent tag where allowed, delivery when the customer writes again |
| Media | "[The customer sent: image]" | Story replies resolved to products, images described by a vision tool, posts shared from the catalog |
| Abuse and cost | None | Per-customer rate limits, message-size caps, per-shop daily AI budget |
| Model failures | One provider, no retry | Retries with backoff, a fallback model chain, per-turn deadline |
| Debugging | Logs | **Turn traces** in the database and a `replay-turn` command |

---

## 2. Rules that never bend

Every design choice below follows from these. If something you're building conflicts with one, stop and ask.

1. **Code decides money, stock, order state and payment status.** The model never computes, types or changes an amount.
2. **An order is paid only when PayPal (or the UPI gateway) confirms it**, re-checked by code against the provider's API. Never from a screenshot, a message or the model.
3. **Customer text is untrusted data.** It goes to the model only as the customer's message, length-capped and normalised. It can never change rules, prices or tools.
4. **Nothing reaches a customer unchecked.** Every outbound message passes the output checks, or is replaced by a fixed template.
5. **When unsure, the agent asks the merchant.** Guessing is a bug.
6. **Health answers (ingredients, allergens, eggless, Jain, sugar-free) come only from stored product data.**
7. **Every step is safe to retry.** Any job can crash and run again without a second order, a second payment link or a second message.
8. **Meta's rules are product requirements:** the 24-hour window, no storing story-mention media, automation disclosure when asked.

---

## 3. Architecture

```
 Instagram webhook ─► inbox (exists) ─► parse + store message (exists)
                                              │
                                              ▼
                          ┌──────── 1. Inbound gate ────────┐
                          │ normalise text, size caps,      │
                          │ per-customer rate limit, budget │
                          └───────────────┬─────────────────┘
                                          │ queued turn (procrastinate, per-chat lock, 3 s batch)
                                          ▼
 ┌──────────────────────────── 2. Turn engine ─────────────────────────────┐
 │  context builder ── memory (semantic, episodic, procedural, in-context)  │
 │        │                                                                 │
 │        ▼                                                                 │
 │  model call (tools offered = those allowed in this conversation state)   │
 │        │ tool calls                     ▲ tool results                   │
 │        ▼                                │                                │
 │  tool executor: validate args → check permission → run (idempotent)     │
 │        │                                                                 │
 │  ... until send_reply, or the step / time budget runs out → holding msg  │
 │  every step written to turn_steps (trace + resume)                       │
 └──────────────────────────────┬──────────────────────────────────────────┘
                                │ reply (tokens filled in by code)
                                ▼
                     3. Output guardrails ── fail → repair once → fixed template
                                │
                                ▼
                     4. Outbox ── window check ── send with retries ── status
                                │
                                ▼
                         Instagram Send API
```

**Module layout** (new or rewritten files under `backend/app/modules/`):

```
agent/
  service.py            public interface: run_turn(conversation_id), replay_turn(turn_id)
  engine.py             the turn loop: budgets, model calls, tool dispatch, resume
  context.py            builds the prompt from memory, state and history, within a token budget
  llm.py                gateway: tools, retries, fallback chain, timeouts, usage logging
  prompts/              see section 4 (files, not code)
  prompt_store.py       loads, validates and versions prompt files
  tools/
    registry.py         Tool base class, schemas, permissions per state, executor
    catalog.py          search_catalog, get_product_details, send_menu_image, share_post
    orders.py           update_order_draft, create_quote, confirm_order, cancel_order, get_order_status
    payments.py         resend_payment_link
    people.py           ask_shop_owner, hand_off_to_owner
    memory.py           remember_customer_fact, log_missed_demand
    media.py            lookup_story, describe_image, transcribe_voice (phase 3 stub)
    reply.py            send_reply (the only way a turn ends)
  guardrails/
    inbound.py          normalise, cap, rate-limit decisions
    output.py           money tokens, links, promises, language, length
  memory/
    semantic.py         shop knowledge
    episodic.py         customer memory and conversation summaries
    procedural.py       playbook selection, merchant rules
  tracing.py            turn and step records, replay
conversations/
  outbox.py             outbound queue, window checks, retries
  window.py             24-hour and Human Agent window logic
channels/
  instagram.py          + quick replies, media, MEDIA_SHARE, reactions, Human Agent tag, conversations API
```

**No agent framework.** Keep the harness in our own code, as the dev plan decided. Frameworks hide the loop, and the loop is exactly what we need to control: permissions, budgets, idempotency, tracing. The harness is a few hundred lines; the value is in the tools and rules.

---

## 4. Prompts live in files

No prompt text in Python. Code only loads and fills prompts.

```
backend/app/modules/agent/prompts/
  base.md                      identity, tone, language mirroring, hard rules, how to use tools
  playbooks/
    new_order.md
    custom_or_future_order.md
    story_or_photo.md
    payment_problem.md
    order_status.md
    product_question.md
    complaint.md
    small_talk.md
    abuse_or_off_topic.md
  tools/                       one short file per tool: when to use it, when not to
    search_catalog.md  ...
  templates/                   fixed customer-facing messages, sent by code, per language
    holding.yaml               en, ta, ta-en, hi, hi-en
    quote_card.yaml
    payment_link.yaml
    follow_up.yaml
    window_closed.yaml
    too_long.yaml
    rate_limited.yaml
  CHANGELOG.md                 what changed in each prompt version and the eval score
```

**File format:** Markdown with a small front-matter header.

```markdown
---
id: playbook.new_order
version: 3
applies_when: stage in [browsing, collecting_details, awaiting_confirmation]
---
# Taking an order
1. Find the items with search_catalog (or use the ids in the menu). ...
```

**Rules for the prompt store (`prompt_store.py`):**
- Load all files at startup, validate the front matter, fail startup on an error.
- Render with Jinja2 using `StrictUndefined` (a missing variable is an error, not an empty string). Only code-produced values go into templates. **Customer text is never rendered into a system prompt**; it's always a separate user message.
- Every turn records the `id@version` of each prompt it used (section 16).
- A PR that changes anything under `prompts/` must include an eval run (section 17), as `CONTRIBUTING.md` already requires.
- Keep `base.md` short and stable so providers can cache it. Playbooks are swapped per turn; templates are never sent to the model.

**Which playbook loads:** code picks one playbook per turn from the conversation state plus a cheap intent check (keywords, attachment types, story reply flag; a small classifier call only if those are ambiguous). The model can also call `load_playbook(name)` once per turn if the conversation clearly moved to another situation.

---

## 5. Tools

### 5.1 How tools work

- Each tool is a class with a **name**, a **Pydantic model for its arguments** (turned into the JSON schema sent to the model), a **description** loaded from `prompts/tools/<name>.md`, the **states it's allowed in**, whether it **writes**, and a `run()` method that calls module services.
- The model sees only the tools allowed in the current state (section 7). A call to any other tool returns an error result; it isn't run.
- **Tool results are JSON**, not prose: `{"ok": true, "data": {...}}` or `{"ok": false, "error": {"code": "...", "message": "...", "hint": "..."}}`. Errors are results the model can react to, never exceptions that kill the turn.
- **Write tools are idempotent.** Each call gets a key `turn_id:step:tool` stored in `turn_steps`. If the turn is retried after a crash, the stored result is returned instead of running the write again.
- **IDs, never names.** Items are referenced by the short ids code shows in the menu or returns from search (`c1`, `b7`). The fuzzy matcher from phase 1 lives inside `search_catalog`, not in the order tools.
- Write tools run one at a time. Read tools may run in parallel if the provider returns several calls.

### 5.2 The tools

| Tool | Writes? | Allowed in | Arguments | Returns / does |
|---|---|---|---|---|
| `search_catalog` | No | all except `handed_off` | `query`, `limit` (≤ 10) | Candidate items: id, name, variant, price token, available today, why it matched |
| `get_product_details` | No | same | `item_id` | Description, ingredients, allergens, sizes, options. **The only source for health answers.** Empty fields come back as `null`, and the model must then ask the owner |
| `get_customer_profile` | No | same | — | Episodic memory for this customer (section 8): name, language, saved address, usual order, past order count, open orders |
| `get_order_status` | No | same | `order_number` (optional) | This customer's orders only: number, status, total token, needed by |
| `lookup_story` | No | same | `story_ref` | Products the story shows, from the story registry (section 11); `unknown` if not tagged yet |
| `describe_image` | No | same | `attachment_id` | Vision model result: products seen and catalog matches with confidence. Runs at most once per attachment (cached result) |
| `send_menu_image` | Yes (outbound) | browsing, collecting_details | — | Queues today's menu photo (if the merchant uploaded one) in the outbox |
| `share_post` | Yes (outbound) | browsing, collecting_details | `item_id` | Queues the shop's own post for that product (`MEDIA_SHARE`) if one is linked |
| `update_order_draft` | Yes | browsing, collecting_details, awaiting_confirmation | `items[{item_id, quantity, options}]`, `fulfilment`, `delivery_address`, `needed_by`, `notes` | Saves the draft; returns what's still missing and any stock problems. Changing a draft in `awaiting_confirmation` supersedes the quote |
| `create_quote` | Yes | collecting_details | — | Prices the draft (code), saves a quote with an expiry, and **queues the quote card** (section 6.4). Returns the quote id and a summary with tokens, not raw amounts |
| `confirm_order` | Yes | awaiting_confirmation | `quote_id`, `customer_message_id` | Code checks: the card was delivered, the message came after it, it's an affirmative (section 6.4), the quote hasn't expired, the stock is still there. Then holds stock, creates the payment link and queues the payment message. Idempotent per quote |
| `cancel_order` | Yes | payment_pending | `order_id`, `reason` | Cancels an unpaid order, releases the hold, voids the PayPal order |
| `resend_payment_link` | Yes (outbound) | payment_pending | `order_id` | Re-queues the existing link; never creates a second PayPal order for the same order |
| `ask_shop_owner` | Yes | all except `handed_off` | `question`, `category`, `suggested_answers[]` (≤ 3) | Opens an Ask me question, sets `waiting_on_owner`, starts the window countdown (section 10) |
| `hand_off_to_owner` | Yes | all | `reason` (`asked_for_person`, `complaint`, `abuse`, `stuck`) | Switches the agent off for this chat and alerts the merchant |
| `remember_customer_fact` | Yes | all except `handed_off` | `key` (allow-listed), `value` | Saves episodic memory (section 8). Rejects keys not on the allow-list |
| `log_missed_demand` | Yes | all | `wanted_text`, `reason` | For Insights: sold out, not stocked, shop closed |
| `send_reply` | Yes (outbound) | all except `handed_off` | `text`, `language`, `choices[]` (≤ 13 quick replies), `reply_to_message_id` | **Ends the turn.** The text goes through the output checks, tokens are filled in, then it goes to the outbox |

**Deliberately not tools:** marking an order paid, refunds, discounts, changing prices or stock, sending messages outside the window. These are code paths or merchant actions in the app, never something the model can call.

---

## 6. The turn engine

### 6.1 The loop

```python
async def run_turn(conversation_id) -> None:
    turn = await tracing.start_or_resume(conversation_id)      # resumes a crashed turn
    gate = await inbound.check(turn)                           # caps, rate limit, budget
    if gate.stop:
        return await outbox.queue_template(turn, gate.template)
    ctx = await context.build(turn)                            # section 8, token budget
    for step in range(MAX_MODEL_CALLS):                        # 6
        if turn.elapsed() > TURN_DEADLINE:                     # 30 s
            break
        response = await llm.complete(ctx.messages, tools=registry.allowed(turn.state))
        await tracing.record_model_call(turn, step, response)
        if not response.tool_calls:
            ctx.add_correction("End the turn by calling send_reply.")   # once, then break
            continue
        for call in response.tool_calls:
            result = await registry.execute(turn, step, call)  # idempotent, permission-checked
            ctx.add_tool_result(call, result)
            if call.name == "send_reply" and result.ok:
                return await tracing.finish(turn, "replied")
    await outbox.queue_template(turn, "holding")               # never leave the customer silent
    await escalations.open(turn, "The assistant couldn't finish this reply")
    await tracing.finish(turn, "fallback")
```

### 6.2 Budgets (settings, with these defaults)

| Budget | Default | When exceeded |
|---|---|---|
| Model calls per turn | 6 | Holding template + Ask me |
| Tool calls per turn | 10 | Same |
| Turn deadline | 30 s | Same |
| Per model call timeout | 20 s, then retry (section 13) | Fallback model |
| Repair attempts on `send_reply` failing output checks | 1 | Holding template + Ask me |

### 6.3 Messages the model sees

1. `system`: `base.md` (cached), then the active playbook, then the context block (section 8).
2. Conversation history as `user` (customer) and `assistant` (our earlier replies) messages. Merchant messages typed in Instagram are `assistant` messages prefixed by code with "(Shop owner wrote)".
3. **Events** (payment received, hold expired, merchant answered) are **not** chat text. They're injected as a synthetic `assistant` tool call plus a `tool` result (`{"event": "payment_received", "order": "#1042", ...}`), which customers can't produce. This replaces the `[Shop system #tag]` notes.

**JSON fallback:** if the configured provider doesn't support tool calls (`LLM_TOOL_MODE=json`), the gateway asks for `{"tool_calls": [...]}` as JSON and parses it into the same structure, so the engine code is identical.

### 6.4 Quotes and confirmation (fixes the phase 1 bug)

1. `create_quote` saves the quote with `expires_at` (the earlier of the end of the business day and 2 hours) and queues a **quote card** from `templates/quote_card.yaml`: items, quantities, total, pickup or delivery, time. Code writes all of it. It has Instagram quick replies **Confirm** (payload `CONFIRM:<quote_id>`) and **Change** (`CHANGE:<quote_id>`).
2. When the outbox confirms the card was delivered, it stores `quotes.shown_message_id`. **A quote without a delivered card can't be confirmed.**
3. **A Confirm tap** arrives as a quick-reply payload. That's layer 0: code confirms the order directly, without the model, then runs a turn so the agent can say thanks.
4. **A typed yes** ("ok", "seri", "haan confirm"): the model calls `confirm_order(quote_id, customer_message_id)`. Code checks the message came after `shown_message_id`, the quote hasn't expired or been superseded, and a small, cheap **affirmation check** (yes / no / change / unclear, logged in the trace) says yes. "unclear" returns an error telling the model to ask again.
5. A **Change** tap or a change in words → `update_order_draft` supersedes the quote.

---

## 7. Conversation state

Code owns the state; the model can't set it.

| State | Meaning | Tools offered (besides the read tools and `send_reply`) |
|---|---|---|
| `browsing` | Questions, no order | `update_order_draft`, `send_menu_image`, `share_post`, `ask_shop_owner`, `hand_off_to_owner`, `remember_customer_fact`, `log_missed_demand` |
| `collecting_details` | Draft exists, something missing | `update_order_draft`, `create_quote`, `ask_shop_owner`, `hand_off_to_owner`, `remember_customer_fact`, `log_missed_demand` |
| `awaiting_confirmation` | Card delivered, waiting | `confirm_order`, `update_order_draft`, `ask_shop_owner`, `hand_off_to_owner` |
| `payment_pending` | Order placed, link sent | `resend_payment_link`, `cancel_order`, `get_order_status`, `ask_shop_owner`, `hand_off_to_owner` |
| `handed_off` | The merchant is handling it | None: the turn engine doesn't run; messages are logged |

**Flags alongside the state** (they don't replace it):
- `waiting_on_owner`: open questions the customer was told about. The context tells the model not to answer them; holding and follow-up messages are sent by code.
- `window`: `open`, `closing` (under 2 hours left), `human_agent_only` (24 hours to 7 days), `closed` (section 10).

Transitions happen only inside tool `run()` methods and payment/expiry handlers, each in one database transaction with the conversation row locked (`SELECT … FOR UPDATE`), and each written to `order_events` or `turn_steps`.

---

## 8. Memory

Four kinds of memory, at three scopes. "Per user" means **per customer** (episodic) and **per shop** (semantic, procedural).

| Type | What it is in sellix | Scope | Stored in | How it reaches the model |
|---|---|---|---|---|
| **Semantic** (facts about the business) | Shop profile, policies, FAQs, catalog, product details, **aliases and glossary** ("choco" = chocolate, "rendu" = 2, "seri" = ok), opening hours | Per shop (plus a global glossary of code-mixed words) | `shop_profiles`, catalog tables, `product_aliases`, new `glossary_terms` | Profile and hours in the context block; catalog via the menu or `search_catalog`; details via `get_product_details` |
| **Episodic** (what happened before) | Customer facts (name, preferred language and script, saved addresses, usual order, dietary notes they volunteered), order history, past questions and the merchant's answers, summaries of older conversations | **Per customer, per shop** | New `customer_memories`, new `conversation_summaries`, `orders` | A short "About this customer" section in the context block; details via `get_customer_profile` and `get_order_status` |
| **Procedural** (how to do things) | Base prompt, playbooks, tool descriptions, routing rules, **the merchant's saved rules** ("bulk orders over 30: ask me") | Global (prompts) + per shop (saved rules) | `prompts/` files; `merchant_rules` | The active playbook in the system prompt; saved rules in the context block |
| **In-context** (working memory) | This turn: the last messages, the order state, open questions, tool results | Per turn | Built fresh each turn | The message list itself, within a token budget |

### 8.1 Context block (order and budget)

Built by `context.py`, things that rarely change first so providers can cache them. Default total budget: 6,000 input tokens before tool results.

1. `base.md` (cached)
2. Active playbook
3. Shop profile + saved rules + glossary (semantic, procedural)
4. "Now" line and opening hours (from phase 1)
5. Menu: today's stock with ids and price tokens if ≤ 40 sellable items; otherwise a one-paragraph catalog summary and "use search_catalog"
6. About this customer (episodic, ≤ 150 tokens)
7. State brief: stage, draft or quote summary, open questions, window status
8. Summary of older conversation (episodic, if any)
9. Recent messages: the newest that fit the remaining budget, at most 20

### 8.2 Writing memory

- **Customer facts** only through `remember_customer_fact`, with an allow-list: `name`, `preferred_language`, `address` (label + text), `usual_order` (item ids), `dietary_note`, `occasion` (e.g. birthday date if they share it). Each fact stores its source message, `confidence`, `updated_at`, and an `expires_at` where sensible (addresses: 12 months).
- **Never stored as memory:** payment details, phone numbers typed for someone else, health information beyond what the customer volunteered for their order, anything about other people.
- **Conversation summaries** are written by a background job (not in the turn) when a conversation has more than 30 messages: a cheap model summarises the older part into ≤ 200 tokens, **without amounts** (amounts come from orders). The summary stores which message ids it covers.
- **Saved rules** (procedural) are written only when the merchant approves "Always answer this way" in Ask me (dev checklist 6.3).
- **Corrections win:** a newer fact replaces an older one for the same key; the merchant can view and delete any customer memory in the app (Chats → customer).

### 8.3 Privacy (DPDP)

- A customer asking to be forgotten → `hand_off_to_owner(reason="data_request")`, and an operator command deletes their memories, summaries and messages (order records keep only what accounting needs).
- Memory is per shop: one shop never sees another shop's memory of the same person.
- Retention: messages 12 months (as in `database-schema.md`), summaries and memories until deleted or expired.

---

## 9. Instagram: what the API can and can't do

sellix uses the **Instagram API with Instagram Login** (`graph.instagram.com`), with the permissions `instagram_business_basic` and `instagram_business_manage_messages`. Serving shops we don't own needs **Advanced Access** through Meta App Review; until then only accounts with a role on our app work.

| Capability | Available? | Notes for sellix |
|---|---|---|
| Receive DMs, echoes, story replies, story mentions, quick-reply taps, postbacks, reactions, unsends | ✅ by webhook | Already receiving DMs, echoes and story-reply URLs. Phase 2 adds quick-reply payloads, story mention, reactions and unsend handling |
| Send text | ✅ | Up to **1,000 bytes** (UTF-8 *bytes*, not characters: Tamil text uses ~3 bytes per character, so ~330 Tamil characters). The outbox must measure bytes |
| Send images, video, audio, PDF | ✅ | Images png/jpeg ≤ 8 MB (up to 10 per message); audio, video and PDF ≤ 25 MB |
| Share the shop's own post | ✅ `MEDIA_SHARE` with the post id | Only posts the shop owns. Basis for `share_post` |
| Quick replies | ✅ | Basis for quote cards and choices (verify the current maximum count; plan for ≤ 13) |
| Generic template (cards with image, title, buttons) | ✅ (verify for Instagram Login) | Could show product cards; not required in phase 2 |
| Reply to a specific message, react with an emoji | ✅ | `reply_to.mid`; `sender_action: react` |
| Read message history (Conversations API) | ⚠️ Limited | Lists conversations and message ids, but **details only for the 20 most recent messages** of each conversation. Inactive conversations in the Requests folder (30+ days) aren't returned. **Our own `messages` table is the source of truth** |
| Message a customer first | ❌ | Only after the customer has messaged the shop |
| Message outside 24 hours | ⚠️ | Only with the **Human Agent** tag, up to 7 days, for human-written replies (section 10) |
| Store story-mention media on our servers | ❌ | Meta: "You must not store or cache the media content on your server." Store the CDN URL only |
| Private replies to comments (comment → DM) | ✅ with the comments permission | Phase 3: "comment 'price' and we'll DM you" flows |
| Rate limits | Per Instagram account | Meta documents per-second limits for sending (text and audio/video differ) and **2 calls per second for the Conversations API**; it also limits too many messages to one thread. The outbox paces sends per thread (section 13) |

**Are we storing message history? Yes.** Every inbound customer message, every outbound reply (with its delivery status), every merchant echo and every system event is a row in `messages`, scoped by `merchant_id` and `conversation_id`. That's why sellix doesn't depend on Instagram's 20-message limit. Phase 2 adds an **optional backfill** when a shop connects: for each recent conversation, fetch the last 20 messages once, so the agent has context for customers who wrote before sellix was connected (respecting the 2 calls per second limit).

---

## 10. The 24-hour window and late answers

### 10.1 The rule

Instagram lets a business send messages only **within 24 hours of the customer's last message**. Each new customer message restarts the 24 hours. After that, the only option is the **Human Agent tag**: a reply written by a real person, up to **7 days** after the customer's last message. It needs Meta's approval for the app and must not be promotional.

### 10.2 Why late answers fail today

1. A customer asks for a custom cake at 10 am Monday; the agent says "I'll check with the shop" and opens an Ask me question.
2. The merchant answers at 11 am Tuesday, 25 hours later.
3. `answer_question` turns the answer into a note, a turn runs, and `_send` calls Instagram.
4. Instagram rejects it: the window closed at 10 am Tuesday. `_send` marks the message failed and opens *another* Ask me question ("I couldn't send my reply"). **The customer never hears back.**

Nothing warned the merchant that the window was closing, nothing tried the Human Agent tag, and nothing delivers the answer if the customer writes again.

### 10.3 What phase 2 does

| When | What sellix does |
|---|---|
| Question opened | Ask me card shows a countdown: "Reply within 23 h 40 min to reach Priya" |
| 2 hours left and still unanswered | Push to the merchant: "Priya's window closes at 10 am; answer now or she may not get it" |
| Merchant answers inside 24 h | Normal: the agent passes it on in the customer's language |
| Merchant answers between 24 h and 7 days | If our app has Human Agent approval: send **the merchant's words as written** (not an AI rewrite, since the tag is for human replies) with the Human Agent tag. Without approval: don't send; tell the merchant "Priya must message you first, or reply from the Instagram app" and keep the answer **pending** |
| Customer writes again later | Deliver any pending answer first (the window is open again), then continue the turn |
| Over 7 days | Mark pending answers expired; the merchant sees it in Ask me |
| Holding and follow-up messages | Only inside the 24-hour window (phase 1 already checks this for follow-ups) |

**Implementation:** `conversations/window.py` computes the window from `conversations.last_customer_message_at`. The outbox checks it before every send. Each outbound message has `window_policy` = `standard` | `human_agent` | `when_open` (deliver when the customer next writes). Classify Instagram's "outside the allowed window" error as permanent (no retries) and move the message to `pending_window`.

---

## 11. Stories, images, posts and media

### 11.1 Story replies (a customer replies to the shop's story)

The webhook gives `reply_to.story` with the story **id** and a media **url** that stops working when the story expires (24 hours) or is deleted. Today we keep only the url.

1. **Parse** both `story.id` and `story.url` into the message (`details.story = {id, url}`).
2. **Registry first:** `stories` table keyed by `(merchant_id, story_id)` → products the story shows. Filled when the merchant tags a story in the app (dev checklist 8.2), or by step 3.
3. **First reply to an untagged story:** while the story is live, run the vision model on it **once** (pass the CDN url to the model, or fetch it into memory for the call only), match the result against the catalog, and save **the derived result** in `stories`: product ids, confidence, caption text, a perceptual hash. Mark it `needs_merchant_confirmation` and show it on Today so the merchant can confirm with one tap.
4. **Every later reply** to the same story: registry lookup, no AI cost. `lookup_story` returns the products; the playbook `story_or_photo.md` handles "idhu venum" / "this one" / "M size irukka?".
5. **Expired or unknown story:** the agent asks for a screenshot or sends today's menu image.

**Storage rule:** don't copy story media into our storage. This is the shop's own story, but Meta's docs prohibit storing story-mention media and are not explicit for replies; store derived data (product ids, hash, caption) and the CDN url only, until we confirm otherwise (section 21). Photos the merchant uploads in our app (morning stock, menu image) are the merchant's own uploads and may be stored.

### 11.2 Story mentions (a customer mentions the shop in *their* story)

Arrives as a `story_mention` attachment with a CDN url. **Never store the media.** Use it only to thank the customer or start a conversation. Fetch the url via the Conversations API (`<MESSAGE_ID>?fields=story`) if needed. Show a placeholder once it expires.

### 11.3 Photos and screenshots from customers

`describe_image(attachment_id)` sends the attachment url to the vision model during the turn, caches the *result* (not the image) by attachment id and perceptual hash, and matches against the catalog and registered stories. A screenshot of a known story or the menu image matches by hash without any model call. At most 3 images per turn go to the vision model; more → ask which one.

### 11.4 Voice notes

Phase 3 (needs the speech-to-text bake-off). In phase 2, `transcribe_voice` returns `not_available`, and the playbook asks the customer to type, or escalates.

### 11.5 Sending posts and media

- `share_post(item_id)` sends the shop's own post via `MEDIA_SHARE`. Add `product_posts (merchant_id, product_id, ig_media_id)`, filled when the merchant links a post to a product in Catalog.
- `send_menu_image()` sends today's menu photo as an image attachment.
- All media goes through the outbox, like text.

---

## 12. Inbound protection: rate limits, size caps, budgets

The model must never receive a huge passage, and one customer must never be able to run up the shop's bill.

| Protection | Default | Behaviour |
|---|---|---|
| Normalise text | Always | Unicode NFKC, remove zero-width and control characters, collapse whitespace |
| Max characters per message sent to the model | 1,000 | Longer messages are cut with "[…message shortened]"; the full text stays in `messages` for the merchant |
| Max characters per turn (a batch of messages) | 2,000 | Oldest parts of the batch are cut first |
| Message far too long | > 4,000 characters | No model call. Code sends `templates/too_long.yaml` ("Could you send that in a shorter message?") and flags the chat |
| Per-customer message rate | 20 messages / 5 min | Extra messages are stored but don't trigger turns; after the burst, one turn answers the latest |
| Per-customer turns | 30 turns / hour, 150 / day | Then one polite template, then silence until the next hour; Ask me card "Unusual activity from @user" |
| Per-shop AI budget | Configurable per shop; default from the plan's cost target | Soft limit (80%): alert the merchant and ops. Hard limit: switch the shop to templates + Ask me only until the next day |
| Attachments per turn to vision | 3 | Ask which one |

Rate limits are counted in Postgres (a `rate_limit_counters` table or counts over `messages` with an index on `(conversation_id, created_at)`), so they survive restarts and work with several workers. No Redis.

---

## 13. Reliability: retries, outbox, durable execution

### 13.1 Model calls (`llm.py`)

- Retry on timeouts, HTTP 429 and 5xx: up to 2 retries with exponential backoff and jitter (0.5 s, 1.5 s), respecting `Retry-After`.
- **Fallback chain** from settings (`LLM_MODELS=primary,fallback`): after the primary's retries fail, call the fallback. Record which model answered.
- **Circuit breaker:** if a model fails 5 times in 1 minute, skip it for 2 minutes.
- Non-retryable errors (400 bad request, 401) fail immediately and are logged with the prompt version.

### 13.2 The outbox

Every outbound message (text, image, quote card, payment link, template) is a row in `outbound_messages` before anything is sent:

- `idempotency_key` (unique): e.g. `turn:<turn_id>:reply`, `quote:<quote_id>:card`, `order:<order_id>:link`. Queuing twice does nothing.
- A procrastinate job sends it, with a `lock` per conversation, so messages to one customer go out in order and are paced (at least 1 second apart).
- **Retryable** (network errors, 5xx, rate limit): retry with backoff up to 6 times over ~10 minutes.
- **Permanent** (window closed, user blocked the shop, invalid recipient): no retry. Set the status, and for window errors move to `pending_window` (section 10).
- On success, store Instagram's message id and mark `sent`; post-send hooks run (e.g. set `quotes.shown_message_id`).
- A periodic job finds rows stuck in `sending` for > 2 minutes and reconciles them.

### 13.3 Resumable turns

- `run_agent_turn` gets a retry strategy (3 attempts).
- Each turn has a row in `agent_turns`; each model call and tool call a row in `turn_steps` with its idempotency key and result.
- On retry, the engine **replays stored steps** instead of re-running them, then continues. A crash after placing an order but before replying no longer loses the payment link: the stored `confirm_order` result is reused, and the payment message is already in the outbox.

### 13.4 Temporal: decision

[Temporal](https://temporal.io/) gives durable workflows: a workflow's history is stored, steps (activities) retry automatically, and timers can wait days. It's a strong tool. **We're not adopting it in phase 2**, for these reasons:

- It's a second system to run: Temporal Cloud (a paid service) or a self-hosted cluster with its own database. That conflicts with the plan's low-cost, one-database rule (ADR 0003).
- Our durable needs are short turns (seconds), timers (hold expiry, follow-ups) and a few multi-day order flows. Procrastinate + the outbox + idempotent steps + state in Postgres cover these.
- Temporal workflow code has determinism rules that every contributor must learn; the team is small and on a deadline.

**Revisit when** any of these is true: multi-day workflows multiply (custom orders with deposit → balance → delivery, refunds with approvals), we need workflows spanning several services, or procrastinate becomes a throughput bottleneck. Keep the step and idempotency design in 13.3 so that moving a flow to Temporal (or a Postgres-based durable-workflow library) later is a contained change.

---

## 14. Payments security

Payments must be the most boring, most checked part of the system.

**What already exists (keep it):** amounts come from the database; PayPal orders are created with a `PayPal-Request-Id` per order (retry-safe) and `custom_id` = our order id; captures use a request id; webhook signatures are verified through PayPal's `verify-webhook-signature` API; the webhook inbox deduplicates; the model only sees a `{payment_link}` placeholder; an amount mismatch goes to the merchant.

**Add in phase 2:**

1. **Re-check every capture with PayPal before marking an order paid.** Today `PAYMENT.CAPTURE.COMPLETED` is applied from the webhook body once its signature is verified. Instead, fetch the order from PayPal (`GET /v2/checkout/orders/{id}`) and require all of: status `COMPLETED`, amount and currency equal to our order, `custom_id` equal to our order id, and (once shops connect their own PayPal) the payee equal to the shop's PayPal merchant id.
2. **The return page never marks anything paid by itself.** It triggers the same capture-and-verify path.
3. **One PayPal order per sellix order.** `resend_payment_link` reuses it; a new link is created only after the old PayPal order is voided (after a change or cancel).
4. **Links expire with the hold.** When the hold expires, void the PayPal order so an old link can't be paid. Payments that still arrive late go to the existing "paid after expiry" path.
5. **No refund or "mark paid" tool for the agent.** Refunds happen only from the merchant app, after the merchant confirms with re-authentication (a fresh session check), with an audit record. Manual UPI confirmations ("Paid" button) also need the merchant's tap and are audited.
6. **Per-customer limits:** at most 2 unpaid orders per customer per shop at a time; more → `ask_shop_owner`.
7. **Never in prompts or logs:** access tokens, PayPal ids beyond the order number, payer emails, full payment links in logs (log a hash). `structlog` processors redact known secret fields.
8. **Secrets:** PayPal and Meta secrets only in environment variables (Render environment groups); Instagram tokens encrypted with rotatable Fernet keys (exists). Webhook ids per environment.
9. **Audit:** every payment state change is an `order_events` row with actor (`paypal`, `merchant`, `system`), the provider ids and the verification result.
10. **Never touch card data.** PayPal's hosted pages handle it; sellix stays out of PCI scope.

Tests: a forged webhook (bad signature), a valid webhook whose PayPal order says `PENDING`, a capture with a different amount, a replayed webhook, a capture for another shop's order, a link paid after expiry.

---

## 15. Output guardrails

Everything `send_reply` sends goes through `guardrails/output.py`:

1. **Money tokens.** The model writes `[[price:<item_id>]]`, `[[quote_total]]`, `[[order_total]]`, `[[order_number]]`, `[[payment_link]]`. Code fills them from the database for this turn's quote or order. An unknown token or a token with nothing to fill → rejected.
2. **No raw amounts.** Any amount the model typed (₹, Rs, rupees, rupa, ரூ, रु, $, USD, or a bare number next to "total", "price" or "mothham") → rejected. Because code fills in all amounts, this rule can be strict.
3. **No links**, except the filled-in payment link.
4. **No promises** from the shop's "never promise" list (stored per shop, edited in Settings) plus the global list: discounts, free items, free delivery, delivery times.
5. **Health claims** only if `get_product_details` returned that field in this turn.
6. **Language and script** match the customer's latest message (phase 1 check, extended to romanised Tamil and Hindi with a small word list).
7. **Length:** ≤ 1,000 bytes after filling tokens; long replies are split by the outbox at sentence boundaries into at most 2 messages.
8. On failure: one repair attempt with the reasons; then the holding template and an Ask me question.

---

## 16. Observability

- **`agent_turns`:** conversation, trigger message, state before and after, prompt ids and versions, playbook, model(s) used, total tokens, cost, latency, outcome (`replied`, `fallback`, `gated`, `handed_off`).
- **`turn_steps`:** each model call (request hash, response, tokens, latency) and each tool call (arguments, result, duration, idempotency key).
- **`just cli replay-turn --turn-id <id> [--prompts current] [--model x]`:** rebuilds the exact context and re-runs it. Every bad production reply becomes an eval case.
- **Metrics (logged, then on a dashboard):** turns per minute, fallback rate, tool error rate by tool, output-check rejection rate by reason, p50/p95 turn latency, cost per conversation and per order, outbox retry and failure counts, pending-window messages.
- **Alerts:** fallback rate > 10% for 10 minutes; any `payment_verification_failed`; outbox permanent failures > 5 in an hour for one shop; a shop over its AI budget.

---

## 17. Evals and tests

| Layer | What | Runs |
|---|---|---|
| Unit | Each tool's validation and permission checks; output guardrails (including Tamil-script and token cases); window logic; rate limits; prompt store | Every PR |
| Tool contract | Each tool against a real database: happy path, invalid ids, wrong state, idempotent retry | Every PR |
| Scripted conversations | Multi-turn scenarios through the real engine with a fake model that emits scripted tool calls: standard order, change after quote, Confirm tap, typed yes, "no", expired quote, story reply, payment received, hold expired, late merchant answer, window closed, crash and resume | Every PR |
| Live-model evals | `evals/run.py` extended to multi-turn: 50+ anonymised real chats + the adversarial set (fake system notes in every bracket style, discount pressure, fake screenshots, huge messages, language switches, prompt injection inside image text) | `run-evals` label and nightly |
| Simulator | `/simulator`: a web chat that goes through the same pipeline. Used by developers, end-to-end tests and judges | Manual and E2E |
| CI gate | Live-model score must not drop on any change to `prompts/`, tools or model config | `evals.yml` |

**Required regression tests from the phase 1 review:** order from an unseen quote (must be refused), stale quote (must be refused), wrong total in Tamil script (must never be sent), crash after `confirm_order` (payment message still delivered once).

---

## 18. Database changes

One migration per step, in `supabase/migrations/` (new files only).

| Migration | Adds |
|---|---|
| `agent_turns_and_steps` | `agent_turns`, `turn_steps` (partition by month later) |
| `outbound_messages` | `outbound_messages` (idempotency key unique, status, window policy, attempts, next attempt at, error, provider message id) |
| `quote_cards_and_expiry` | `quotes.expires_at`, `quotes.shown_message_id`; `conversations.order_stage` adds `handed_off` |
| `memory` | `customer_memories (merchant_id, customer_id, key, value jsonb, source_message_id, confidence, expires_at)`, `conversation_summaries`, `glossary_terms`, `merchant_rules` (if not on `main` yet) |
| `window_and_pending` | `escalations.window_closes_at`, `escalations.answer_delivery` (`sent`, `pending_window`, `human_agent`, `expired`) |
| `stories_and_media` | `stories (merchant_id, story_id, cdn_url, products jsonb, confidence, confirmed_by_merchant, hash, expires_at)`, `media_results (attachment hash → vision result)`, `product_posts` |
| `limits_and_budgets` | `rate_limit_counters` (or indexes for counting), `merchant_settings.ai_daily_budget_minor`, `merchant_settings.never_promise` |

Every business table: `merchant_id`, row-level security enabled, money as integer minor units, times in UTC (`dev-plan.md` section 8).

---

## 19. Rollout

1. **Feature flag `AGENT_ENGINE=v1|v2`**, per shop (`merchant_settings.agent_engine`). Both engines share orders, payments and the outbox.
2. **Shadow mode:** v2 runs on real traffic for a test shop, writes its traces and would-be replies, but v1 sends. Compare in a report.
3. **Draft mode for v2:** the merchant approves each reply in Chats before it goes out.
4. **Cutover per shop** once the eval gate passes and a week of shadow traces show no critical issue. Delete v1 code after all shops move.

---

## 20. Work plan

Order matters: each step leaves the system working. **Who:** P = platform and channels · AI = agent · A = Flutter app · C = commerce and data.

- [ ] **2.0 Prerequisites** (all). Section 0: merge `main`, fix the unseen-quote bug and quote expiry, regression tests.
  Done when: `agent-phase-1` is merged into `main` with the new tests green.
- [ ] **2.1 Prompt store** (AI). Move every prompt and customer-facing fixed message into `prompts/`; loader, validation, versions; no behaviour change.
  Done when: `grep` finds no prompt text in Python, and all tests pass unchanged.
- [ ] **2.2 Outbox** (P). `outbound_messages`, send job, retries, error classification, pacing; all current sends go through it.
  Done when: a test with Instagram returning 500 twice then 200 delivers exactly one message.
- [ ] **2.3 Window handling** (P + A). `window.py`, outbox checks, pending delivery, countdown in Ask me, push at 2 hours left, Human Agent sending behind a setting.
  Done when: scenario 10.2 delivers the answer when the customer writes again, and the merchant was warned.
- [ ] **2.4 LLM gateway v2** (AI). Tool calling, JSON fallback mode, retries, fallback chain, circuit breaker, usage and cost logging.
  Done when: tests pass with the primary model failing, and in JSON fallback mode.
- [ ] **2.5 Tool registry and the first tools** (AI + C). Registry, permissions, idempotency; `search_catalog`, `get_product_details`, `update_order_draft`, `create_quote` (with quote card), `confirm_order`, `send_reply`, `ask_shop_owner`, `hand_off_to_owner`.
  Done when: each has contract tests, including wrong state and retry.
- [ ] **2.6 Turn engine and tracing** (AI). `engine.py`, `context.py`, `agent_turns`, `turn_steps`, resume, budgets, events as tool results, `replay-turn`.
  Done when: the scripted conversations in section 17 pass on v2, including crash and resume.
- [ ] **2.7 Output guardrails v2** (AI). Money tokens, strict amounts, never-promise list per shop, health claims, byte length, splitting.
  Done when: the adversarial output set never produces a sent raw amount.
- [ ] **2.8 Quote cards and Confirm taps** (P + C). Quick replies on Instagram, payload parsing as layer 0, `shown_message_id`, affirmation check.
  Done when: a tap places the order without a model call; "no" never places one.
- [ ] **2.9 Memory** (AI + C + A). `customer_memories`, `remember_customer_fact`, `get_customer_profile`, summaries job, glossary, saved rules in context; the merchant can view and delete customer memory.
  Done when: a returning customer's "same as last time" quotes their usual order and address.
- [ ] **2.10 Inbound protection** (P). Normalisation, caps, rate limits, per-shop budget.
  Done when: a 10,000-character message and a 100-message burst each cost at most one model call.
- [ ] **2.11 Payments hardening** (C). Section 14 items 1–7 and their tests.
  Done when: all six payment attack tests pass.
- [ ] **2.12 Stories and images** (P + AI + A). Story id parsing, registry, first-reply identification, merchant confirmation on Today, `lookup_story`, `describe_image`, story mentions without storage, `share_post`, `send_menu_image`.
  Done when: "idhu venum" on a real story quotes the right product, and later replies cost no image call.
- [ ] **2.13 Remaining tools** (AI + C). `get_order_status`, `cancel_order`, `resend_payment_link`, `get_customer_profile`, `log_missed_demand`, `load_playbook`.
- [ ] **2.14 Playbooks** (AI). Split `base.md`; write the nine playbooks with code-mixed examples; selection logic.
  Done when: the live eval score is at least the phase 1 score.
- [ ] **2.15 Evals v2 and simulator** (AI + P). Multi-turn runner, 50+ real chats, adversarial set, CI gate, `/simulator`.
- [ ] **2.16 Rollout** (all). Flag, shadow, draft, cutover (section 19).

---

## 21. Facts to verify before building on them

Spike each with the team's test account and record the payloads in `docs/meta-payloads.md`:

1. Human Agent tag: is it available under Instagram Login, what App Review it needs, and the exact request field.
2. Quick replies on Instagram Login: maximum count, payload length, how a tap arrives in the webhook.
3. Whether the shop's own live stories can be listed and fetched with our permissions, and whether storing **derived** data from the shop's own story is fine (we plan not to store the media itself).
4. Exact error codes for "outside the allowed window", "user blocked", and rate limiting, so the outbox classifies them correctly.
5. Current send rate limits for Instagram Login specifically (third-party sources disagree).
6. Generic template support under Instagram Login (optional).
7. PayPal: the void/cancel behaviour for an unpaid order, and the payee check once shops connect their own PayPal (Partner Referrals).

---

## Sources

- [Meta: Instagram API with Instagram Login, Send Messages](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/messaging-api): window rules, message types and limits, permissions
- [Meta: Instagram API with Instagram Login, Conversations API](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/conversations-api): 20-most-recent-messages limit, Requests folder rule
- [Meta: Instagram Messaging, Story Mention](https://developers.facebook.com/documentation/business-messaging/instagram-messaging/features/story-mention): no storing media, CDN URL behaviour
- [Meta: Messenger Platform rate limits](https://developers.facebook.com/docs/messenger-platform/overview/rate-limiting): Send API and Conversations API limits
- [CM.com: Instagram inbound messaging](https://developers.cm.com/messaging/docs/instagram-messaging-inbound): `reply_to` story id and URL in story replies
- [Chatwoot: Human Agent tag](https://chatwoot.com/hc/user-guide/articles/1745225158-what-is-human-agent-tag-in-instagram-messenger-channel): 7-day window for human replies
- [Temporal](https://temporal.io/)
