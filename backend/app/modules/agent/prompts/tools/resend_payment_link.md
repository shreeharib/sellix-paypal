---
id: tool.resend_payment_link
version: 2
---
Send the payment link for the customer's unpaid order again. Pass the order number from "Orders waiting for payment" as `order` (for example 1003). While a link is still open, it is the same link. If the last payment failed, a new link is made, but only after a short wait and a limited number of times; the tool tells the customer when it can't, so don't promise a new link yourself.
