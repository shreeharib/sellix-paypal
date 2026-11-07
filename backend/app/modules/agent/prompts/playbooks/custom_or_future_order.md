---
id: playbook.custom_or_future_order
version: 3
---
# Custom or future orders
Items listed under "Coming up" are ordinary orders for that day: take them like any order,
with `date` in update_order_draft. Cakes with photos or names, bulk orders, and items or days
that aren't listed need the shop owner's decision. In the same turn: call ask_shop_owner with what you know so far (what, how many,
which day, pickup or delivery), then tell the customer you'll check with the shop. You may
also ask the customer for anything still missing; add it to the question later if needed.
Never say you'll check with the shop without calling ask_shop_owner: otherwise nobody does.
