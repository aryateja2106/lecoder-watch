-- feedback: what a user typed into "Report a problem" in the published app, plus the
-- facts the app attaches by itself (version, build, device, OS). One row per report.
--
-- Who can do what (least privilege, all explicit — "expose new tables automatically"
-- stays OFF on this project):
--   anon           INSERT only, and only rows with no user_id. The app ships the public
--                  anon key; a holder of that key can file a report and nothing else —
--                  no reading anyone's reports, no editing, no deleting. Proven by
--                  scripts/check-published.sh: an anon GET answers 401/403.
--   authenticated  INSERT only, user_id must be its own uid (or null).
--   service_role   everything; only the feedback worker (scripts/feedback-to-issues.ts)
--                  holds it, on the machine that runs the pipeline.
-- Nobody can read a report back through the API except the worker. There is nothing
-- for the app to read: the answer to a report is a GitHub issue, not a row.
--
-- Privacy: contact_email stays in this table and is never copied into the issue; the
-- worker hashes it (sha256, first 12 hex) before anything leaves Supabase. The bundle
-- column is already redacted on the phone (FeedbackBundle + the daemon's secret
-- patterns) and the worker runs the daemon's redactor over every string once more.

create table public.feedback (
  id             uuid primary key default gen_random_uuid(),
  created_at     timestamptz not null default now(),
  kind           text not null check (kind in ('bug', 'idea', 'other')),
  title          text not null check (char_length(title) between 1 and 200),
  body           text not null default '' check (char_length(body) <= 20000),
  contact_email  text check (contact_email is null or char_length(contact_email) <= 320),
  user_id        uuid references auth.users (id) on delete set null,
  app_version    text not null check (char_length(app_version) <= 40),
  app_build      text not null check (char_length(app_build) <= 40),
  device         text not null check (char_length(device) <= 80),
  os             text not null check (char_length(os) <= 80),
  -- storage object path in bucket feedback-attachments; screenshot or screen recording,
  -- attached only when the user picked one (opt-in, never captured by the app itself).
  attachment     text check (attachment is null or attachment ~ '^[0-9a-f-]{36}\.(png|jpg|jpeg|mov|mp4)$'),
  bundle         text check (bundle is null or char_length(bundle) <= 200000),
  source         text not null default 'app' check (source in ('app', 'web', 'cli')),
  -- filled by the worker
  issue_url      text,
  issue_status   text check (issue_status is null or issue_status in ('filed', 'duplicate', 'skipped')),
  processed_at   timestamptz
);

comment on table public.feedback is
  'In-app "Report a problem" rows. anon/authenticated: insert only. Read by the feedback worker (service_role) which files deduped GitHub issues labeled from-users. contact_email never leaves this table unhashed.';

create index feedback_unprocessed on public.feedback (created_at) where processed_at is null;

alter table public.feedback enable row level security;

-- Grants first (the default privileges on public would otherwise give anon everything),
-- then policies. Both layers must say "insert only".
revoke all on public.feedback from anon, authenticated;
grant insert on public.feedback to anon, authenticated;
revoke all on public.feedback from public;

create policy feedback_insert_anon
  on public.feedback for insert to anon
  with check (user_id is null and source = 'app');

create policy feedback_insert_own
  on public.feedback for insert to authenticated
  with check (user_id is null or user_id = auth.uid());

-- Attachments: a private bucket the app may only write into. Object names are the
-- feedback row's id plus an extension, so a report and its file share one key.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('feedback-attachments', 'feedback-attachments', false, 52428800,
        array['image/png', 'image/jpeg', 'video/quicktime', 'video/mp4'])
on conflict (id) do nothing;

create policy feedback_attachments_insert
  on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'feedback-attachments'
              and name ~ '^[0-9a-f-]{36}\.(png|jpg|jpeg|mov|mp4)$');
-- No select/update/delete policy on the bucket for anon or authenticated: the worker
-- (service_role) mints a short-lived signed URL when it files the issue.
