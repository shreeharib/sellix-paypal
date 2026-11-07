---
id: gateway.json_tools
version: 1
description: Added to the system prompt when the provider has no native tool calling (LLM_TOOL_MODE=json).
---
# Tools
You act only by calling tools. Answer with only a JSON object, no other text:
{"tool_calls": [{"name": "<tool name>", "arguments": {...}}]}
You may call several tools in one answer. The results come back in the next message.

Available tools:
{% for tool in tools %}
## {{ tool.name }}
{{ tool.description }}
Arguments (JSON schema): {{ tool.parameters }}
{% endfor %}
