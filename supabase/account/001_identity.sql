-- Identity only. Never store mesh tokens, tailnet addresses, or host lists.
-- Do not run this on the telemetry project.
-- These tables hold a username, a user-typed device label, a platform enum,
-- a device public key, and sealed mailbox ciphertext. The secret that opens
-- a machine is not a column. Deleting the auth user cascades profiles,
-- devices, and mailbox rows.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null,
  created_at timestamptz not null default now(),
  constraint profiles_username_unique unique (username),
  constraint profiles_username_shape check (username ~ '^[a-z0-9_]{3,32}$')
);

alter table public.profiles enable row level security;

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  label text not null,
  platform text not null,
  public_key text not null,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint devices_user_public_key unique (user_id, public_key),
  constraint devices_label_len check (char_length(label) between 1 and 64),
  constraint devices_platform_kind check (platform in ('web', 'ios', 'watchos', 'macos', 'linux')),
  constraint devices_public_key_len check (char_length(public_key) between 1 and 512)
);

alter table public.devices enable row level security;

create table public.mailbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  recipient_device_id uuid not null references public.devices (id) on delete cascade,
  sender_device_id uuid not null references public.devices (id) on delete cascade,
  ciphertext text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  constraint mailbox_ciphertext_len check (char_length(ciphertext) between 1 and 16384)
);

alter table public.mailbox enable row level security;

create policy profiles_select
  on public.profiles
  for select
  to authenticated
  using (id = auth.uid());

create policy profiles_insert
  on public.profiles
  for insert
  to authenticated
  with check (id = auth.uid());

create policy profiles_update
  on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy profiles_delete
  on public.profiles
  for delete
  to authenticated
  using (id = auth.uid());

create policy devices_select
  on public.devices
  for select
  to authenticated
  using (auth.uid() = user_id);

create policy devices_insert
  on public.devices
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy devices_update
  on public.devices
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy devices_delete
  on public.devices
  for delete
  to authenticated
  using (auth.uid() = user_id);

create policy mailbox_select
  on public.mailbox
  for select
  to authenticated
  using (auth.uid() = user_id);

create policy mailbox_insert
  on public.mailbox
  for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.devices
      where id = recipient_device_id
        and user_id = auth.uid()
    )
    and exists (
      select 1 from public.devices
      where id = sender_device_id
        and user_id = auth.uid()
    )
  );

create policy mailbox_delete
  on public.mailbox
  for delete
  to authenticated
  using (auth.uid() = user_id);

revoke all on table public.profiles from public;
revoke all on table public.profiles from anon;
revoke all on table public.devices from public;
revoke all on table public.devices from anon;
revoke all on table public.mailbox from public;
revoke all on table public.mailbox from anon;

grant select, insert, update, delete on table public.profiles to authenticated;
grant select, insert, update, delete on table public.devices to authenticated;
grant select, insert, delete on table public.mailbox to authenticated;
