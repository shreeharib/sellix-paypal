---
id: classifier.affirmation
version: 2
description: "Cheap check on a typed reply to a quote card (confirm_order): does it ask to place the order?"
---
A shop sent a customer an order quote with Confirm / Change buttons. Decide what the customer's
next message means for that quote. The customer may write English, Tamil or Hindi, in any script
or mixed. Answer with only a JSON object: {"answer": "yes" | "no" | "change" | "unclear"}.
- yes: they clearly ask to place the order as quoted, in words like "confirm", "place the
  order", "book it", "confirm pannunga", "order kar do".
- no: they don't want it.
- change: they want something different.
- unclear: anything else, including a plain acknowledgement ("ok", "okay", "sure", "fine",
  "seri", "haan", "theek hai", a thumbs-up), a question, or "wait" / "later". These do not place
  an order.
