# supabase/ — the one hosted database: it receives "Report a problem" messages from the app and one anonymous daily usage ping per installed daemon

**Read first:** `supabase/migrations/20260922100000_feedback.sql` (live feedback contract + privacy rules), `install/payload/meshd/telemetry.ts` (heartbeat writer), `web/privacy.html` (the public promise these tables keep)
**Surface:** data
**Serialized (one agent at a time):** `supabase/config.toml` (remote auth: `site_url` `:154`, redirects `:156`) and any new migration (timestamp order = apply order)
**Prove a change:** `sh scripts/check-published.sh` (anon cannot read feedback, `:234-238`; needs network + service-role env); `sh scripts/check-feedback-cloud.sh`; `sh scripts/check-feedback-pipeline.sh`. Schema: no dedicated check — add `scripts/check-supabase-schema.sh` (local `supabase start` + `supabase db reset`, assert anon grants). Never touch the hosted project without Arya
**Traps:**
- Hosted project ref lives in client code (`iOS/LeSearchCloud.swift:27`, `install/payload/meshd/telemetry.ts:22`); `config.toml:5` `project_id` is only a local name. Link state unverified.
- `config.toml:65` seeds from `./seed.sql`, which does not exist.
- Grants and RLS (row-level security) must both say insert-only (`migrations/20260922100000_feedback.sql:51-63`).
- Telemetry columns must match `web/privacy.html` and `telemetry.ts` (AGENTS.md design principle 2).
- Never print or commit the service-role key; only the feedback worker holds it (`20260922100000_feedback.sql:11-12`).
**SDLC stage:** Deploy, Maintain — the only cloud piece; it turns user feedback into GitHub issues (see [docs/sdlc/5-ship.html](../docs/sdlc/5-ship.html))
**Map:** 9 tracked files; run `git ls-files supabase` to list them; migrations in `supabase/migrations/AGENTS.md`
