# 0003: Webhook inbox and a job queue in Postgres

**Status:** accepted · 25 Oct 2026

## Context

Meta and PayPal expect a fast answer to every webhook and retry when they don't get one. Processing a message (storing it, calling the model, replying) takes seconds and can fail halfway. Work done in memory is lost on a restart or deploy. Running Redis or a separate queue service costs money that small merchants' prices can't carry.

## Decision

- Every webhook is verified, stored once in `webhook_events` (deduplicated by a hash of the raw body), and answered immediately. A job then processes it.
- Jobs run on **procrastinate**, a queue stored in the same Postgres database, with retries, locks and periodic jobs. Its schema is a normal migration (`supabase/migrations/..._procrastinate_3_10.sql`); upgrades add its migration files.
- Each chat gets at most one queued agent turn (`queueing_lock`), turns for a chat run one at a time (`lock`), and a turn waits a few seconds so a burst of messages gets one reply.
- A job is queued only after the data it needs is committed. A periodic job re-queues chats left unanswered, covering the rare case where queueing fails after a commit.
- The worker runs inside the API process by default (`RUN_WORKER_IN_PROCESS`), and as its own process (`python -m app.worker`) when traffic needs it.

## Consequences

- Nothing is lost on restarts or deploys; retries from Meta or PayPal are harmless.
- One database to run and back up. The queue's tables have row-level security, so they stay hidden if the database is ever exposed through an API layer such as Supabase's.
- The database connection must support LISTEN/NOTIFY: use a direct (or session-pooled) connection, not a transaction pooler.
