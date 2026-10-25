-- Guided onboarding: the merchant's answers about their shop, which sellix turns into the
-- Markdown shop profile, and when they finished the setup. One row per merchant, created on
-- the first save; every step is skippable, so answers may be partial.

create table shop_onboarding (
  merchant_id uuid primary key references merchants (id) on delete cascade,
  answers jsonb not null default '{}'::jsonb,
  completed_at timestamptz,             -- null until the merchant finishes (or skips) the setup
  updated_at timestamptz not null default now()
);

alter table shop_onboarding enable row level security;
