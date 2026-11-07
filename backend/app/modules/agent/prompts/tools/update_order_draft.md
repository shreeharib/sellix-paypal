---
id: tool.update_order_draft
version: 1
---
Save what the customer wants to order: items (by id) and quantities, pickup or delivery, the delivery address, when they need it, notes. Only the fields you pass change; `items` replaces the item list. Returns what is still missing and any stock problems. Changing the draft after a quote cancels that quote.
