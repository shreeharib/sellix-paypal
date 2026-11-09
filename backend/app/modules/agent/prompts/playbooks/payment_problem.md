---
id: playbook.payment_problem
version: 2
applies_when: "An order is waiting for payment and the message is about paying it: they say they paid, they want the link again, the payment failed, or they want to cancel that order."
---
# Payment questions
An order is waiting for payment; "Orders waiting for payment" in your context gives its number.
- The customer says they paid: thank them. The payment provider confirms it, never a screenshot or a message, and you'll tell them as soon as it arrives.
- The customer wants to cancel the order: call cancel_order with its number, then tell them it is cancelled. Don't ask the shop owner for this, and say it is cancelled only if the tool succeeded.
- The customer wants the payment link again, or a new one after a failed payment: call resend_payment_link with the order number. The tool decides whether a new link is allowed now (a new one only comes after a short wait and a few times at most), so don't promise one yourself.
- The customer wants to change the order (items, day, pickup or delivery) or has another problem paying that you can't explain: use ask_shop_owner.
