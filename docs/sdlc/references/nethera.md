# Reference review: nethera

Reviewed 2026-09-27 on branch `sdlc/ai-native-playbook` at `88a1332` (the brief named
`e666aab`; the branch had moved one commit on, same day family). Clone:
`references/external/repos/nethera` at `f056cf0` (2026-08-10), read only, nothing executed.
Paths below that start `nethera/` are inside that clone; every other path is this repo.

## For Arya

Nethera sells "run apps on your own computer and get a public web address for them." The
apps do run on your machine, but every visitor goes through Nethera's own servers first.
Those servers hold the HTTPS certificate, see every request in the clear, and decide who
gets in with a Nethera account login or an API key. That puts their cloud in the middle of
your traffic, which our roadmap rules out, and their login model needs an account system,
which is also on our non-goals list. So we should not copy the product. We should copy
three habits: an app is only ever reachable on a private address, every link says in plain
words who can open it, and access keys are named, shown once and can be revoked. Our
biggest weakness for your goal ("nobody can just open it and delete or edit stuff") is
already written down as SEC-06: the secret in each app link is too short to put on the
public internet. Fixing it is small, but it touches two existing self-checks, so it needs
your OK.

## What it is

- A CLI (`neth`) on your laptop and a Linux agent (`nethera-agent`) on each server
  (`nethera/README.md:18-31`). You write a `nethera.yml`, which is a Docker Compose file
  with a `nethera:` block per service (`nethera/README.md:72-84`), and `neth deploy` sends
  it to the Nethera control plane (`nethera/docs/architecture.mdx:14-17`).
- A service marked `public: <port>` gets a URL like `<app>-<service>-<id>.sg.nethera.io`
  (`nethera/docs/endpoints.mdx:107-110`), gated by `auth: none | login | token`
  (`nethera/docs/auth.mdx:17-31`). The default is `none`, meaning anyone with the URL
  (`nethera/docs/auth.mdx:31`).
- License: **MIT License**, "Copyright (c) 2026 Nethera" (`nethera/LICENSE:1-3`). Bundling
  or adapting is allowed as long as the copyright and permission notice travel with any
  substantial copied portion (`nethera/LICENSE:12-13`). Scope matters: this repo holds only
  the agent, CLI, install scripts, docs and examples. The control plane, the edge proxy and
  the web frontend are private (`nethera/README.md:190-209`), so the security-critical
  half cannot be read, let alone reused.

## How it is built

Two Go programs, no shared module. About 22k lines including tests and docs.

| Piece | Key files | What it does |
|---|---|---|
| Agent entry | `nethera/agent/main.go`, `nethera/agent/daemon.go:57-140` | Gets sudo for WireGuard (`nethera/agent/system.go:345-357`), loads credentials, fetches its WireGuard config from the backend, then polls for deploy jobs every 5 s (`nethera/agent/daemon.go:59-60`). |
| Pairing | `nethera/agent/enroll.go:33-119` | Makes a 32-byte random secret (`:60-64`), posts to `/api/machines/enroll/start`, prints a pair code for `neth machine pair <code>` (`:94-101`), polls until paired, saves the machine token at mode 0600 (`nethera/agent/config.go:121-131`). |
| Tunnel | `nethera/agent/system.go:147-161`, `:282-309` | Downloads a WireGuard config from `/api/machines/network`, **including the interface private key** (`nethera/agent/system.go:282-285`, `nethera/agent/types.go:158`), writes `/etc/nethera/wg0.conf` at 0600, brings it up with `wg-quick`. |
| Exposure | `nethera/agent/compose.go:237-315`, `:411-440` | Rewrites the Compose file so a public service's port is bound to the machine's **WireGuard address only** (`nethera/agent/compose.go:298`), never `0.0.0.0`. Free host ports are found by trying to listen on that exact address (`nethera/agent/ports.go:9-35`). |
| Jobs | `nethera/agent/jobs.go:267-331` | Writes the generated compose file, `.env` of secrets and managed files into a per-deployment directory and runs `docker compose`. |
| CLI login | `nethera/cli/auth.go:16-130` | Browser device-login: start, open URL, poll. Session token saved at 0600 (`nethera/cli/config.go:153-161`). |
| Endpoint tokens | `nethera/cli/endpoint_tokens.go:101-143`, `:178-250` | Named per-service API tokens, optional expiry, printed exactly once ("Nethera cannot show it again", `:140-142`), revocable by id. |
| Posture wording | `nethera/cli/deploy.go:897-906` | Every printed URL carries a plain label: protected by login, API token required, or "Public - anyone with this URL can access". |

