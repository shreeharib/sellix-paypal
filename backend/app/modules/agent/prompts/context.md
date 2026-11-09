---
id: context
version: 5
description: "The per-turn context block: shop, time, menu, stage, draft, quote, open questions."
---
# The shop: {{ shop_name }}
{% if profile %}{{ profile }}{% else %}No shop profile has been written yet.{% endif %}

{% if rules %}# The shop owner's saved answers (use them as written)
{% for rule in rules %}- Q: {{ rule.question }} A: {{ rule.answer }}
{% endfor %}
{% endif -%}
{% if glossary %}# Words customers use
{% for word in glossary %}- {{ word.term }}: {{ word.meaning }}
{% endfor %}
{% endif -%}
# Now
{{ now }} (the shop's local time)

# Today's menu
{% for item in menu -%}
- {{ item.name }} | id {{ item.id }} | price [[price:{{ item.id }}]] | {% if item.available > 0 %}{{ item.available }} left{% else %}sold out{% endif %}
{% else -%}
- Nothing has been added to today's stock yet.
{% endfor %}
{% if facts %}# About this customer
{% for fact in facts %}- {{ fact.key }}: {{ fact.value }}
{% endfor %}
{% endif -%}
{% if coming_up %}# Coming up (open for pre-order on the days shown: take these orders, pass the day as `date` to update_order_draft)
{% for item in coming_up -%}
- {{ item.name }} | id {{ item.id }} | price [[price:{{ item.id }}]] | {{ item.days | join(", ") }}{% if item.order_by %} | last day to order {{ item.order_by }}{% endif %}{% if item.only_on %} | sold only on {{ item.only_on }}{% endif %}
{% endfor %}
{% endif -%}
# This conversation
Stage: {{ stage }}
{% if draft_lines %}Order draft{% if draft_date %} for {{ draft_date }}{% endif %}: {{ draft_lines | join(", ") }}{% if fulfilment %}; {{ fulfilment }}{% endif %}{% if needed_by %}; needed by {{ needed_by }}{% endif %}
{% endif -%}
{% if quote_id %}Open quote: {{ quote_id }}, total [[quote_total]], card {% if quote_shown %}delivered{% else %}not delivered yet{% endif %}
{% endif -%}
{% if open_orders %}Orders waiting for payment: {% for number in open_orders %}#{{ number }}{% if not loop.last %}, {% endif %}{% endfor %}. To cancel one, or to send its payment link again, call the tool with that number (for example 1003).
{% endif -%}
{% if open_questions %}Waiting on the shop owner for: {{ open_questions | join("; ") }}. Don't answer these yourself.
{% endif -%}
{% if window_closing %}Instagram's reply window for this customer closes soon.
{% endif %}
{% if summary %}
# Earlier in this conversation
{{ summary }}
{% endif %}
