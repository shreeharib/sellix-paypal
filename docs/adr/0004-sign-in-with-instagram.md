# 0004: Sign in with Instagram, with our own sessions

**Status:** accepted · 25 Oct 2026 (replaces the plan to use Supabase Auth)

## Context

Merchants must never create Meta developer accounts or copy tokens: sellix has one Meta app, and each merchant connects through Instagram's own login. That login already proves who the merchant is, so a second login system (Supabase Auth) would only add a step and a dependency.

## Decision

- **"Continue with Instagram" is the app's login.** One tap signs the merchant in, creates their shop on first login, stores the Instagram token encrypted, and subscribes the account to our webhook.
- **The app starts the login with PKCE.** It sends a code challenge; after Instagram, the backend redirects back to the app (`sellix://auth/callback`, or `auth.html` on the web) with a one-time code, which only the app holding the verifier can redeem.
- **sellix issues its own sessions:** 15-minute signed access tokens and 60-day refresh tokens that rotate on every use and are stored only as hashes. Reusing a rotated-out refresh token revokes the session.
- **Accounts are modelled for growth:** users, login identities (Instagram today; phone or email later) and shop members (owner, staff).

## Consequences

- No Supabase Auth; the database can be any Postgres host. Firebase covers push, crash reports and web hosting, and possibly a phone-code backup login later.
- Until Meta App Review grants Advanced Access, only accounts with a role on the Meta app can sign in. That's fine for the hackathon and design partners.
- A merchant whose Instagram account is disabled can't sign in. A backup login (phone or email code) is needed before wide launch, and for staff.
