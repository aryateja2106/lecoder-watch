# meshd native /limits — recipe (2026-07-07, verified live)

Goal: serve Claude/Codex usage limits from meshd WITHOUT the OpenUsage.app dependency (G4 independence).
All findings verified on Aryas-MacBook-Pro; no secret values in this doc — locations/formats only.

## Sources (priority order)

**Claude** (no offline path — surface staleness via `fetchedAt`, don't hide it):
1. `GET https://api.anthropic.com/api/oauth/usage` — authoritative, verified 200.
   Headers: `Authorization: Bearer <oauth access token>`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-code/2.1.69`, JSON accept/content-type.
   Token: Keychain generic password, service **`Claude Code-credentials`** → JSON `claudeAiOauth.accessToken`.
   Read via shell-out `/usr/bin/security find-generic-password -s 'Claude Code-credentials' -w` (works non-interactively from the meshd LaunchAgent — empirically verified; a native keychain lib would trip code-signature ACL prompts, so keep the shell-out).
   No `~/.claude/.credentials.json` on this machine — Keychain is the only Claude source.
2. OpenUsage live `http://127.0.0.1:6736/v1/usage` (if running).
3. OpenUsage cache `~/Library/Application Support/com.sunstory.openusage/usage-api-cache.json` (was 7 days stale — last resort only).

Bucket map: `five_hour`→Session (windowMs 18_000_000), `seven_day`→Weekly (604_800_000), `seven_day_opus`→Opus, `seven_day_sonnet`→Sonnet, `seven_day_omelette`→Claude Design. `usedPct = bucket.utilization` (0–100 float), `resetsAt = bucket.resets_at` (already ISO). Emit a bucket only when `typeof utilization === "number"`.

**Codex** (has a real offline path — default to it):
1. Newest session jsonl `~/.codex/sessions/YYYY/MM/DD/rollout-<ISO-ts>-<uuid>.jsonl` — zero-auth, offline.
   Filenames sort lexicographically: glob today's dir, take max name, walk back a day if empty (never full-tree `find`). Reverse-scan for the last line containing `"rate_limits"`.
   Shape: `rate_limits{primary{used_percent, window_minutes, resets_at}, secondary{...}, plan_type}`. **`resets_at` is epoch SECONDS** → `new Date(x*1000).toISOString()`.
2. `GET https://chatgpt.com/backend-api/wham/usage` — headers `Authorization: Bearer <access_token>`, `ChatGPT-Account-Id: <account_id>`, both from plaintext `~/.codex/auth.json` (`tokens.access_token`, `tokens.account_id`).
3. OpenUsage fallback as above.

Bucket map: `primary`→Session (windowMs = window_minutes*60_000), `secondary`→Weekly.

**ccusage**: token/$ aggregation from jsonl only — NOT a limit source (no %, no resets). Ignore for /limits.

## Endpoint design

`GET /limits` → `{ fetchedAt, providers: [{ id, displayName, plan, source, limits: [{ label, usedPct, resetsAt, windowMs }] }] }`
— same normalized shape the app's UsageProvider already parses; keep `/usage` as an alias during migration.

- In-memory cache, **60–120s TTL**; honor 429 `Retry-After`; keep the existing 1.5s fetch timeout.
- Include `source` (`oauth` | `openusage` | `cache` | `jsonl` | `wham`) per provider so clients can show staleness.

## Hard rules / risks

1. **meshd is read-only on credentials.** Never refresh OAuth tokens (Claude Code/Codex refresh themselves; OpenUsage's plugin warns that writing the keychain JSON back non-minified corrupts Claude Code's session). On 401 (mid-rotation): serve last-good, retry next cycle.
2. **Keychain needs the user logged in** — at boot before GUI login the read fails; KeepAlive + fallback covers it.
3. **Schema drift**: all fields are internal/undocumented — `typeof`-guard every field, absent bucket ≠ crash, normalize both `resets_at` encodings (Codex epoch-sec vs Claude ISO).
4. Claude Code's own refresh endpoint (`platform.claude.com/v1/oauth/token`, client_id `9d1c250a-e61b-44d9-88ed-5944d1962f5e`) is documented here ONLY so nobody re-derives it — see rule 1: do not use it from meshd.

Refs: OpenUsage plugins `~/Library/Application Support/com.sunstory.openusage/plugins/{claude,codex}/plugin.js`; meshd usage code `meshd/server.ts` ~:402-463; LaunchAgent `~/Library/LaunchAgents/ai.lesearch.meshd.plist`.
