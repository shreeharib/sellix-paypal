-- Core schema: merchants, channel connections, customers, conversations, messages, catalog,
-- daily stock, shop profiles, escalations, AI usage and the webhook inbox.
--
-- Every business table carries merchant_id. Row-level security is enabled on every table with
-- no policies yet, so Supabase's anon and authenticated API roles see nothing until policies
-- for the merchant app are added. The backend connects as the table owner.

create function set_updated_at() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Merchants -------------------------------------------------------------------------------

create table merchants (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  timezone text not null default 'Asia/Kolkata',
  agent_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Channels --------------------------------------------------------------------------------

create table channel_connections (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants (id) on delete cascade,
  channel text not null check (channel in ('instagram', 'whatsapp')),
  external_account_id text not null,   -- the account ID the channel uses in webhooks
  username text,
  access_token_encrypted text not null, -- Fernet ciphertext; the key lives outside the database
  token_expires_at timestamptz,
  token_refreshed_at timestamptz not null default now(),
  scopes text[] not null default '{}',
  status text not null default 'active' check (status in ('active', 'revoked', 'error')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (channel, external_account_id)
);
create index channel_connections_merchant_idx on channel_connections (merchant_id);

-- Customers, conversations, messages ------------------------------------------------------

create table customers (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants (id) on delete cascade,
  channel text not null check (channel in ('instagram', 'whatsapp', 'webchat')),
  external_id text not null,            -- the customer's ID on the channel (Instagram: IGSID)
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (merchant_id, channel, external_id)
);

create table conversations (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants (id) on delete cascade,
  customer_id uuid not null unique references customers (id) on delete cascade,
  channel_connection_id uuid not null references channel_connections (id) on delete cascade,
  agent_active boolean not null default true,
  agent_paused_reason text
    check (agent_paused_reason in ('merchant_replied', 'merchant_switched_off')),
  last_customer_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (agent_active or agent_paused_reason is not null)
);
create index conversations_merchant_idx on conversations (merchant_id);

create table messages (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants (id) on delete cascade,
  conversation_id uuid not null references conversations (id) on delete cascade,
  direction text not null check (direction in ('inbound', 'outbound')),
  sender text not null check (sender in ('customer', 'agent', 'merchant')),
  external_id text,                     -- the channel's message ID
  body text not null default '',
  metadata jsonb not null default '{}', -- attachments, story reply, detected language
  status text not null check (status in ('received', 'sending', 'sent', 'failed')),
  error text,
  created_at timestamptz not null default now(),
  check ((direction = 'inbound') = (sender = 'customer'))
);
create unique index messages_external_id_idx
  on messages (merchant_id, external_id) where external_id is not null;
create index messages_conversation_idx on messages (conversation_id, created_at);

-- Catalog and daily stock -----------------------------------------------------------------

create table products (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants (id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index products_merchant_name_idx on products (merchant_id, lower(name));

create table product_variants (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants (id) on delete cascade,
  product_id uuid not null references products (id) on delete cascade,
  name text,                            -- null when the product has no variants
  price_minor integer not null check (price_minor >= 0),  -- paise for INR
  currency text not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index product_variants_name_idx
  on product_variants (product_id, lower(coalesce(name, '')));

create table daily_stock (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants (id) on delete cascade,
  variant_id uuid not null references product_variants (id) on delete cascade,
  business_date date not null,
  opening integer not null default 0 check (opening >= 0),
  restocked integer not null default 0 check (restocked >= 0),
  held integer not null default 0 check (held >= 0),
  sold integer not null default 0 check (sold >= 0),
  counter_sales integer not null default 0 check (counter_sales >= 0),
  available integer generated always as
    (opening + restocked - held - sold - counter_sales) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (variant_id, business_date),
  -- Stock never goes negative: what's promised can't exceed what was made.
  check (opening + restocked - held - sold - counter_sales >= 0)
);
create index daily_stock_merchant_date_idx on daily_stock (merchant_id, business_date);

-- Shop profile (Markdown the agent reads), versioned -------------------------------------

create table shop_profiles (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants (id) on delete cascade,
  version integer not null check (version > 0),
  content_md text not null,
  created_at timestamptz not null default now(),
  unique (merchant_id, version)
);

-- Escalations ("Ask me") ------------------------------------------------------------------

create table escalations (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants (id) on delete cascade,
  conversation_id uuid not null references conversations (id) on delete cascade,
  trigger_message_id uuid references messages (id) on delete set null,
  question text not null,
  status text not null default 'open' check (status in ('open', 'answered', 'closed')),
  answer text,
  created_at timestamptz not null default now(),
  answered_at timestamptz
);
create index escalations_open_idx on escalations (merchant_id, created_at) where status = 'open';

-- AI usage (cost meter) -------------------------------------------------------------------

create table ai_usage (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid references merchants (id) on delete set null,
  conversation_id uuid references conversations (id) on delete set null,
  purpose text not null,                -- e.g. 'customer_reply'
  model text not null,
  input_tokens integer,
  output_tokens integer,
  latency_ms integer not null,
  succeeded boolean not null,
  created_at timestamptz not null default now()
);
create index ai_usage_merchant_idx on ai_usage (merchant_id, created_at);

-- Webhook inbox ---------------------------------------------------------------------------
-- Raw payloads contain customer messages: keep them only as long as needed (retention job).

create table webhook_events (
  id uuid primary key default gen_random_uuid(),
  source text not null check (source in ('meta', 'paypal')),
  dedupe_key text not null,             -- SHA-256 of the raw body; providers retry identically
  payload jsonb not null,
  status text not null default 'pending' check (status in ('pending', 'processed', 'failed')),
  attempts integer not null default 0,
  error text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (source, dedupe_key)
);
create index webhook_events_pending_idx on webhook_events (received_at) where status = 'pending';

-- updated_at triggers ---------------------------------------------------------------------

create trigger merchants_updated_at before update on merchants
  for each row execute function set_updated_at();
create trigger channel_connections_updated_at before update on channel_connections
  for each row execute function set_updated_at();
create trigger customers_updated_at before update on customers
  for each row execute function set_updated_at();
create trigger conversations_updated_at before update on conversations
  for each row execute function set_updated_at();
create trigger products_updated_at before update on products
  for each row execute function set_updated_at();
create trigger product_variants_updated_at before update on product_variants
  for each row execute function set_updated_at();
create trigger daily_stock_updated_at before update on daily_stock
  for each row execute function set_updated_at();

-- Row-level security ----------------------------------------------------------------------

alter table merchants enable row level security;
alter table channel_connections enable row level security;
alter table customers enable row level security;
alter table conversations enable row level security;
alter table messages enable row level security;
alter table products enable row level security;
alter table product_variants enable row level security;
alter table daily_stock enable row level security;
alter table shop_profiles enable row level security;
alter table escalations enable row level security;
alter table ai_usage enable row level security;
alter table webhook_events enable row level security;
