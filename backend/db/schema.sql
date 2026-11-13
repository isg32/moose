-- Moose: the server only knows who is paired with whom and holds sealed
-- mail until the other phone takes it. Every body is ciphertext.
-- Realtime reads `mailbox`, so it keeps a primary key and no RLS; the API
-- authorises every query itself (one API, no Data API).

create table if not exists couples (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create table if not exists members (
  user_id text primary key,                 -- neon_auth user id (JWT sub)
  name text not null default '',
  pubkey text not null default '',          -- X25519, base64
  couple_id uuid references couples(id) on delete set null,
  joined_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists members_couple on members(couple_id);

create table if not exists invites (
  code text primary key,
  creator text not null references members(user_id) on delete cascade,
  expires_at timestamptz not null
);

create table if not exists mailbox (
  id uuid primary key,                      -- chosen by the sender
  couple_id uuid not null references couples(id) on delete cascade,
  sender text not null,
  recipient text not null,
  kind text not null,                       -- msg, receipt, typing, moment, theme, doodle, rtc
  body text not null,                       -- sealed box, base64
  created_at timestamptz not null default now()
);
create index if not exists mailbox_recipient on mailbox(recipient, created_at);
