# LeSearch Mesh

Your machines, and the AI coding agents running on them, on your **iPhone and Apple
Watch**. An agent stops to ask a question, your wrist buzzes, you answer it, the agent
carries on.

No account, no cloud relay, no server of ours in the path. The phone talks straight to a
daemon on a machine you own.

- **iOS + watchOS app** (SwiftUI) — this repo
- **`meshd`** — the per-machine daemon (Bun + TypeScript), in [`install/payload/`](install/payload/)
- **Installer** — public at [LeSearch-AI/mesh-install](https://github.com/LeSearch-AI/mesh-install)

TestFlight: <https://testflight.apple.com/join/pVYPTxc7> · Landing page:
[`web/`](web/)

## Setup

```sh
curl -fsSL https://mesh.lesearch.ai/install.sh | sh   # on each Mac / Linux box
mesh pair                                             # prints an address + 8-char code
mesh hooks install                                    # so a blocked agent reaches your wrist
```

Then in the app: **Machines › Pair a machine**, type the address and the code. The
daemon hands back its own token *and every host it already knows*, so a fleet of four
takes one code. There are no built-in machines and no shipped token — an empty list is
the honest starting state.

## What it does

| Surface | What is on it |
|---|---|
| **Watch** | "Needs you" — every blocked agent across every machine, with the question and a one-tap answer. Sessions, terminal (crown scroll, key bar, VoiceOver), Mac control, usage limits. |
| **Complication** | How many agents are waiting, which one, and what it asked. Says when its reading is stale rather than asserting a count it cannot stand behind. |
| **Notifications** | Continue / Reply / Stop, answerable without opening anything. Sent by *your* machine straight to APNs. |
| **Live Activity** | The one session that needs you, on the Lock Screen and in the Dynamic Island. Blocked outranks merely busy. |
| **iPhone** | Machines and stats, sessions and terminals, a native trackpad + keyboard + screen for the Mac, pairing, settings. |

### The safety rule worth knowing

"Continue" sends a bare **Return**, and Return accepts whichever option the agent has
highlighted. So it is a *yes*, not an acknowledgement. `Shared/RiskClassifier.swift`
reads the question (never the session name) and, for a force-push / `rm -rf` /
hard-reset / `DROP TABLE` / `| sh` / `sudo`, turns the button red and makes it name the
verb. The list is deliberately narrow — flagging everything trains the eye to skip the
warning.

## Architecture

```
Apple Watch ──WatchConnectivity── iPhone ──HTTP over your tailnet/LAN──┬─ Mac:      meshd
  needs-you · sessions · terminal   (polls every machine)              ├─ dataflow: meshd
  trackpad · complication                                              └─ …:        meshd
                                                                            │
   agent blocks ─> mesh-hook ─> POST /events ─> meshd signs APNs ─> your phone + watch
```

The watch is a **companion**: it reaches the mesh through the paired iPhone, so install
the iPhone app first and the watch app follows from the Watch app on your phone.

### meshd

`GET /health /stats /agents /usage /events /tailnet /kb /displays /screen.jpg /clipboard`,
`POST /events /input /agents/:name/send /pair/claim /push/register`, plus `/files` and
`/fs`. Bearer token per machine, minted by that machine during pairing; header-only,
never in a query string. Binds `0.0.0.0:8899` on your private network.

Capabilities are advertised on `/health` (`screenPeek`, `input`, `files`, `push`,
`pair`, …) and the app gates its UI on them — Linux has input and files but no screen
capture, and says so.

## Build

```sh
xcodegen generate
xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build
xcodebuild -project MeshWatch.xcodeproj -scheme 'MeshWatch Watch App' \
  -destination 'generic/platform=watchOS Simulator' -derivedDataPath build/DerivedData build
sh scripts/check-all.sh
```

`scripts/check-all.sh` runs every self-check: pure-Swift ones compile with `swiftc
-Onone` (**`assert` is a no-op under `-O`** — an optimised check passes even when the
code under test is wrong), plus the shell checks over `meshd` and the `mesh` CLI.

**A green build proves very little here.** Two features have shipped correct and
completely dead — one because no hook was ever registered, one because event hostnames
never matched what pairing stored — and a third rendered nothing because every fixture
in the repo used a timestamp shape the daemon does not emit. Run it against a real
daemon before believing it. See [`MEMORY.md`](MEMORY.md).

## Layout

```
Shared/     models, MeshClient, risk classifier, glance, notification categories
iOS/        app, store, pairing, terminal, native remote screen
Watch/      watch app, store, views, remote control
WatchWidgets/      watch complication
MeshWatchWidgets/  iOS Live Activity + Dynamic Island
install/    the installer and the meshd payload it ships
scripts/    self-checks, packaging, release
web/        landing page (Vercel)
docs/       runbooks and design notes
```

Release process: [`docs/release-workflow.md`](docs/release-workflow.md). Changes:
[`CHANGELOG.md`](CHANGELOG.md) — the `[Unreleased]` block is the source for TestFlight's
"What to Test".
