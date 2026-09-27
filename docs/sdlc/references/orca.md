# Reference review: Orca

Reviewed 2026-09-27 on branch `sdlc/ai-native-playbook` at `88a1332` (the brief named
`e666aab`; the tree is one commit newer, same branch). The clone is
`references/external/repos/orca` at `46907de6` (2026-09-26), about 393 MB. It was read by
directory listing, README, docs and a handful of entry files; nothing in it was executed.
Paths below starting `orca/` are inside that clone. Everything else is in this repo.

## For Arya

Orca is a free, open-source desktop app for running many coding agents side by side on
your computer, each in its own copy of the project, with a phone app that watches them.
It is the closest thing to what we do, but it is built the other way round: the desktop
app is the product and the phone is an add-on, and to reach the phone from outside your
home network it sends traffic through Orca's own cloud servers, which needs an Orca
account. We refuse both of those by design, so the parts to take are ideas, not code.
The three ideas worth taking are: start each agent in its own copy of the project so
three agents on one repo cannot overwrite each other; give each paired phone its own
key so a lost phone can be cut off without re-pairing every device; and never tell you an
agent has stopped when the truth is only that we cannot reach its machine. Our real
advantages remain the watch, controlling the Mac screen and pointer, and no SSH or
account at all; Orca has none of those. The license (MIT) lets us copy code if we keep
their copyright line, but we do not need to.

## What it is

- A desktop "IDE for parallel agentic development" (`orca/package.json:2-4`), Electron +
  TypeScript, version `1.4.214`, shipped daily (`orca/README.md` "we ship daily").
- Core idea: every task is a git worktree with its own branch, files and agent terminals
  (`orca/docs/site/content/docs/model/worktrees.mdx:10-23`). Any terminal agent works;
  the README lists 25+ agent CLIs.
- A React Native + Expo mobile companion (`orca/mobile/README.md:3`, `orca/mobile/package.json:30,58`)
  that is "a remote control for the desktop you already have running"
  (`orca/docs/site/content/docs/mobile.mdx:36`): status per worktree, scrollback, chat
  view, short replies, dictation, image attach, account switcher, source control, push.
- A headless server mode (`orcad`) for remote Linux boxes
  (`orca/docs/reference/orcad-operations.md:1-18`), plus "SSH worktrees" where Orca
  deploys a small relay daemon over SSH and runs agents there
  (`orca/docs/reference/ssh-execution-boundary.md:16-27`).
- A cloud relay and push gateway run by the vendor (`orca/cloud/README.md:1-30`).

No watchOS target was found in `orca/mobile/app.config.js`, `orca/mobile/app.json` or
`orca/mobile/plugins/` (searched for "watchos", "apple watch", "WatchConnectivity";
not exhaustive).

## How it is built

