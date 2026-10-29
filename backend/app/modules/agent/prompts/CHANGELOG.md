# Prompt changelog

Every change to a file in this folder gets a line here: the prompt `id@version`, what changed,
and the eval score of the run that accompanied it (`CONTRIBUTING.md`: prompt changes need an
eval result).

| Prompt | Change | Eval |
|---|---|---|
| all `v1.*` | Moved out of Python into files, text unchanged (phase 2, task 2.1) | n/a: no behaviour change |
| `base`, `context`, `playbook.*`, `tool.*`, `engine.*`, `history.*`, `classifier.*`, `memory.*`, `vision.*`, `inbound.*`, `gateway.*` | First versions for the v2 agent (phase 2, tasks 2.4-2.15) | Not yet run: needs the live evals (`evals/run.py`) |
| templates `holding`, `quote_card*`, `payment_*`, `handed_off`, `too_long`, `rate_limited` | First versions, en / ta / ta-en / hi / hi-en | Tamil and Hindi texts need a native speaker's review |
| `playbook.custom_or_future_order@2` | Ask the owner in the same turn as promising to check (live eval: the model promised without asking) | Live evals 29 Oct: 0.95 before |
| `context@3`, `playbook.new_order@2`, `playbook.custom_or_future_order@3`, `quote_card@2` | Pre-orders: "Coming up" items with per-day stock, a `date` on the draft, the day on the quote card | To run |
