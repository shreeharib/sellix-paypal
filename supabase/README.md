# Database (Supabase Postgres)

Migrations and demo seed data. Rules: [docs/dev-plan.md](../docs/dev-plan.md), section 8.

## Setup (first task for the commerce owner)

Install the [Supabase CLI](https://supabase.com/docs/guides/cli), then from the repo root:

```bash
supabase init        # creates supabase/config.toml (commit it)
supabase start       # runs Postgres, auth and realtime locally in Docker
```

## Rules

- Create every schema change with `supabase migration new <name>` and commit the new file.
- **Never edit a migration that's already merged.** Fix it with a new migration.
- Every business table has a `merchant_id` column and row-level security.
- Money is stored as integer minor units (paise or cents) with a currency code. Times are stored in UTC.
- `seed.sql` holds the demo bakery: catalog, stories, and 6–8 weeks of realistic orders.