| Part | Where | What it does |
|---|---|---|
| Desktop main process | `orca/src/main/` (~100 sub-folders: `pty`, `git`, `ssh`, `daemon`, `agent-hooks`, `claude-usage`, `rate-limits`, `runtime`, `telemetry`, one folder per agent CLI) | Owns PTYs, git, worktrees, hooks, usage, pairing |
| Terminal daemon | `orca/src/main/daemon/` | Separate long-lived process that owns every PTY; its socket is named by protocol version `daemon-v<N>.sock`, so an app update does not orphan live terminals (`orca/docs/reference/ssh-execution-boundary.md:49`) |
| Remote relay (SSH) | `orca/src/relay/` (`relay.ts` is 37 lines; handlers beside it) | Detached daemon on the SSH host; PTYs are its children, reconnect replays a 102,400-unit tail (`ssh-execution-boundary.md:41`) |
| Headless runtime | `orcad` (`orca/docs/reference/orcad-operations.md:7-18`) | orcad + terminal daemon as two processes; restarting orcad never kills terminals |
| CLI | `orca/src/cli/` (`index.ts`, `dispatch.ts`, `handlers/`) | `orca worktree create`, `snapshot`, `click`, `fill`; agents drive Orca through it |
| Mobile app | `orca/mobile/src/` (`home`, `session`, `terminal`, `worktree`, `transport`, `notifications`, `accounts`) | Terminal is xterm.js inside a WebView (`orca/mobile/package.json:26-28`) |
| Mobile transport | WebSocket RPC on port 6768 (`orca/mobile/README.md:7`), or the cloud relay | JSON RPC, method allowlist for phones |
| Cloud | `orca/cloud/apps/relay`, `apps/push`, `infra/terraform` | Relay "splices frames" between phone and desktop (`orca/cloud/README.md:3-7`); push gateway holds the APNs key (`:27-30`); Postgres in production (`:51`) |
| Agent status | one store in the hook server; sidebar, CLI, mobile subscribe (`orca/AGENTS.md:98-100`) | Same rule as our `sessionsNeedingAttention` (`Shared/Models.swift:735`) |
| Usage | `orca/src/main/claude-usage/` scans `~/.claude/projects/*.jsonl` (`transcript-file-discovery.ts:5-6`); `orca/src/main/rate-limits/` calls Anthropic's OAuth usage endpoint (`claude-oauth-usage-request.ts:8`) or parses `/usage` in a PTY (`claude-pty-usage-parser.ts`) | Token counts locally; limit percentages from the vendor API |
| Worktree create | `orca/src/main/git/worktree-add.ts` (244 lines); `.worktreeinclude` copies listed gitignored files such as `.env` into each new worktree (`worktrees.mdx:46`) | |
| Engineering rules | `orca/AGENTS.md` (their CLAUDE.md is one line, `@AGENTS.md`, same pattern as ours); `orca/docs/reference/` holds 53 rule documents | Ratchet checks in `orca/package.json` `lint` (e.g. `config/scripts/check-max-lines-ratchet.mjs:7-14`: the set of over-limit files may only shrink) |

### Mapping to ours

| Concern | Orca | Ours |
|---|---|---|
| Unit of work | git worktree per task | multiplexer session per agent (`install/payload/meshd/server.ts:1506-1540`); no worktree option |
| Remote machine | SSH relay or paired `orcad` | `meshd` on every machine, paired by code (`install/payload/meshd/pair.ts:1-20`) |
| Phone terminal | xterm.js in a WebView | native SwiftTerm over `GET /agents/:name/pty` (`install/payload/meshd/pty.ts:1-12`, `docs/product/PRODUCT.md:151`) |
| Reconnect replay | bounded buffer tail | `capture-pane -e -S -N` replay, default 2000 lines (`install/payload/meshd/pty.ts:12,92`) |
| Surviving a daemon restart | terminal daemon separate from orcad; Linux uses `systemd-run --user --scope` (`orcad-operations.md:31-37`) | `KillMode=process` in the systemd unit (`install/install.sh:230-234`), enforced by `scripts/check-linux-desktop.sh:23` |
| Transcript search/resume | "AI vault" (`orca/src/relay/ai-vault-*`) | `sessions.ts` + `chats.ts` (`docs/product/PRODUCT.md:152-153`) |
| Push | vendor push gateway | APNs direct from meshd (`docs/product/PRODUCT.md:143`) |
| Watch, Mac screen and pointer | none found | yes (`docs/product/moshi-parity-2026-09-22.md:76-77`) |

## Security and audit model

What Orca does (read in code or their docs):

- **Default reach is loopback.** `orcad` binds `127.0.0.1` unless told otherwise, accepts
  only literal IPs, and logs every wide bind (`orca/docs/reference/orcad-operations.md:71-80`).
  A pairing offer on a wildcard listener advertises `127.0.0.1` unless an address is set
  (`orca/src/main/runtime/pairing-endpoint.ts:17-24`).
- **One token per device, with a scope.** Each paired device has its own id, token, scope
  (`mobile` or `runtime`), `pairedAt`, `lastSeenAt` and optional push registration
  (`orca/src/main/runtime/device-registry.ts:25-40`). A phone's scope is limited to an RPC
  allowlist (`orca/src/main/runtime/runtime-rpc/runtime-rpc-mobile-method-allowlist.ts:1`,
  300 lines). The registry refuses to overwrite itself after a failed read, because that
  "would revoke every paired device" (`device-registry.ts:344`).
- **Pairing offer.** `orca://pair?code=<base64url JSON>`, size-capped and host-checked
  (`orca/src/shared/pairing.ts:14-27,40-53`). It carries a device token and the server's
  public key (inferred from `orca/mobile/README.md:99`; field names unverified).
