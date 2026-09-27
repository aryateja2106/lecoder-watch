-- Lecoder cloud account plane v1 — METADATA ONLY.
-- Terminal content, prompts, and agent output never leave the user's machines
-- (local-first mesh is the product; this database is the account/visibility plane
-- so a user can sign in from any device and see their fleet, sessions, and usage).

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);
create table public.nodes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  platform text,
  app_version text,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  unique (user_id, name)
);
create table public.agent_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  node_id uuid references public.nodes (id) on delete set null,
  agent text not null,
  title text,
  -- canonical 4-value status set from the agent-native-cli spec
  status text not null default 'running'
    check (status in ('running', 'waiting-needs-you', 'done', 'error')),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  last_event_at timestamptz
);
create index agent_sessions_user_started_idx
  on public.agent_sessions (user_id, started_at desc);
create table public.usage_daily (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  model text not null,
  tokens_in bigint not null default 0,
  tokens_out bigint not null default 0,
  cost_usd numeric(12, 6) not null default 0,
  primary key (user_id, day, model)
);
alter table public.profiles enable row level security;
alter table public.nodes enable row level security;
alter table public.agent_sessions enable row level security;
alter table public.usage_daily enable row level security;
create policy "own profile" on public.profiles
  for all using (id = auth.uid()) with check (id = auth.uid());
create policy "own nodes" on public.nodes
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own sessions" on public.agent_sessions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own usage" on public.usage_daily
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id);
  return new;
end;
$$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
