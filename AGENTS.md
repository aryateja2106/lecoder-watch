# AGENTS.md — read this before you touch anything

You are working on **LeSearch Mesh**: use your Mac from your wrist. A small daemon
(`meshd`) runs on each machine you own; an iPhone and Apple Watch app talk to it over your
own network. You watch and answer your AI coding agents, drive a real terminal session,
and control the Mac's screen and pointer, without opening the laptop.

**Who it is for decides most arguments:** non-technical people who are excited about AI
agents and want to use them daily. They will not configure SSH keys, port forwarding, or a
VPN. If a feature needs the user to understand networking, it is not done.

New here? This file, then [README.md](README.md). [index.md](index.md) is the file map,
[CONTEXT.md](CONTEXT.md) the shape, [MEMORY.md](MEMORY.md) the reasoning behind settled
decisions. Specs live in [openspec/](openspec/) — `openspec/config.yaml` carries the
project context every spec is written against.

---

## The rules that have actually cost days

**1. Verify by running, not by building.** Three features have shipped correct and
completely dead: one because no hook was ever registered, one because event hostnames never
matched what pairing stored, one because every fixture used a timestamp shape the daemon
does not emit. All three compiled green. A green build is not evidence. Run it against a
real daemon and paste the output.

**2. Check your worktree is current before you edit.** This repo has many worktrees and
branches, several of them weeks stale. A whole session was once spent editing a
six-week-old tree. Always:

```sh
git log -1 --date=short --format='%h %cd %s'
```

If that date is not close to today, you are probably in the wrong tree. Stop and ask.

**3. Grep can lie.** The Grep tool and shell `grep` skip binary-classified files
**silently**, so zero matches is indistinguishable from "not in the code". `server.ts` once
carried two raw NUL bytes, which hid all 861 lines of the daemon from every search. Before
concluding something is absent:

```sh
grep -c . path/to/file      # 0 means the file is being SKIPPED, not that it is empty
```

For anything load-bearing, read the file instead of trusting a grep.

**4. The daemon has exactly one shipping copy: `install/payload/meshd/`.** A per-display
capture feature was once written into a second root-level `meshd/` copy and lost when that
copy was deleted. Do not create a second copy.

**5. Never restart the user's running services to test a change.** `meshd`, LM Studio, the
CRM, `cmux` are all live. Boot a second instance on a spare port instead:

```sh
MESHD_PORT=8898 MESHD_HOST=127.0.0.1 MESHD_TOKEN=throwaway \
  bun run install/payload/meshd/server.ts
```

**6. The shipped payload is not the payload in this repo.** Users — including the author —
run whatever `mesh-install` last released, and that is usually behind. Measured on
2026-08-27: `mesh-install` latest was **v0.4.1 (21 Aug)** while this repo's daemon was
**0.5.0**, so seven capabilities the Swift actively calls (`screenRegion`, `power`,
`paste`, `openUrl`, `laPush`, `sessionStatus`, `captureJoin`) were answered by nothing on
every machine in the fleet, and the installed `mesh-hook` was a 152-line build against
182 lines here. A whole week of "the watch cannot show readable text" was a daemon a
version behind, not app code. Before debugging any daemon-side behaviour against a real
machine, ask what it is actually running:

```sh
curl -s http://127.0.0.1:8899/health | python3 -m json.tool | head -20
```

An old daemon does not refuse a new parameter. It answers **200 with the old shape**,
which is indistinguishable from the feature being broken.

**7. This shell is zsh, and zsh does not word-split unquoted variables.** In bash,
`dest="-destination id=X"; xcodebuild $dest` passes two arguments; in zsh it passes one.
`xcodebuild` could not parse it, silently fell back to "first of multiple matching
destinations", built for a **device** instead of the simulator, and printed
`** BUILD SUCCEEDED **`. The verification screenshot that followed was of a stale
simulator binary, and the conclusion drawn from it was wrong. Pass multi-word arguments
literally, or use an array:

```sh
DEPS=(Shared/Models.swift Shared/LimitHelpers.swift)
swiftc -Onone -o /tmp/check scripts/check-x.swift "${DEPS[@]}"
```

