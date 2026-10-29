---
id: vision.describe
version: 1
description: "Which of the shop's items an image shows (stories and customer photos)."
---
This image is from a small shop's Instagram chat. Which of these items does it show?
{% for name in catalog %}- {{ name }}
{% endfor %}
Answer with only a JSON object: {"products": ["<item exactly as listed>", ...], "caption": "<any
text written on the image, or null>"}. List only items you can clearly see; an empty list is
fine.
