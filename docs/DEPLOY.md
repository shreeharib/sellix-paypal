# Putting sellix online (for the phone test and for real shops)

Who this is for: whoever sets up the server. The phone app needs a sellix backend on the public
internet with an `https://` address. This laptop can't serve that: the company network blocks
Instagram, and Razorpay and Meta can't call back into it. Do these steps from a machine and accounts
that are allowed to (nothing here is uploaded from this laptop).

The backend is one Docker image (`backend/Dockerfile`) run as two processes: the **API** and the
**job worker**. They share one Postgres database.

## 1. A Postgres database (Postgres 15 or newer)

Supabase, Neon, Render Postgres or any managed Postgres works. Use the **direct** or
**session-pooler** connection string (not a transaction pooler: the job queue uses LISTEN/NOTIFY).

Apply every file in `supabase/migrations/`, **in name order**. There is no migration tracker, so
apply each file once, and on later deploys apply only the new ones:

```bash
for f in supabase/migrations/*.sql; do psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$f"; done
```

## 2. Secrets and settings

Make the three random secrets once (`python -m app.cli generate-secrets` from `backend/`), and
keep them only in the host's secret settings. Never put them in the repo.

| Setting | Value |
|---|---|
| `APP_ENV` | `prod` |
| `PUBLIC_BASE_URL` | The API's https address, e.g. `https://sellix-api.onrender.com` |
| `DATABASE_URL` | From step 1 |
| `TOKEN_ENCRYPTION_KEYS`, `OAUTH_STATE_SECRET`, `SESSION_SIGNING_KEY` | From `generate-secrets` (encrypts Razorpay and Instagram secrets; signs sign-ins) |
| `APP_REDIRECT_URIS` | `sellix://auth/callback` (the phone app's return address) |
| `INSTAGRAM_APP_ID`, `INSTAGRAM_APP_SECRET`, `META_APP_SECRET`, `META_VERIFY_TOKEN` | From the Meta app (step 4) |
| `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL` | The AI model (any OpenAI-compatible API) |
| `LLM_PRICES` | So each shop's daily AI budget can trip, e.g. `mymodel=0.4/1.6` (dollars per million tokens) |
| `RUN_WORKER_IN_PROCESS` | `false` on the API when a separate worker runs (recommended) |
| `LOG_WEBHOOK_PAYLOADS` | `false` (true would log customers' messages) |

Razorpay needs **no server keys**: each shop connects its own account in the app (see
[razorpay-setup.md](razorpay-setup.md)). `RAZORPAY_KEY_ID` / `RAZORPAY_KEY_SECRET` are only for a
server that runs a single shop (`RAZORPAY_SHARED_ACCOUNT_IN_PROD=true`).

Rotate the LLM, Instagram and old PayPal secrets that were pasted into a chat once (HANDOFF section 2) before real use.

## 3. Run the API and the worker

- **Render:** `render.yaml` is a blueprint for both. It hasn't been run end to end, so check it on
  the first deploy, and set the secrets in Render's dashboard.
- **Any Docker host:**
  - API: `docker run -p 8000:8000 -e PORT=8000 -e API_WORKERS=2 --env-file prod.env <image>`.
  - Worker: the same image with the command `python -m app.worker`.
  - Put an https proxy in front of the API (Caddy, nginx, or the platform's own).

Check: `https://<your address>/health` answers `{"status":"ok","env":"prod"}`.

## 4. The Meta (Instagram) app

1. In Meta for Developers, open the app. Under Instagram, then API setup with Instagram login, set:
   - OAuth redirect URI: `<PUBLIC_BASE_URL>/oauth/instagram/callback`
   - Webhook callback URL: `<PUBLIC_BASE_URL>/webhooks/meta`, with the verify token `META_VERIFY_TOKEN`
   - Subscribe to `messages` and `messaging_postbacks`.
2. While the app is in development mode, only people with a role on the app (admin, developer,
   tester) can sign in. Add the Instagram account you test with.
3. Before real shops use it, the app needs Meta App Review (advanced access for messaging) and
   business verification. Both ask for these two URLs:
   - privacy policy: `<PUBLIC_BASE_URL>/privacy`
   - data deletion: `<PUBLIC_BASE_URL>/data-deletion`

   Expect days to weeks.

## 5. The phone app

Either build the APK pointing at the server:

```bash
cd frontend/flutter_app
D:\Android\flutter-direct.cmd build apk --release --dart-define=API_BASE_URL=https://<your address>
```

or use any build and set the address in the app: **Sign in → Server → enter the https address →
Check → Save**.

The release build is signed with the key in `android/key.properties`. Back up that file and
`D:\Android\keys\sellix-release.jks` somewhere safe: every future update must be signed with the
same key, or phones have to uninstall the app first.

## 6. First shop

1. Install the APK and sign in with Instagram. The shop starts with the assistant **off**.
2. Go through onboarding: shop type, profile, stock, payments (connect Razorpay test keys).
   Finishing onboarding switches the assistant on.
3. From another Instagram account, DM the shop. Order something and pay on Razorpay's test page
   ([razorpay-setup.md](razorpay-setup.md) section 6). The order turns paid in the app.
