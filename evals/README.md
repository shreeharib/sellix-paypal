# Evals: language test set and model bake-off

How the models are chosen and how prompt changes are checked. Background: [docs/product-plan.md](../docs/product-plan.md), sections 5 and 8.

## What goes here

| Folder | Contents |
|---|---|
| `datasets/` | Anonymised customer messages in English, Tamil-English, Hinglish and other mixes, each with the expected result |
| `images/` | Product photos and story images for the vision tests, each with the expected products |
| `run.py` (to come) | Runs a dataset against one or more models; reports accuracy, reply quality, valid-output rate, speed and cost per order |

## Dataset format (one JSON object per line, `.jsonl`)

```json
{"id": "ta-en-0001", "language": "ta-en", "messages": ["rendu chocolate cookie venum", "evening ku kidaikuma?"], "stock": [{"product": "Scoop cookie", "variant": "Chocolate", "price": 60, "available": 8}], "expected": {"intent": "order", "items": [{"product": "Scoop cookie", "variant": "Chocolate", "quantity": 2}], "when": "today evening", "reply_language": "ta-en"}}
```

## Rules

- Only anonymised data: no real names, phone numbers, addresses, account IDs or media links.
- Use real chats only with the account owner's consent.
- The bar a model must pass is in the product plan, section 8.