Request path: browser → Nethera edge (TLS, hostname match, auth) → WireGuard → your
machine → container (`nethera/docs/endpoints.mdx:124-128`,
`nethera/docs/architecture.mdx:24-33`). The agent is not in the request path
(`nethera/docs/architecture.mdx:6-8`).

## Security and audit model

What is on your machine versus theirs:

| Concern | Where it lives | Evidence |
|---|---|---|
| TLS termination | Their edge | `nethera/docs/architecture.mdx:26-28` |
| `auth: login` and `auth: token` checks | Their edge (code not in this repo) | `nethera/docs/auth.mdx:84-91` |
| WireGuard private key | Issued by their backend and sent to the agent | `nethera/agent/system.go:282-285` |
| What runs on the box | Their control plane sends a compose job; the agent runs it as root | Unit has no `User=` (`nethera/scripts/install-agent.sh:420-423`); job runner `nethera/agent/jobs.go:267` |
| App data, volumes | Your machine | `nethera/docs/architecture.mdx:30-33` |

What that means:

1. **Their cloud sees all of your app's traffic in plain text.** The edge terminates TLS,
   so "never takes your data off-box" (`nethera/README.md:36`) is true for stored data and
   not for data in flight.
2. **Whoever controls their backend, or a stolen `neth` session, controls your server.**
   A deploy job is an arbitrary compose file run by a root service, so it is root on every
   paired machine.
3. **The control plane knows the tunnel key.** A key generated on the machine, with only
   the public half uploaded, would not need to leave the box.
4. **`preferLan` opens an unauthenticated side door.** The docs say auth is checked before
   the LAN redirect (`nethera/docs/local-access.mdx:28`), but the agent also binds the
   container port directly on the LAN address (`nethera/agent/compose.go:299-300`). Anyone
   on that network can reach `http://<lan-ip>:<port>` with no login or token. The edge
   check only covers the redirect.
5. Good parts: no inbound ports on the machine (`nethera/docs/architecture.mdx:39`); files
   holding secrets are written 0600 (`nethera/agent/config.go:130`,
   `nethera/agent/system.go:302`); endpoint tokens are shown once, named, and revocable.

There is no audit log in the client code. `grep -i audit` over `agent/` and `cli/`
returns nothing, so any access log lives on their private edge (unverified).

### Our side, for comparison (read, not run)

- Built apps are served at `GET /a/<slug>-<key>/…` with no bearer token, because Safari
  cannot send one; the key in the path is the gate (`install/payload/meshd/apps.ts:3-6`,
  mounted before auth at `install/payload/meshd/server.ts:1343-1348`). Only `GET` is
  mounted there. By reading `server.ts:1346-1361`, any other method on `/a/` falls through
  to the bearer check.
- A web app is a folder of static files (`apps.ts:220-257`), and the PWA skill keeps its
  data in each visitor's own browser storage
  (`install/payload/share/skills/pwa-local-app-builder/SKILL.md:3`). So today a visitor
  **cannot edit or delete anything on the Mac**. The only risk is someone reading an app
  they were not given.