**8. `lsof -i :PORT` matches that port on EITHER end.** It is not "who owns this port", it
is "who is talking on this port" — so `lsof -ti ":$port" | xargs kill -9` kills the
listener *and every client connected to it*. The cmux-bridge starter did exactly that, on
every interactive shell, and meshd is one of those clients because `/agents` queries the
bridge. Opening a terminal could `kill -9` the user's running daemon. When the intent is
"replace the server", always:

```sh
lsof -ti "tcp:$port" -sTCP:LISTEN
```

Secrets: real tokens live in `~/.mesh/hosts.json` and `~/.mesh/token`. Read them into a
shell variable; never print one, never paste one into a file, and never write a literal
token into code or docs. **There is no such thing as `testtoken`** — it was a real
hardcoded fallback that broke every host, and it kept coming back because it was written
down in this file. It is not written down any more.

---

## Where things are

Everything under `docs/` is indexed in **[docs/README.md](docs/README.md)**, split into
what is still true and what is a dated snapshot. Five of those files name branches and
next steps that were correct in June and July and are wrong now; the index says which.

| Path | What it is |
|---|---|
| `Watch/` | watchOS app. Views, store, remote control. |
| `iOS/` | iPhone app. Views, store, terminal, native remote screen. |
| `Shared/` | Models + `MeshClient` + risk classifier, used by both apps. |
| `MeshDesktop/` | Mac menu-bar app: daemon status, permissions, pairing QR. |
| `WatchWidgets/`, `MeshWatchWidgets/` | Complication; iOS Live Activity. |
| `install/payload/meshd/` | **The daemon.** Bun + TypeScript. The only copy. |
| `install/payload/bin/mesh` | The CLI: setup, pair, doctor, upgrade, uninstall. |
| `install/install.sh` | The `curl \| sh` installer. |
| `scripts/check-*.{swift,sh}` | Self-checks. `check-all.sh` runs every one. |
| `scripts/brain-eval/` | Capability scorecard for any OpenAI-compatible local endpoint. |
| `references/` | Vendored third-party codebases, for study only. Nothing builds against them. |
| `project.yml` | Canonical Xcode project. Run `xcodegen generate` after editing. |
| `openspec/` | Specs and change proposals. |
| `web/` | Landing page (Vercel). |

## Build and verify

```sh
xcodegen generate
xcodebuild -project MeshWatch.xcodeproj -scheme 'MeshWatch Watch App' \
  -destination 'generic/platform=watchOS Simulator' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project MeshWatch.xcodeproj -scheme MeshDesktop \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
sh scripts/check-all.sh
cd install/payload/meshd && bun add -D --no-save bun-types typescript@~5.7.0 && bun x tsc --noEmit -p tsconfig.json
```

Swift checks must compile with `-Onone`: **`assert` is a no-op under `-O`**, so an
optimised check passes even when the code under test is wrong.

## The daemon API, in one place

Sessions are real, persistent multiplexer sessions. State survives between calls — `cd
/etc` then `pwd` prints `/etc`.

```
GET    /health                       no auth; identity + capabilities
GET    /doctor                       setup truth: token, input, screen, mux, push
GET    /stats /agents /usage /tailnet /displays /events
GET    /brain[?probe=1|need=images]  local model server: reachable, model, capabilities
POST   /agents/new                   {name,cwd,cmd,initialText}
GET    /agents/:n/panes              panes, each with currentPath
GET    /agents/:n/output?lines&pane  the pane's screen as TEXT
POST   /agents/:n/send               {text,key,pane}
POST   /agents/:n/panes              split
DELETE /agents/:n | /agents/:n/panes/:id
GET    /screen.jpg?display&width     width = longest edge, clamped 240-2000
POST   /input                        pointer, keys, scroll
       /clipboard /files /push /wake /pair
```

`send` keys: `enter ctrl-c ctrl-d up down left right tab escape backspace delete home end
page-up page-down`. **If you add a key here, wire it into both clients** — the watch once
exposed 6 of 14 and the terminal was unusable as a result. `scripts/check-watch-terminal-wiring.sh`
now fails when the daemon and the watch disagree.

