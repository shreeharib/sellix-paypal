-- Orders, order items, the order audit trail, and payments. Also lets conversations hold
-- internal "system" notes (e.g. "payment received") that the agent turns into a message.

create table orders (
  id uuid primary key default gen_random_uuid(),
  number bigint generated always as identity (start with 1001) unique,  -- shown to customers
  merchant_id uuid not null references merchants (id) on delete cascade,
  customer_id uuid not null references customers (id) on delete cascade,
  conversation_id uuid references conversations (id) on delete set null,
  status text not null
    check (status in ('awaiting_payment', 'paid', 'expired', 'cancelled', 'completed', 'refunded')),
  business_date date not null,          -- the stock day the items are held against
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  total_minor integer not null check (total_minor >= 0),
  fulfilment text check (fulfilment in ('pickup', 'delivery')),
  delivery_address text,
  needed_by text,                       -- as the customer said it, e.g. "today evening"
  notes text,                           -- e.g. the message on a cake
  hold_expires_at timestamptz,          -- unpaid holds are released after this
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index orders_merchant_idx on orders (merchant_id, created_at desc);
create index orders_awaiting_payment_idx on orders (hold_expires_at)
  where status = 'awaiting_payment';

create table order_items (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants (id) on delete cascade,
  order_id uuid not null references orders (id) on delete cascade,
  variant_id uuid not null references product_variants (id),
  product_name text not null,           -- names and price as sold, kept even if the catalog changes
  variant_name text,
  unit_price_minor integer not null check (unit_price_minor >= 0),
  quantity integer not null check (quantity > 0)
);
create index order_items_order_idx on order_items (order_id);

create table order_events (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants (id) on delete cascade,
  order_id uuid not null references orders (id) on delete cascade,
  event text not null,                  -- placed, paid, expired, stock_shortfall, ...
  from_status text,
  to_status text,
  actor text not null check (actor in ('agent', 'customer', 'merchant', 'system', 'paypal')),
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index order_events_order_idx on order_events (order_id, created_at);

create table payments (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants (id) on delete cascade,
  order_id uuid not null references orders (id) on delete cascade,
  provider text not null check (provider in ('paypal')),
  provider_order_id text not null,      -- PayPal order ID
  provider_capture_id text,             -- PayPal capture ID once paid
  status text not null
    check (status in ('created', 'approved', 'completed', 'denied', 'refunded', 'failed')),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  amount_minor integer not null check (amount_minor >= 0),
  approve_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, provider_order_id)
);
create unique index payments_capture_idx
  on payments (provider, provider_capture_id) where provider_capture_id is not null;
create index payments_order_idx on payments (order_id);

create trigger orders_updated_at before update on orders
  for each row execute function set_updated_at();
create trigger payments_updated_at before update on payments
  for each row execute function set_updated_at();

alter table orders enable row level security;
alter table order_items enable row level security;
alter table order_events enable row level security;
alter table payments enable row level security;

-- Conversations: internal system notes (never sent; the agent tells the customer).
alter table messages drop constraint messages_direction_check;
alter table messages drop constraint messages_sender_check;
alter table messages drop constraint messages_check;
alter table messages add constraint messages_direction_check
  check (direction in ('inbound', 'outbound', 'internal'));
alter table messages add constraint messages_sender_check
  check (sender in ('customer', 'agent', 'merchant', 'system'));
alter table messages add constraint messages_direction_matches_sender check (
  (direction = 'inbound') = (sender = 'customer')
  and (direction = 'internal') = (sender = 'system')
);
