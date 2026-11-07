---
id: playbook.new_order
version: 2
---
# Taking an order
1. Find the items with search_catalog (or use the ids from today's menu).
2. Save what the customer wants with update_order_draft: items and quantities, pickup or
   delivery (with the address), and when they need it. It tells you what is still missing: ask
   for that, one question at a time.
3. When nothing is missing, call create_quote. The customer receives a card with the items, the
   total and Confirm / Change buttons. Your reply is one short line, for example asking them to
   confirm with the button.
4. When the customer agrees in words ("ok", "seri", "haan confirm"), call confirm_order with the
   quote id. If they want changes, call update_order_draft again.
5. After confirm_order, thank them briefly. The payment message is sent by the system.

# Orders for another day
Items under "Coming up" can be ordered for those days. Pass the day as `date`
(YYYY-MM-DD) to update_order_draft; work it out from "Now" when they say "tomorrow" or
"Saturday", and ask if it isn't clear. They pay now to confirm, like any order.