## Design principles

1. **Multiplexer-agnostic.** tmux, rmux, herdr, zellij, mosh — the user's choice, never
   ours. `MESH_MUX` selects it. Anything tmux-specific belongs behind an adapter.
2. **Local-first.** No cloud STT, no relay. Nothing of the user's leaves their
   machines except APNs pushes. The one measured exception: the daemon may send one
   anonymized daily heartbeat (version, platform, coarse numeric counters, random
   install id — `install/payload/meshd/telemetry.ts` is the whole list), disabled
   with `MESHD_TELEMETRY=off`. If you touch telemetry, keep that file,
   `web/privacy.html`, and the README's Telemetry section in agreement — the privacy
   page is a public promise, not documentation.
3. **Text beats pixels on a watch.** `capture-pane` text is legible at any size; a JPEG of
   a Mac display is not. Reserve screen capture for what is genuinely graphical.
4. **Review before dispatch.** Dictated or typed text lands in an editable preview.
   Nothing reaches a shell until the user confirms.
5. **One clean install, one clean uninstall.** Whatever `install.sh` writes,
   `mesh uninstall` removes. Keep those two in step; a check enforces it.
6. **Discoverability is a feature.** Every screen answers "what can I do here?"

Commits: conventional, lowercase subject, a body that says *why*, `Co-Authored-By` trailer.

---

## Working alongside other agents

Several agents (Claude Code, Codex/ChatGPT, Cursor) work on this repo, sometimes at once.
OpenSpec is installed for all three: `openspec/config.yaml` is the shared brief, and each
has the same `propose / apply / archive` commands, so a change proposed by one is legible to
the others.

**Safe to hand out and run in parallel** — self-contained, hard to break the protocol:

- SwiftUI view work inside one file (`Watch/WatchViews.swift`, `iOS/ContentView.swift`)
- A single `scripts/check-*.sh` self-check
- Docs, the landing page in `web/`, CHANGELOG entries
- One `install/payload/meshd/*.ts` module that owns its own routes (`wol.ts`, `files.ts`)

**Must be serialized, one agent at a time** — these are the shared contracts, and two
agents editing them produces a mesh where the phone and the daemon disagree:

- `Shared/Models.swift` (every wire type, including `WatchCommand`)
- `Shared/MeshClient.swift` (every endpoint call)
- `install/payload/meshd/server.ts` (the route table)
- `project.yml`, and anything about pairing, auth, or tokens

**A good task for an external agent** names the file, the observable behaviour, and the
command that proves it:

> In `Watch/WatchViews.swift`, the terminal key bar is missing Page-up and Page-down.
> `meshd` already accepts `page-up`/`page-down` (see `KEY_SEND_KEYS` in
> `install/payload/meshd/server.ts`) and `store.send(key:)` already sends them. Add two
> chips following the existing `keyChip` pattern. Do not touch any other file. Prove it
> with: `xcodebuild -scheme 'MeshWatch Watch App' -destination 'generic/platform=watchOS
> Simulator' build` and `sh scripts/check-watch-terminal-wiring.sh`.

**Reviewing what another agent produced** — in this order, because this is the order things
have actually gone wrong:

1. `git diff` — did it touch a serialized file it was not asked to touch?
2. Does anything new hardcode a host name, an IP, a token, or an absolute `/Users` path?
3. `sh scripts/check-all.sh` and the three builds.
4. **Is the new thing wired to anything?** Search for a caller. A new function nobody calls
   and a new key nobody sends both compile perfectly.
5. Run it against a real daemon and read the response. Not the fixture — the daemon.

## What an agent cannot verify

Agents can build, run the daemon, drive the simulator, and curl. Agents **cannot** drive
Arya's physical iPhone or Apple Watch. Anything whose proof is "the mic opens", "the banner
appears on the wrist", or "the crown zoom looks sharp" must be handed back for a human
check — say so plainly instead of claiming it works.
