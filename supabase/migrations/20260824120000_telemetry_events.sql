-- telemetry_events: one anonymized daily heartbeat per meshd install.
-- The whole payload is: random install id, version, platform, uptime, coarse
-- numeric feature counters. No commands, no keystrokes, no terminal or screen
-- content, no hostnames. This is exactly the list web/privacy.html promises.
-- Daemons opt out with MESHD_TELEMETRY=off and send nothing at all.

create table public.telemetry_events (
  id             bigint generated always as identity primary key,
  install_id     uuid not null,
  ts             timestamptz not null default now(),
  platform       text not null,
  daemon_version text not null,
  uptime_hours   int,
  counters       jsonb not null default '{}'::jsonb
);

comment on table public.telemetry_events is
  'meshd daily heartbeats: install_id (random uuid, not tied to a person), version, platform, uptime, coarse numeric counters. Nothing else is ever collected; users disable it entirely with MESHD_TELEMETRY=off. See web/privacy.html.';

-- The daemon embeds the public anon key and may only ever append. Reading the
-- data back is for the authenticated dashboard side only — anon gets no select,
-- update or delete policy, so those are denied by RLS default-deny.
alter table public.telemetry_events enable row level security;

create policy telemetry_insert_only
  on public.telemetry_events
  for insert
  to anon
  with check (true);