- The key is 8 hex characters (`apps.ts:90`), made by `randomHex(4)`, which is 32 bits
  (`install/payload/bin/mesh:1851-1855`, `:2038`, `:2063`). This is finding **SEC-06** in
  `docs/review-2026-09-17.md:98`: too short, with no rate limit, and
  `docs/self-serve-apps.md:36-40` names Tailscale Funnel as the next step. Still open in
  this tree.
- `mesh apps ota --enable` maps only `/a` through Tailscale Serve, which is tailnet only
  (`install/payload/bin/mesh:1936-1946`). meshd itself binds `0.0.0.0` by default
  (`server.ts:28`), so the same `/a/` URL also answers over plain HTTP on the LAN (SEC-01).
- A reverse proxy on the box connects from 127.0.0.1, and its `X-Forwarded-For` already
  withdraws the loopback exemption (`install/payload/meshd/loopback-trust.ts:14-39`,
  `server.ts:1186-1191`). That lesson is what makes any Serve or Funnel mapping safe for
  the rest of the daemon.
- There is no support at all for an app that has its own backend process, such as a small
  server with a database. Nothing proxies to one. That is the real gap behind "we do not
  want anyone to delete or edit stuff", because only a backend can be edited remotely.

## What to borrow

| Pattern | Where it would live in our repo | Effort | Why |
|---|---|---|---|
| Long unguessable link keys before anything goes public (Nethera relies on edge auth; our key is our auth) | `install/payload/bin/mesh:2038,2063` (`randomHex(16)`), `install/payload/meshd/apps.ts:90,225` (accept 8 or 32 hex) | S | Closes SEC-06, which is the prerequisite `docs/self-serve-apps.md:36` itself states. |
| Bind an app's port to a private address, never all interfaces (`nethera/agent/compose.go:298`) | A future `mesh apps serve` in `install/payload/bin/mesh`: an app with a backend must listen on `127.0.0.1`; meshd refuses to register a port that answers on the LAN address | S | This is the Nethera habit that actually protects data. Their `preferLan` side door shows what happens without it. |
| Probe "is this port free / actually listening on this exact address" (`nethera/agent/ports.go:9-35`) | Same `mesh apps serve` command; `apps.ts` row gains `up: true/false` | S | So `/built-apps` can say an app is down instead of showing a dead link. |
| Plain-words posture on every link (`nethera/cli/deploy.go:897-906`) | `mesh apps list` / `ota` output in `install/payload/bin/mesh:1948-1958`; a `reach` field on `AppRow` in `apps.ts:129` shown by `iOS/AppsLibraryView.swift` | S | Arya and non-technical users should never have to guess whether a link is "my devices only" or "anyone with the link". |
| Named, revocable, shown-once access keys per app (`nethera/cli/endpoint_tokens.go:101-143`) | `~/.mesh/apps/<slug>/meta.json` gains a list of hashed write keys; `mesh apps key add/list/revoke <slug>` | M | Lets a backend app allow edits only from holders of a key that can be killed on its own, without handing out the machine token. Store hashes, not values (our redaction rules). |
| Reverse proxy for a backend app, read-open / write-gated | New `install/payload/meshd/appproxy.ts` + one route line in `server.ts` (the "one module, two lines" rule, `docs/product/PRODUCT.md` §11.4) | M | The block Arya is actually asking for: GET passes with the link key; POST/PUT/PATCH/DELETE need the owner's bearer or a per-app write key. |
| Secrets injected at start from a 0600 file, never in the app folder (`nethera/docs/secrets.mdx:30-37`, `nethera/agent/config.go:130`) | `~/.mesh/apps/<slug>/env` (0600) read by `mesh apps serve` | S | Agent-built apps will want API keys; keep them out of `site/` which is web-served. |

## What not to copy and why

- **The edge / relay itself.** TLS ends in their cloud and every request passes through
  it. `ROADMAP.md:13-18` and `ROADMAP.md:114-115` rule out our server in the data path, and
  `docs/product/PRODUCT.md` §10 repeats it.
