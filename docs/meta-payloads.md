# Meta webhook payloads: what actually arrives

Findings from the week-1 spikes (dev plan, section 9). Replace every "to capture" with a real, anonymised example, and save each raw example as a fixture in `backend/tests/fixtures/meta/`.

## How to capture an event

1. Make sure the dev deployment runs with `LOG_WEBHOOK_PAYLOADS=true` (dev only, test accounts only).
2. Do the action, for example reply to the shop's story from a teammate's account.
3. Copy the `meta.webhook.payload` line from the Render logs.
4. Anonymise IDs, names, phone numbers and media links, then save it as `backend/tests/fixtures/meta/<event>.json`.
5. Fill in the table below.

## Instagram

| Event | Status | Fixture | Questions to answer |
|---|---|---|---|
| Text DM | to capture | | |
| Image DM | to capture | | |
| Voice note | to capture | | Format and download method |
| **Story reply** | to capture | | Which fields identify the story? Is there a media link, and how long does it work? Do video stories and highlights look different? |
| Story mention | to capture | | How does it differ from a reply? |
| Shared post or reel | to capture | | |
| Quick-reply tap | to capture | | |
| **Echo** (the merchant replies from the Instagram app) | to capture | | Does it arrive? How do we tell it apart from messages sellix sent (we track our sent message IDs)? |
| Message deleted (unsend) | to capture | | |

## WhatsApp

| Event | Status | Fixture | Questions to answer |
|---|---|---|---|
| Text | to capture | | |
| Image, voice note, location | to capture | | |
| Button or list reply | to capture | | |
| **Echo from the WhatsApp Business app** (coexistence) | to capture | | Does it arrive for coexistence numbers? |
| Status reply | to capture | | Is the status referenced? |
