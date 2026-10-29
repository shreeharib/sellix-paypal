---
id: history.attachments
version: 1
description: "How a customer's story reply or attachments appear in the model's history."
---
{% if story %}[Replied to one of the shop's stories: use lookup_story] {% endif %}{% if attachments %}[Sent: {{ attachments | join(", ") }}] {% endif %}{{ text }}
