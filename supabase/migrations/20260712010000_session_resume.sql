-- Agent-agnostic session-resume persistence for the account plane.
-- METADATA ONLY: a provider-native session id, an optional resume argv, and a
-- resumable flag so a user can see (and a device can act on) which sessions can
-- be resumed. Transcript content itself never leaves the user's machines, so no
-- transcript_path column is mirrored to the cloud.
-- The existing `agent` column already carries the agent type — do not add one.

alter table public.agent_sessions add column if not exists native_session_id text;
alter table public.agent_sessions add column if not exists resume_argv jsonb;
alter table public.agent_sessions add column if not exists resumable boolean not null default false;
