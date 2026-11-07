# Evals: language test set and model bake-off

How the models are chosen and how prompt changes are checked. Background: [docs/product-plan.md](../docs/product-plan.md), sections 5 and 8.

## What goes here

| Folder | Contents |
|---|---|
| `datasets/` | Anonymised customer messages in English, Tamil-English, Hinglish and other mixes, each with the expected result |
| `images/` | Product photos and story images for the vision tests, each with the expected products |
| `run.py` | Runs multi-turn scenarios (`datasets/*.jsonl`) through the simulator API of a running sellix: the real pipeline and the configured model. Reports the score, fallback rate, p95 latency and cost; exits non-zero below `--min-score` |
| `scoring.py` | What each turn is checked for: tools used or not used, how the turn ended, the stage after it, reply patterns |
| `demo_stock.json` | The stock the eval shop is seeded with |

## Dataset format (one JSON object per line, `.jsonl`)

```json
{"id": "ta-en-0001", "language": "ta-en", "messages": ["rendu chocolate cookie venum", "evening ku kidaikuma?"], "stock": [{"product": "Scoop cookie", "variant": "Chocolate", "price": 60, "available": 8}], "expected": {"intent": "order", "items": [{"product": "Scoop cookie", "variant": "Chocolate", "quantity": 2}], "when": "today evening", "reply_language": "ta-en"}}
```

## Rules

- Only anonymised data: no real names, phone numbers, addresses, account IDs or media links.
- Use real chats only with the account owner's consent.
- The bar a model must pass is in the product plan, section 8.

## Running the multi-turn evals

```bash
just cli create-merchant --name "Eval Bakery"                      # note the id
just cli set-stock --merchant-id <id> --file ../evals/demo_stock.json
just cli set-agent-engine --merchant-id <id> v2
TOKEN=$(just cli issue-token --merchant-id <id>)
python evals/run.py --token "$TOKEN" evals/datasets/scenarios.jsonl evals/datasets/adversarial.jsonl --min-score 0.9
```

CI runs the same nightly and on PRs labelled `run-evals` (`.github/workflows/evals.yml`).

### Any kind of shop

`datasets/any_shop.jsonl` runs the same agent on clothing, jewellery and skincare as well as food (the
stock is in `demo_stock.json`): tone with no self-introduction, an honest answer to "are you a bot?",
facts the shop hasn't listed (fabric, returns, skin type) going to the owner, size variants.

### Pre-orders and the menu

`datasets/preorders_and_menu.jsonl` needs the pre-order cake: run it with `--seed-preorder`, which sets
up "Diwali cake (1 kg)" 8 days ahead the way the merchant app does (one-day item, orders close the
day before). It checks that a greeting lists no products, that a listed pre-order is answered and
booked without asking the owner, and that "what do you have?" shows today's items and the pre-orders.

### Owner answers

`datasets/owner_answers.jsonl` covers the owner answering a question the assistant asked, which
arrives later and through a background job. A turn can be `{"owner_answers": "text",
"question_contains": "cash", "expect": {...}}`: the runner answers the newest open question (or the
newest containing that text) and waits up to two minutes for the assistant's follow-up. The eval
server must run the job worker (`RUN_WORKER_IN_PROCESS=true`, the default), unlike the other
datasets.

### Checks on every turn

Whatever a scenario expects, a turn fails if an agent message contains an internal item id (like
`i3f9a2c`) or an unfilled `[[token]]`.

### When to run them

- Before every change to a prompt, a playbook, a tool or an output check (`CONTRIBUTING.md`).
- Run twice: a language model doesn't answer the same way every time. One failure in several
  runs is a flaky scenario to look at, a scenario failing every run is a bug.
- In production, watch `python -m app.cli agent-health --days 1`: the share of `fallback` turns
  and the top errors. A fallback rate above a few percent means look at the traces
  (`replay-turn`) the same day.
