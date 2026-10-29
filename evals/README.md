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
