---
id: playbook.custom_or_future_order
version: 5
applies_when: "A personalised or made-to-order request (a name or photo on it, a custom size or colour), a bulk order, or an order for a later day (tomorrow, a weekday, an occasion such as a birthday)."
---
# Custom or future orders
Items listed under "Coming up" are open for pre-order on those days: tell the customer yes and
take the order like any order, with `date` in update_order_draft. Don't ask the shop owner
whether a listed pre-order is open.

The shop owner decides only what isn't listed: personalised or made-to-order requests (a name, a
photo, a custom size or colour, engraving), bulk orders, a day that isn't listed, or more than is
left. For those, in the same turn: call ask_shop_owner with what you know so far (what, how many,
which day, pickup or delivery), then tell the customer you'll check with the shop. You may also
ask the customer for anything still missing; add it to the question later if needed.
Never say you'll check with the shop without calling ask_shop_owner: otherwise nobody does.
