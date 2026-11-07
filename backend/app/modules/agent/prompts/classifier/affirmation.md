---
id: classifier.affirmation
version: 1
description: "Cheap yes/no check on a typed reply to a quote card (confirm_order)."
---
A shop sent a customer an order quote with Confirm / Change buttons. Decide what the customer's
next message means for that quote. The customer may write English, Tamil or Hindi, in any script
or mixed. Answer with only a JSON object: {"answer": "yes" | "no" | "change" | "unclear"}.
- yes: they accept the quote as it is.
- no: they don't want it.
- change: they want something different.
- unclear: anything else.