- **`auth: login` (workspace accounts).** Needs an account system. `ROADMAP.md:118` and
  `PRODUCT.md` §10 ("no login ever gates a machine") exclude it.
- **Server-issued tunnel keys and root agents.** The backend hands out the WireGuard
  private key and the agent runs as root executing jobs the cloud sends. Our trust model is
  a code the user's own machine printed, and meshd runs as the user (launchd / systemd
  `--user`, `PRODUCT.md` §3).
- **`preferLan` binding on the LAN interface.** It is an unauthenticated listener next to
  an authenticated URL. We already carry that shape by accident: SEC-01, meshd on
  `0.0.0.0`. Do not add a second one.
- **Docker Compose as the app format.** It needs Docker on a Mac-first product and is far
  more than an agent-built habit tracker needs. The Linux-only, systemd, root installer
  (`nethera/README.md:173-179`) does not fit a launchd user daemon.
- **Default `auth: none`.** Public-by-default is the wrong default for "nobody can edit my
  stuff". Ours should default to tailnet-only with the link key.
- **Code.** MIT allows it, but there is nothing worth vendoring: the valuable parts are
  a few one-line habits, and the Go code targets Docker and WireGuard, which we do not use.

## The first block

Make app link keys 128-bit (SEC-06). `mesh apps publish` and a first `mesh apps add` mint
`randomHex(16)` instead of `randomHex(4)` (`install/payload/bin/mesh:2038`, `:2063`, which
still keeps a prior key so links already on a Home Screen keep working). `apps.ts:90` and
the route regex at `apps.ts:225` accept either 8 or 32 hex characters, so old links do
not break. `mesh apps list` marks an app still on an 8-hex key as "short key, re-publish
before sharing outside your devices". Proof is a new `scripts/check-apps-key-strength.sh`:
it boots a side-port meshd (`MESHD_PORT=8898`, scratch `MESH_HOME`), publishes a fixture,
and asserts that the key is 32 hex, the 32-hex URL serves 200, a legacy 8-hex fixture
still serves 200, and a wrong 32-hex key returns 404. `scripts/check-apps-serve.sh` must
stay green unmodified. **Human gate:** `scripts/check-mesh-apps.sh:50,63` and
`scripts/check-apps-ota.sh:58` assert an 8-hex key. They must be widened to 8-or-32 in the
same change, and CLAUDE.md rule 3 forbids an unattended run editing an existing
`check-*`. So this block runs attended, with Arya's explicit OK on those three lines.
Effort S. The backend proxy (`appproxy.ts`, read-open / write-gated) is the second block,
and it should not start before this one lands.

## Open questions for Arya

1. **Who should be able to open an app?** (a) Only your own devices on the tailnet, as
   today with `ota --enable`; (b) anyone you send the link to, which means Tailscale
   Funnel. Funnel carries public visitors through Tailscale's servers. It is not *our*
   server, but it is a third party in the data path (per Tailscale's docs, unverified
   here). Is that acceptable under "local-first, forever"?
2. **Do agent-built apps need a backend at all**, or is "static app, data in each
   device's browser" enough for now? If static is enough, the first block is the whole
   job and the proxy can wait.
3. **For apps with a backend, who may edit?** Only you (the machine token), or also
   people you hand a named, revocable key to?
4. **May the first block edit the three 8-hex assertions** in `check-mesh-apps.sh` and
   `check-apps-ota.sh`? Without that, SEC-06 cannot land green.
5. **Should old 8-hex links be rotated automatically** (they break on phones that saved
   them), or only flagged in `mesh apps list`?
6. Tailscale Serve can tell a proxied app which tailnet user is calling (a
   `Tailscale-User-Login` header, per Tailscale's docs, unverified here). Do you want
   "edits allowed only when it's me on my tailnet" as the write rule instead of keys?
   meshd would have to trust that header only from a 127.0.0.1 socket peer.