- **Encryption on top of the socket, even on the LAN.** NaCl box (`tweetnacl`, X25519)
  shared by desktop, CLI and phone (`orca/src/shared/e2ee-crypto.ts:1-17`); the v2 session
  uses separate keys per direction and message counters
  (`orca/src/main/runtime/rpc/mobile-e2ee-v2-desktop-session.ts:26-35`) and applies to both
  `direct` and `relay` transports (`orca/src/shared/mobile-e2ee-v2-contract.ts:152-164`).
  So the relay should see ciphertext only; I did not verify the relay code.
- **Honest process verdicts.** `live` / `unverifiable` / `exited`; losing contact can only
  ever produce `unverifiable` (`orca/docs/reference/ssh-execution-boundary.md:14`), and a
  separate host-contact verdict adds `refused` and `retired` (same file, "Host contact is a
  different question").
- **Wire compatibility.** A new optional field is safe; a new stream frame type must be
  capability-negotiated because old peers drop unknown frames silently
  (`orca/docs/reference/remote-wire-compatibility.md:12-36`).

What weakens it for our purposes:

- The relay requires signing in to an Orca account (`orca/docs/site/content/docs/mobile.mdx:42`),
  and the API and auth services live in a private repository
  (`orca/cloud/README.md:100-103`), so the account side cannot be audited from this clone.
- The push gateway holds the APNs key centrally and receives notification titles and bodies
  to send (`orca/cloud/README.md:27-44`); it logs counters only (`:59-60`).
- Product telemetry goes to PostHog (`orca/src/main/telemetry/client.ts:1-11`), behind a
  consent module (`orca/src/main/telemetry/consent.ts`, not read).
- Rate-limit data comes from reading the user's Claude login credentials and calling
  `https://api.anthropic.com/api/oauth/usage` (`orca/src/main/rate-limits/claude-oauth-usage-request.ts:8`).
- Audit trail: I found no per-action audit log (not searched exhaustively). Their audit is
  git history plus the reference documents.

Ours, for contrast: fail-closed constant-time bearer (`install/payload/meshd/auth.ts:1-27`),
Origin/Host guard before auth (`install/payload/meshd/server.ts:1333`), redaction on every
outbound path and an exposure ledger (`docs/product/PRODUCT.md:154`), a narrower second
bearer for the session mirror (`docs/product/PRODUCT.md:152`). Two gaps Orca makes visible:
(1) one token per machine, and pairing hands the phone every fleet token
(`install/payload/meshd/pair.ts:18-20,76-88`), so a lost phone means rotating every machine
(`mesh token rotate`, `install/payload/bin/mesh:1338`); (2) meshd serves plain HTTP on
`0.0.0.0` (`install/payload/meshd/server.ts:28,1327-1329`) and relies on Tailscale's
encryption; on a plain LAN without Tailscale the bearer and every response cross the
network unencrypted (follows from the code; not measured with a packet capture).

## What to borrow

Patterns, not code. Effort: S under a day, M a few days, L a week or more.

| Pattern | Where it would live in our repo | Effort | Why |
|---|---|---|---|
| Optional git worktree per new agent (`worktree: true` on `/agents/new`, branch `mesh/<name>`, path beside the repo) | new `install/payload/meshd/worktree.ts`; two-line patch in `server.ts:1506-1520`; `"worktree"` in `CAPABILITIES` (`server.ts:51`); `--worktree` in `cmdNew` (`install/payload/bin/mesh:356-365`) | M | Orca's core feature. Today three agents started on one repo from the phone share one checkout and can overwrite each other |
| `.worktreeinclude` (copy listed gitignored files like `.env` into the new worktree) | inside `worktree.ts`, after the row above | S | A fresh worktree without `.env` fails its first build; Orca found this (`worktrees.mdx:46`) |
| Host-contact verdict: `live` / `unverifiable` / `refused` (token rejected, protocol mismatch) instead of one `error ?? "offline"` string | `Shared/Models.swift:929-960` (machine status; serialized file, one agent at a time) | S | "Token rejected on every host" has happened here before; the user should read "pair again", not "offline". Never report a session ended because a poll failed |
| One token per paired device, with scope and "remove this phone" | new `install/payload/meshd/devices.ts`; `pair.ts`; `auth.ts`; a `mesh devices` CLI verb | L | Revoke one phone without rotating the fleet; a watch or phone scope can later be narrower than a desktop's. Touches pairing and auth, which AGENTS.md:239 says must be serialized |
| Terminals outlive the daemon via their own systemd scope (`systemd-run --user --scope`) instead of `KillMode=process` | `install/install.sh:230-234`; where meshd first starts the mux server | M | Orca documents `KillMode=process` as "not a supported preservation mechanism" (`orcad-operations.md:25-30`). Needs a human OK: `scripts/check-linux-desktop.sh:23` requires the current line and existing checks may not be edited unattended |
| Record real agent screens and transcripts as fixtures, byte for byte, scrubbed | new `scripts/capture-agent-fixture.sh`; fixtures under `scripts/fixtures/` | S | AGENTS.md rule 1: a feature shipped dead because every fixture used a timestamp shape the daemon never emits. Orca's rule: write detection against a captured transcript (`orca/AGENTS.md:102-104`, `agent-pty-transcript-capture.md:10-20`) |
| Wire-compatibility rules written down: optional field safe, new frame type capability-gated | a new doc under `docs/agents/`; applies to `pty.ts` text frames and every `/health` capability | S | We already gate on capabilities (`docs/product/PRODUCT.md:121-130`); Orca's two rules name the failure (silent drop) our old-daemon incidents had |
| Usage from local transcripts instead of a third-party app's cache | replace `getUsage` (`install/payload/meshd/server.ts:821-830`) with a `usage.ts` module that scans `~/.claude/projects` and `~/.codex/sessions` | M | Today `/usage` reads `com.sunstory.openusage`'s cache on Macs only and returns nothing on Linux. Local scanning gives token counts; limit percentages would still be unknown without the vendor API (see "not copy") |
| Ratchet checks: a number that may only go down (e.g. `server.ts` line count, count of ungated capabilities) | new `scripts/check-*-ratchet.sh` with a baseline file | S | Enforces "one module, two lines" (`docs/product/PRODUCT.md:457`) and shrinks the 16 capabilities no client gates on (`docs/agents/CONTRACTS.md:96-129`) |

Things Orca has that we have **dead or partial**, using the legend of
`docs/product/moshi-parity-2026-09-22.md:3` (W works, P partial, D dead, M missing):

| Orca has | Ours | Evidence |
|---|---|---|
| Desktop app people can download | **D** Mac menu bar app built, not distributed | `docs/product/PRODUCT.md:85` |
| Mobile app in the App Store | **P** public TestFlight serves an old build until Beta App Review | `docs/product/PRODUCT.md:84`, `:469` |
| Usage and rate-limit screen on the phone | **P** wired end to end (`iOS/MeshStore.swift:608`, `Watch/WatchMeshStore.swift:451`) but fed by a third-party Mac app; Linux always empty | `install/payload/meshd/server.ts:821-830` |
| Capabilities negotiated per feature | **P** 16 of 32 advertised capabilities are gated by no client, which the generated contract calls "dead on the client": an old daemon shows a broken screen instead of a named symptom | `docs/agents/CONTRACTS.md:94-129` |
| Worktree per agent | **M** | `install/payload/meshd/server.ts:1506-1540` |
| Diff review and annotations | **M** | `docs/product/moshi-parity-2026-09-22.md:64` |
| Image attach from the phone | **M** | `docs/product/moshi-parity-2026-09-22.md:40` |
| Quick commands synced with the desktop | **P** quick-send strings only | `docs/product/moshi-parity-2026-09-22.md:30` |
| Session search and resume | **W** | `docs/product/PRODUCT.md:152-153` |

Ignore: GitHub/Linear/Jira/GitLab boards, the embedded Chromium browser and Design Mode,
the VS Code editor, annotating diffs on the desktop, Windows/WSL support, ephemeral VMs,
relay region placement, their computer-use CLI (`mesh-input` already covers the Mac), the
account switcher's reset-credit spending, and the 25+ agent icon catalog.

## What not to copy and why

- **License.** MIT, verbatim name "MIT License", `Copyright (c) 2026 Lovecast Inc.`
  (`orca/LICENSE:1-3`; `package.json` names the author `stablyai`). Bundling or adapting is
  allowed, commercially too, provided the copyright and permission notice travel with any
  copied or substantial portion. Borrowing a pattern needs no notice. If a file is ever
  copied, keep the notice in that file's header.
- **The cloud relay, sign-in and central push gateway** (`orca/cloud/`). Our non-goals
  forbid a cloud relay and an account system (`ROADMAP.md:112-118`,
  `docs/product/PRODUCT.md:435-441`) and nothing of the user's leaves their machines except
  APNs pushes (`AGENTS.md:200-206`). This rules out the relay, the push gateway, and the
  relay-only half of their E2EE design (the direct-LAN half is an open question below).
- **PostHog telemetry.** Our privacy page promises one anonymous heartbeat whose whole
  list is `telemetry.ts` (`AGENTS.md:201-206`).
- **Reading Claude login credentials for rate limits** (`claude-oauth-usage-request.ts:8`).
  It uses the user's OAuth credentials against an endpoint Anthropic does not document for
  this use. We do not touch agent credentials.
- **SSH worktrees.** "No SSH" is our wedge (`docs/product/moshi-parity-2026-09-22.md:82`).
- **The mobile terminal stack** (React Native, xterm.js in a WebView). We just left
  WKWebView for native SwiftTerm on purpose (`docs/product/moshi-parity-2026-09-22.md:86-93`).
- **Their code, wholesale.** Orca is Node/Electron with `zod`, `tweetnacl` and hundreds of
  small modules and tests; our daemon is dependency-light Bun, one capability per module
  (`ROADMAP.md:20-22`). Porting files would import their dependencies and their scale.

## The first block

Add an optional git worktree to `POST /agents/new`: when the body has `worktree: true`
and `cwd` is inside a git repository, meshd runs `git worktree add -b mesh/<name>
<repo>-worktrees/<name>` next to the repository and starts the session there; otherwise
nothing changes. Files: new `install/payload/meshd/worktree.ts` (one exported function,
returns the path or a readable error); `install/payload/meshd/server.ts` (an import, one
line before `new-session` at `:1520`, and `"worktree"` in `CAPABILITIES` at `:51`;
`server.ts` is a serialized file, so one agent at a time); `install/payload/bin/mesh`
(`--worktree` in `cmdNew`, `:356-365`); new `scripts/check-agents-worktree.sh`. The new
check boots a throwaway daemon on port 8898 with a scratch `MESH_HOME`, makes a temporary
repo, starts two sessions with `worktree: true`, and asserts `git worktree list` shows two
distinct paths, each pane's `currentPath` matches its worktree, `/health` lists
`worktree`, and a request without the flag behaves as before. Then `sh scripts/codemap.sh`
so `scripts/check-codemap.sh` stays green, `scripts/check-package-mesh-install.sh` to
confirm the new module ships in the tarball, and `./.claude/scripts/gates.sh fast`.
Removing worktrees and the phone toggle (`Shared/MeshClient.swift`, serialized) are the
next blocks, not this one. `mesh uninstall` must never delete a worktree: it lives beside
the user's repository, not under `~/.mesh`.

## Open questions for Arya

1. When you start an agent from the phone on a project that already has an agent running,
   should it get its own copy of the project automatically, or only when you tick a box?
2. Is "remove one lost phone without re-pairing everything" worth about a week now, given
   the 2026 revenue-first focus?
3. On a home network without Tailscale, the phone's traffic to meshd is not encrypted.
   Accept that and say "use Tailscale", or add encryption between phone and daemon like
   Orca's direct mode (a real change to pairing and both apps)?
4. The Linux service fix (own systemd scope for terminals) requires editing the existing
   check `scripts/check-linux-desktop.sh`. Do you approve that edit?
5. Usage display: keep depending on the third-party OpenUsage app, or read the agents' own
   files (token counts only; no "percent of limit left")?
6. Orca's phone app is free, MIT-licensed and in the App Store. Do we position against it
   explicitly (watch, Mac control, no account, no SSH), or ignore it publicly?
