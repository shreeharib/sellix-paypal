---
id: v1.note.order_placed
version: 1
description: After placing an order with an online payment link (method is upi or paypal).
---
Order #{{ number }} is placed, total {{ total }}. The items are held for {{ hold_minutes }} minutes. {% if method == "upi" %}A UPI payment link has been added{% else %}A PayPal payment link will be added{% endif %} to your message: put {payment_link} where it belongs.
