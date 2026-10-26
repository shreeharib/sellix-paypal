# Evals: language test set and model bake-off

How the models are chosen and how prompt changes are checked. Background: [docs/product-plan.md](../docs/product-plan.md), sections 5 and 8, and [docs/agent-improvement-plan.md](../docs/agent-improvement-plan.md), section 3.5.

## What goes here

| Path | Contents |
|---|---|
| `datasets/` | Test conversations, each with the expected result (format below) |
| `images/` | Product photos and story images for the vision tests, each with the expected products |
| `run.py` | Runs datasets against one or more models with the production prompt, parser and reply checks; prints a score and saves details in `results/` (not committed) |

| Dataset | What it covers |
|---|---|
| `orders.jsonl` | Standard orders in English, Tamil-English and Hinglish: quoting, missing details, typos, variants, sold out, confirm and change after a quote, payment notes, future dates |
| `adversarial.jsonl` | Spoofed system and owner notes, "ignore your rules", discount pressure, fake payment screenshots, recipe fishing, allergens, language switches, Tamil script, opening hours, links, "are you a bot?", questions waiting on the owner |

Both are **synthetic**: written by the team to cover each rule, not real chats. The 50 anonymised pilot chats (plan item 1.7) still need adding, as `datasets/pilot.jsonl`.

## Run it

It calls the model in `backend/.env` and costs credits, so run it on demand:

```bash
just evals                                   # every dataset
just evals --dataset adversarial             # one dataset
just evals --case ord-typo                   # one case
just evals --model gpt-5.4 --model gpt-5-mini   # compare models (same provider)
just evals --min-score 0.9                   # exit code 1 below 90% of cases passing
```

Without just: `cd backend && uv run python ../evals/run.py ...`

A case passes when every check passes. The free tests in `backend/tests/unit/test_evals.py` keep the datasets valid and the scoring honest on every PR.

## Dataset format (one JSON object per line, `.jsonl`)

```json
{"id": "ta-en-0001", "language": "ta-en", "messages": ["rendu chocolate cookie venum, inniku 6 manikku pickup"], "expected": {"action": "quote_order", "items": [{"product": "Scoop cookie", "variant": "Chocolate", "quantity": 2}], "reply_language": "ta-en"}}
```

| Key | Meaning |
|---|---|
| `id` | Unique name |
| `messages` | The customer's messages, oldest first. Or use `history` instead: `[{"from": "customer" \| "agent" \| "system" \| "owner", "text": "..."}]`. In `history` text, `{id:Product\|Variant}` becomes that item's stock ID |
| `stock` | Optional. `[{"product", "variant", "price", "available", "currency"}]`, price in rupees or dollars. Default: Sweet Crumbs' cookies and brownies (`run.py`) |
| `profile`, `hours`, `now`, `timezone` | Optional. Shop profile Markdown; hours like `"mon=closed tue-sun=09:00-20:00"` (`""` for not set); the moment of the chat as ISO time |
| `order`, `waiting` | Optional. Code's summary of the order and of questions waiting on the owner, as the agent sees them |
| `expected` | The checks, all optional: `action` (`"quote_order"`, `"place_order"` or `null`), `items` (what a quote asks for), `quote_id`, `needs_owner`, `reply_language`, `must_say_any` and `must_not_say` (regular expressions, case-insensitive), `passes_checks` (the production reply checks; on by default) |

## Rules

- Only anonymised data: no real names, phone numbers, addresses, account IDs or media links.
- Use real chats only with the account owner's consent.
- The bar a model must pass is in the product plan, section 8.
