# supabase/migrations/ — the database table definitions, one file per change, applied in date order

**Read first:** `20260922100000_feedback.sql` (pattern to copy: grants, then policies), `20260824120000_telemetry_events.sql` (insert-only for the daemon), `../AGENTS.md`
**Surface:** data
**Serialized (one agent at a time):** the whole folder — parallel migrations produce an apply order nobody reviewed
**Prove a change:** no dedicated check — add `scripts/check-supabase-schema.sh`. Today: `supabase db reset` on the local stack, then `sh scripts/check-published.sh` after a human applies it to the hosted project
**Traps:**
- Never edit an applied migration; add a new timestamped file. Which are applied on the hosted project is unverified.
- Only `feedback` (`iOS/LeSearchCloud.swift:117`, `scripts/feedback-to-issues.ts:171`) and `telemetry_events` (`install/payload/meshd/telemetry.ts:103`) have callers; `profiles`, `nodes`, `agent_sessions`, `usage_daily`, `api_keys` and the resume columns have none, and `20260712000000_api_keys.sql:2` cites a "key-auth edge function" that does not exist.
- Every new public table: RLS on, plus explicit `revoke`/`grant` (`20260922100000_feedback.sql:51-55`); anon never gets `select` on user data.
**SDLC stage:** Design, Deploy — the data contract, shipped by hand (see [docs/sdlc/2-design.html](../../docs/sdlc/2-design.html), [docs/sdlc/5-ship.html](../../docs/sdlc/5-ship.html))
**Map:** see the file list above (5 migrations)
