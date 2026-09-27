# install/payload/meshd/ — the background program (daemon) on each of the owner's computers that the iPhone and Apple Watch apps talk to

**Read first:** `docs/product/PRODUCT.md` §5 (modules, capabilities, security rules) · `docs/agents/CONTRACTS.md` (route table, auth tier; generated, has gaps) · `server.ts:1327-1363` (request gate order)
**Surface:** daemon
**Serialized (one agent at a time):** `server.ts` (route table + capability list), `auth.ts`, `loopback-trust.ts`, `pair.ts` — AGENTS.md "Must be serialized" (pairing, auth, tokens). `telemetry.ts` changes land together with `web/privacy.html` (AGENTS.md design principle 2).
**Prove a change:**
- Typecheck: `sh scripts/gate-types.sh` (or `./.claude/scripts/gates.sh fast`)
- Security: `sh scripts/check-mesh-auth.sh && sh scripts/check-pair-auth.sh && sh scripts/check-mesh-csrf.sh && sh scripts/check-host-guard.sh && sh scripts/check-redact.sh`
- Per module: its `check-*` in `docs/agents/CHECKS.md` (`check-pty-route.sh`, `check-session-snapshots.sh`, `check-chat-search.sh`, `check-apps-serve.sh`, `check-mesh-push.sh`, `check-wol.sh`, …)
- Behaviour: side-port daemon + curl (AGENTS.md rules 1, 5): `MESHD_PORT=8898 MESHD_HOST=127.0.0.1 MESHD_TOKEN=throwaway MESHD_TELEMETRY=off MESHD_EVENTS_PATH=<scratch> MESHD_EXPOSURES_PATH=<scratch> bun run install/payload/meshd/server.ts`
- No dedicated check for `chat.ts`, `desktop.html`, `files.html`, `cmux-bridge.ts`, or the telemetry payload whitelist — add `scripts/check-<x>.sh`.
**Traps:**
- Gate order is load-bearing: Host guard (421) → `/health` → `/a/*` (path key, no token) → browser cross-site guard → `/pair/new` authed → `/pair/claim` (code is the credential) → bearer or loopback → mirror-token read-only fallback (`server.ts:1333-1363`). A route placed above `server.ts:1359` is unauthenticated.
- Loopback skips the bearer by default (`loopback-trust.ts:24-39`); any `X-Forwarded-For`/`X-Real-IP`/`Forwarded` withdraws it; `MESHD_TRUST_LOOPBACK=0` disables it. A local reverse proxy that strips those headers makes every remote caller loopback.
- The bearer is full-account power: `/fs/read` returns any file unredacted, `~/.mesh/hosts.json` included (`files.ts:81-101`); `/fs/write` refuses `~/.mesh` (`files.ts:125-128`) but `/fs/move` and `/fs/mkdir` do not (`files.ts:169-186`).
- Every outbound text path must pass `redact`/`redactAndRecord` (`redact.ts:113`, `:234`); `pty.ts:74-78` and `server.ts:598` do. A new output route that skips it leaks secrets to APNs and the watch.
- `/health` is unauthenticated and returns hostname, MAC, IPv4, netmask (`server.ts:1341`). Default bind `0.0.0.0`, plain HTTP (`server.ts:28`, `:1327-1329`): the LAN can reach it; only Tailscale encrypts the bearer in transit.
- `cmux-bridge.ts` is a second, token-less listener on 127.0.0.1:8901 guarded only by Origin/Sec-Fetch-Site (`cmux-bridge.ts:41-44`), started by `install/payload/hooks/cmux-bridge.zsh:44`, not by `server.ts`. Never sweep-kill its port (AGENTS.md rule 8).
**SDLC stage:** Build, Test, Maintain — the product's core runtime; its telemetry heartbeat and exposures ledger are the Stage 6 signals, and it is the first security-baseline target (see [docs/sdlc/3-build.html](../../../docs/sdlc/3-build.html), [docs/sdlc/4-test.html](../../../docs/sdlc/4-test.html), [docs/sdlc/5-ship.html](../../../docs/sdlc/5-ship.html))
**Map:** `INDEX.md` (to be generated; 28 tracked files) · until then `docs/agents/CODEMAP.md` section `install/payload/meshd/` (line 121)
