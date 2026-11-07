---
id: v1.note.quote
version: 1
---
Quote: {% for line in lines %}{{ line.quantity }} x {{ line.label }} at {{ line.unit_price }} = {{ line.subtotal }}{% if not loop.last %}, {% endif %}{% endfor %}. Total {{ total }}. Everything is available. Summarise this for the customer, with the total, and ask them to confirm.
