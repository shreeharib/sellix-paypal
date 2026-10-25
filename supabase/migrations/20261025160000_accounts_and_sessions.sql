-- App accounts: users, their login identities, shop membership, sessions and one-time login
-- codes. "Continue with Instagram" creates these on a merchant's first login. Phone or email
-- logins and staff accounts later add identities and members without schema changes.

create table users (
  id uuid primary key default gen_random_uuid(),
  display_name text,
  created_at timestamptz not null default now(),
  last_login_at timestamptz
);

create table user_identities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users (id) on delete cascade,
  provider text not null check (provider in ('instagram', 'phone', 'email')),
  subject text not null,                -- e.g. the Instagram professional account ID
  created_at timestamptz not null default now(),
  unique (provider, subject)
);
create index user_identities_user_idx on user_identities (user_id);

create table merchant_members (
  merchant_id uuid not null references merchants (id) on delete cascade,
  user_id uuid not null references users (id) on delete cascade,
  role text not null default 'owner' check (role in ('owner', 'staff')),
  created_at timestamptz not null default now(),
  primary key (merchant_id, user_id)
);
create index merchant_members_user_idx on merchant_members (user_id);

create table sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users (id) on delete cascade,
  refresh_token_hash text not null unique,  -- SHA-256; refresh tokens themselves are never stored
  previous_refresh_token_hash text,         -- the rotated-out token, to detect its reuse
  user_agent text,
  created_at timestamptz not null default now(),
  last_used_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz
);
create index sessions_user_idx on sessions (user_id);
create index sessions_previous_token_idx
  on sessions (previous_refresh_token_hash) where previous_refresh_token_hash is not null;

create table login_codes (
  code_hash text primary key,           -- SHA-256 of the one-time code
  user_id uuid not null references users (id) on delete cascade,
  code_challenge text not null,         -- PKCE (S256) challenge sent by the app
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

alter table users enable row level security;
alter table user_identities enable row level security;
alter table merchant_members enable row level security;
alter table sessions enable row level security;
alter table login_codes enable row level security;
