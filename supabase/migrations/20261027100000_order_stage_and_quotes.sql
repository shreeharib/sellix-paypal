-- Code, not the model, tracks where each chat is in the order flow, and an order can only be
-- placed from a saved quote the customer has seen and answered (agent improvement plan 1.4).

-- The prices and total code worked out for a customer. One order at most per quote.
create table quotes (
    id uuid primary key default gen_random_uuid(),
    merchant_id uuid not null references merchants(id) on delete cascade,
    conversation_id uuid not null references conversations(id) on delete cascade,
    -- [{"variant_id", "label", "product", "variant", "unit_price_minor", "quantity"}]
    lines jsonb not null,
    currency text not null,
    total_minor bigint not null check (total_minor >= 0),
    fulfilment text check (fulfilment in ('pickup', 'delivery')),
    delivery_address text,
    needed_by text,
    notes text,
    status text not null default 'open' check (status in ('open', 'superseded', 'placed')),
    order_id uuid unique references orders(id) on delete set null,
    created_at timestamptz not null default now()
);
create index quotes_conversation_idx on quotes (conversation_id, created_at desc);
alter table quotes enable row level security;

alter table conversations
    add column order_stage text not null default 'browsing'
        check (order_stage in (
            'browsing', 'collecting_details', 'awaiting_confirmation', 'payment_pending'
        )),
    -- What the customer has asked for so far, as the agent last gave it.
    add column order_draft jsonb,
    add column current_quote_id uuid references quotes(id) on delete set null,
    add column current_order_id uuid references orders(id) on delete set null;
