-- Lecoder API keys — long-lived credentials a signed-out CLI/device exchanges
-- for a Supabase session (see the key-auth edge function). Only the SHA-256
-- hash of a key is stored; the plaintext key is shown once at creation time.

create table public.api_keys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  key_prefix text not null,
  key_hash text not null unique,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);
create index api_keys_user_idx on public.api_keys (user_id);
create index api_keys_key_hash_idx on public.api_keys (key_hash);
alter table public.api_keys enable row level security;
create policy "own api_keys select" on public.api_keys
  for select using (auth.uid() = user_id);
create policy "own api_keys insert" on public.api_keys
  for insert with check (auth.uid() = user_id);
create policy "own api_keys update" on public.api_keys
  for update using (auth.uid() = user_id);
create policy "own api_keys delete" on public.api_keys
  for delete using (auth.uid() = user_id);
