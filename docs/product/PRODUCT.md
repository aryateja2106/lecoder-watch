# LeSearch Mesh — the product, in one place

**Status: canonical.** This is the only document that defines what LeSearch Mesh is:
its names, surfaces, screens, daemon capabilities, commands, install contract,
permissions and non-goals. Everything else under `docs/` is a runbook or a dated
record. When a change adds or removes a screen, a daemon module, a `mesh` verb or a
capability, it edits this file **in the same PR**; `scripts/check-product-spec.sh`
fails when the inventory here and the tree disagree.

Written 2026-09-06 against the `release/lesearch-mesh-0.6` tree. Where a feature is in
flight it is marked **0.6**; where it is proposed and unbuilt it is marked **proposed**.
Nothing unmarked is a claim that it exists, was built and was run.

---

## 0. How an agent uses this document

1. Read sections 1–3 before touching anything. They are short.
2. Find your surface in section 7 (screens) or section 5 (daemon) or section 6 (CLI).
   Each entry names the file, the job, the primary action and the single source it
   reads from. Do not invent a second source for something already listed.
3. If the work changes the inventory, edit this file and run
   `sh scripts/check-product-spec.sh`, then `./.claude/scripts/gates.sh fast`.
4. Visual design (spacing, type, colour) is **not** here. Native UI taste lives in the
   `meshwatch-ui-taste` skill; the brand in `launch/BRAND-KIT.md`; layouts to be
   tweaked by hand are made with `/design`. This file holds structure and rules.
5. Dated documents (`*-2026-09-03.md`, `PROGRESS.md`, `HANDOFF.md`) are archaeology.
   Undated documents are current. `docs/README.md` says which is which.

---

## 1. What it is

**Use your Mac from your wrist.** An AI coding agent stops to ask a question; the wrist
buzzes; the person reads the question, answers it, and the agent carries on with the
laptop closed. When the machine itself is needed there is a real terminal, a real
trackpad and the screen, on the phone and on the watch.

No account. No cloud relay. No server of ours in the data path. The phone talks
directly to a small daemon on a machine the user owns, over their own Tailscale mesh or
LAN.

**Who it is for.** People who want to use AI agents every day, whether or not they call
themselves developers. Every other way to reach a machine from a phone assumes SSH keys,
`known_hosts` and port forwarding. The promise here is one pasted command to install and
one to remove; a feature that needs the user to understand networking is not finished.

**Two loops, in priority order** (from `CONTEXT.md`):

1. **Reach your machines from anywhere** — pointer, keyboard, screen, files, shell.
2. **Run agents 24/7 and answer them when they get stuck** — the notification, the
   Live Activity and the complication exist so that "an agent is waiting on you"
   reaches the wrist and is answerable in one tap.

Loop 2 is the differentiator. Every surface that shows "what needs me" reads from one
function, `sessionsNeedingAttention(from:)` in `Shared/Models.swift`.

---

## 2. Names

| Role | Exact form | Notes |
| --- | --- | --- |
| Company | **LeSearch AI** | GitHub org `LeSearch-AI`. |
| Product | **LeSearch Mesh** | The only public product name. Tagline: *Less Search. More Agents.* |
| Daemon | `meshd` | One per machine. Bun + TypeScript. Port `8899`. |
| Command line | `mesh` | `~/.mesh/bin/mesh`. Every surface is a client of the same daemon API. |
| Mac menu bar app | **LeSearch Mesh** (`LeSearch Mesh.app`) | Xcode target `MeshDesktop`, bundle id `com.lecoder.meshdesktop`. |
| iPhone + Watch app | **LeSearch Mesh** | Xcode target `MeshWatch`, bundle prefix `com.lecoder.meshwatch`. App Store Connect app `6803438426`. TestFlight `pVYPTxc7`. |
| Input helper | `mesh-input` | Swift binary, macOS only, owns the Accessibility grant. |
| Local agent | `mesh-code` | **proposed** (PR #119): a local coding agent driven through the daemon. |
| Internal lane | *Mesh Apps* | The daemon serving and installing apps the user asked an agent to build. Internal name only. |
| Frozen legacy | `MeshWatch`, `com.lecoder.*`, `meshwatch://` | Xcode targets, bundle ids and the URL scheme. **Never change**: Apple does not let a deleted App ID be reused, and the scheme is what the pairing QR carries. Never in public copy. |
| Reserved, retired | `lecoder`, `lesearch` (the Rust control plane), `LeCoder` | Names of earlier products. Not to be reused for anything new. |

---

## 3. Surfaces and the install contract

| Surface | How a person gets it | Where it lives | How it is removed | Status |
| --- | --- | --- | --- | --- |
| Daemon, CLI, hook tools | `curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh \| sh` | `~/.mesh/` (`meshd/`, `bin/`, `hooks/`, `token`, `hosts.json`, `apns/`, `apps/`); launchd `ai.lesearch.meshd` on macOS, systemd `--user` on Linux | `mesh uninstall --yes` (prints exactly what it deletes first), or `install.sh --uninstall --purge` | shipped, `mesh-install` v0.5.2 (2026-08-27); 0.6 payload in flight |
| iPhone + Watch app | TestFlight public link | App Store | Delete the app | shipped to TestFlight; the public build lags (external testers need Beta App Review) |
| Mac menu bar app | `mesh desktop` opens it; distribution of the `.app` itself | `/Applications/LeSearch Mesh.app` | Drag to Trash; "Start at login" unregisters itself | **built, not distributed** |
| Web console | Menu bar → *Open web console*, or `http://127.0.0.1:8899/desktop` | Served by the daemon | Nothing to remove | shipped |
| Website | `https://mesh.lesearch.ai` | `web/` on Vercel (`lesearch-mesh-web`) | — | live (DNS resolves as of 2026-09-06) |

**The contract.** Everything the daemon side installs is under one directory, `~/.mesh`,
plus one service registration and one PATH line, and one command removes all three. No
`sudo`. No global npm. The installer is idempotent (`--upgrade` reinstalls in place and
keeps the token, so a machine stays paired across an upgrade). The install URL above is
compiled into the phone's pairing screen, the Mac app and the daemon's own `/doctor`
advice; **it does not change**, whatever the source repository is called.

---

## 4. Shape

```
Watch ──URLSession──▶ meshd ──▶ mesh-input (CGEvent/AXUIElement) ──▶ macOS
  └── off-tailnet ──WCSession──▶ iPhone ──HTTP──┘
                                   meshd ──APNs (direct, ES256)──▶ iPhone / Watch
```

- **meshd** owns stats, agent sessions (rmux/tmux/cmux/herdr), input injection, screen
  capture, apps, clipboard, volume, power, push, the knowledge base, pairing, doctor,
  redaction, chat and hand-off. Bearer auth, fail-closed, constant-time compare.
- **iOS app** polls every machine, relays snapshots to the watch, owns the machine list
  and the tokens (Keychain via `SecureStore.swift`).
- **Watch app** talks to the daemon directly when it can, else through the phone. The
  watch has no Tailscale and iOS suspends the phone app within seconds, so the watch
  *asks* (sendMessage relaunches the phone app); it never waits to be told.
- **Live Activity, Lock Screen, Dynamic Island, watch Smart Stack, complication** are
  renderings of the same attention function; nothing computes its own answer.

---

## 5. The daemon

### 5.1 Capabilities

`GET /health` lists what a daemon can do. Clients gate on this list, never on a version
string, and when a capability is missing they name the symptom the user sees
(`Shared/DaemonCapabilities.swift`). The 0.6 list, in the daemon's own order:

`events` `newPane` `paneTarget` `usage` `agents` `cmux` `herdr` `tailscale` `kb`
`screenPeek` `input` `files` `push` `pair` `doctor` `wake` `screenRegion` `openUrl`
`power` `laPush` `sessionStatus` `paste` `captureJoin` `redact` `chat` `apps` `handoff`

### 5.2 Modules (`install/payload/meshd/`)

One capability is one module plus a two-line patch to `server.ts` (an import and a
route line). That is the rule for adding anything.

| File | Owns |
| --- | --- |
| `server.ts` | Routing, the capability list, the Origin/Host guard that runs before auth, sessions and stats. |
| `auth.ts` | Fail-closed bearer check, constant-time. Loopback is exempt only after the browser guard has passed. |
| `doctor.ts` | `GET /doctor` and `POST /doctor/fix`. Every check exercises the real path (a green row means it works now). Checks: `token`, `input`, `screen`, `mux`, `push`, `exposures`, `agents`. |
| `input.ts` / `input-linux.ts` | Pointer, keyboard, media, windows, power, clipboard, screen capture and regions. Linux uses xdotool/xclip and screen capture via scrot. |
| `push.ts` | APNs direct from the daemon (ES256), one-buzz dedupe, Live Activity push-to-start tokens. |
| `pair.ts` / `qr.ts` | One-use 8-character codes, ten minutes; `/pair/claim` is the only route that answers without a token. The QR carries `meshwatch://pair?h=&p=&c=`. |
| `files.ts` / `files.html` | File browser and the daemon-served file page. |
| `kb.ts` | Knowledge base: SQLite FTS5, read federation across hosts. |
| `apps.ts` | Mesh Apps: publish a static web app, register a built native app, wireless (OTA) install links. |
| `chat.ts` | **0.6** Transcript chat: talk to a running coding agent from the phone. |
| `handoff.ts` | **0.6** Hand a session to a different agent CLI via `HANDOFF.md` in the working directory. |
| `redact.ts` | **0.6** Every line leaving the machine is redacted; exposures are counted by fingerprint, never by value. |
| `codex-state.ts` | Reads why Codex stopped and when its window resets. |
| `cmux-bridge.ts` / `herdr.ts` | Multiplexer adapters. |
| `wol.ts` | Wake-on-LAN. |
| `telemetry.ts` | One anonymous heartbeat a day at most; `MESHD_TELEMETRY=off` silences it. |
| `desktop.html` | The web console: capture plus input in a browser on the Mac itself. |

### 5.3 Helpers (`install/payload/bin/`)

`mesh` (the CLI), `mesh-input.swift` (the HID helper), `mesh-event`, `mesh-hook`,
`mesh-agent-run`, `mesh-codex-notify` (the four ways an agent tells the daemon
something happened), `mesh-kb`, `mesh-self-check`, `start-cmux-bridge`.

### 5.4 Security rules that are not negotiable

- Auth is fail-closed. No token configured means off-box requests are refused.
- A request with an `Origin` header or a cross-site `Sec-Fetch-Site` is rejected before
  the loopback exemption; the `Host` header is validated against known addresses. This
  is the DNS-rebinding defence and it runs before auth.
- Machine tokens live in `~/.mesh/token` and `~/.mesh/hosts.json`; on the phone, in
  the Keychain. They are never printed and never committed.
- The terminal bridge on `7820` requires the same token as the daemon (**0.6**).
- Secrets an agent prints are redacted before they reach APNs, the events file or the
  watch (**0.6**).

---

## 6. The command line (`mesh` 0.6.0)

| Group | Verbs |
| --- | --- |
| Getting started | `setup` (daemon → doctor → pair → status), `desktop`, `shellenv` |
| Hosts | `pair`, `hooks [status\|install\|remove]`, `hosts`, `host add\|rm\|default` |
| Sessions | `ls`, `peek`, `send`, `key`, `new`, `kill` |
| Status | `status`, `usage`, `health`, `doctor [--fix]`, `events`, `exposures` |
| Maintenance | `upgrade`, `token rotate`, `uninstall` |
| Apps and skills | `skills`, `apps config\|publish\|add\|list\|install\|ota\|remove` |
| Global | `-H <host>`, `--json`, `version` |

`--json` exists so that agents and scripts read the same answers people do.

---

## 7. Screens

Each entry: **file** · job · primary action · what it reads. Anything shown in two
places comes from one function.

### 7.1 iPhone (target `MeshWatch`, iOS 26)

**App shell** — `MeshRelayApp.swift`, `ContentView.swift`. Five tabs: Machines,
Monitor, Terminal, Remote, Settings. `MeshStore.swift` is the single store: the machine
list, polling, snapshots relayed to the watch. `AppLock.swift` locks the app behind
Face ID. `BackgroundRefresh.swift` keeps snapshots warm. `PhoneConnectivity.swift` is
the watch relay (WCSession). `NotificationManager.swift` registers for APNs, wires the
notification actions from `Shared/AgentNotifications.swift`, and starts Live Activities
through `LiveActivityController.swift`.

| Screen | Job | Primary action | Reads |
| --- | --- | --- | --- |
| Machines tab | Every machine on one list with live stats; an offline machine is shown honestly, not hidden | Open a machine | `MeshStore` snapshots |
| No machines | The first-run state | *Pair a machine* | — |
| Machine detail | Setup state, power, daemon version, per-service status, diagnose, wake | Fix what `/doctor` says is wrong | `/doctor`, `/health`, `DaemonCapabilities` gaps |
| Pair machine — `PairMachineView.swift`, `PairingScanner.swift` | Turn a code or a QR into a paired fleet | Scan / enter code | `/pair/claim` (returns the token **and every host in `hosts.json`**) |
| Manual bridge | Add a host by address when there is no code | Save | user input |
| Monitor tab | Usage and limits per provider at the top (**0.6**), then events; dismiss one or clear all | Read | `/usage`, `/events`, `Shared/LimitHelpers.swift` |
| Sessions and new session | List sessions per machine; start one with a chosen CLI, working directory and task; resume a previous conversation (**0.6**) | *New session* | `/agents`, `/agents/new` |
| Session peek | Recent output of one session; the attention row when it is waiting | Answer / type | `sessionsNeedingAttention` |
| Agent chat — `AgentChatView.swift` | A conversation with a running agent: bubbles, decision cards, tool-result cards, artifacts, thinking disclosure, quick-command pills (**0.6**) | Send / decide | `/chat`, `Shared/RiskClassifier.swift` for the decision cards |
| Terminal tab — `TerminalView.swift` | A live terminal over the bridge; the fallback block when the bridge is unavailable | Type | bridge `:7820` (token cookie, **0.6**) |
| Remote tab — `RemoteScreenView.swift` | Screen, trackpad gestures, zoom to a region that arrives sharp | Tap / drag / zoom | `/screen.jpg`, `screenRegion`, `Shared/ScreenZoom.swift` |
| Files — `FileBrowserView.swift` | Browse and open files on a machine | Open | `/files` |
| Exposed secrets — `ExposedSecretsScreen.swift` | **0.6** What the daemon redacted, by kind and fingerprint; mark rotated | Mark rotated | `/exposures` |
| Mesh Apps | Apps published or added on a machine; install one on this phone, with or without a cable | Install | `/apps` |
| Voice — `VoiceInput.swift`, `VoiceTranscriber.swift` | One sheet: live editable transcript, Stop/Resume, Send; recordings kept (last five) with *Transcribe again* (**0.6**) | Send | Speech framework, `Shared/VoiceSegments.swift` |
| Settings tab | Quick commands, pinned limits, app lock, the wireless-install guide | — | UserDefaults |

`ShellSafeText.swift` is the one place text typed on the phone is made safe for a shell.

### 7.2 Apple Watch (target watchOS 10)

**App shell** — `MeshWatchApp.swift`, `WatchViews.swift` (root, machines, sessions,
events, usage, type sheet), `WatchMeshStore.swift` (the store), `WatchLink.swift` and
`WatchLinks.swift` (reach the daemon directly, else via the phone; the connection phase
has a grace window so `isReachable` flapping does not read as "offline"),
`WatchNotifications.swift`.

| Screen | Job | Primary action | Reads |
| --- | --- | --- | --- |
| Root | Machines, then sessions | Open | store |
| Machines list | Each machine, reached directly when possible | Open | `/health`, `/stats` |
| Sessions | State chip per session; the attention row first | Answer | `sessionsNeedingAttention` |
| Agent live | Follow one session's output; crown-scrollable | Type / dictate | `/agents`, `peek` |
| Type sheet + dictation | Text into a session, or the system dictation | Send | `paste` / `send` |
| Events | Recent agent events | Read | `/events` |
| Usage | Limits per provider as gauges | Read | `/usage` |
| Remote hub — `RemoteView.swift` | Screen peek, keyboard, keys, media, system, apps, windows, clipboard | Act | `input` routes |
| Open on Mac | Push the current thing to the Mac's screen | Open | `openUrl` |

The watch ships **no Speech framework**; dictation is the system text field. That is why
on-device intent (section 9) takes text, not audio.

### 7.3 Mac menu bar (target `MeshDesktop`, macOS 14)

`MeshDesktopApp.swift` — three jobs and no fourth: show whether this Mac's daemon is up
(a filled dot when it answered in the last 25 seconds, hollow otherwise), put every
permission behind one button, print a pairing QR. `LSUIElement`, no Dock icon, no
settings. `LocalDaemon.swift` is the whole network layer: loopback only, no token.

| Window | Job | Primary action | Reads |
| --- | --- | --- | --- |
| Menu | Status line (`meshd 0.6.0 · doctor 5/7`), *Permissions…*, *Pair iPhone…*, *Open web console*, *Start at login*, *Quit* | — | `/health`, `/doctor` |
| Permissions — `PermissionsView.swift` | What this Mac still needs, and one button that asks for all of it in the daemon's own processes (the only place macOS will grant to) | *Grant everything* | `/doctor`, `POST /doctor/fix` |
| Pair iPhone — `PairView.swift` | QR plus the eight characters | Scan | `/pair/new`, the Tailscale address chosen on this side |

Section 8 specifies the next version of the Permissions window.

### 7.4 Widgets and cards

| Target | File | Job |
| --- | --- | --- |
| `MeshWatchWidgets` (iOS) | `MeshWatchWidgetBundle.swift`, `SessionLiveActivity.swift`, `SessionLockScreenView.swift` | The Live Activity: Lock Screen, Dynamic Island, watch Smart Stack. Starts from the phone, or by push-to-start (`laPush`). |
| `WatchWidgets` (watchOS) | `WatchGlanceWidget.swift` | The watch-face complication. Data through the App Group from `Shared/WatchGlance.swift`. |

### 7.5 Shared (`Shared/`)

`Models.swift` (wire types, pairing, attention, live-card selection), `MeshClient.swift`,
`AgentNotifications.swift` (the notification-action contract, grepped against the
TypeScript by `check-mesh-push.sh`), `AlertGating.swift` (which events buzz),
`SessionCard.swift` (the status vocabulary), `SessionActivity.swift`,
`LimitHelpers.swift`, `RiskClassifier.swift` (mirrored in the daemon's `risk.ts`),
`ScreenZoom.swift`, `SecureStore.swift`, `DaemonCapabilities.swift`, `APNsEnvironment.swift`,
`VoiceSegments.swift`, `WatchGlance.swift`.

---

## 8. Permissions — the next version of the window

**Today.** The Mac window is a flat list of `/doctor` rows under one *Grant everything*
button, plus this app's own Notifications row. Push, exposures and agents are
informational but render with the same green check as Accessibility. Nothing says
which feature a grant is *for*, and nothing distinguishes "not granted" from "we cannot
tell".

**Target** (modelled on the better Mac utilities: a *needed for what you turned on*
group, an *other permissions* group that is collapsed, per-row *Request* and *Open
System Settings*, and an honest *the app can't check this one* state):

1. `/doctor` grows three additive fields per check. Old clients ignore them; the phone's
   machine-setup section and the Mac window read the same answer.

   ```ts
   type Check = {
     ok: boolean; detail: string; fix?: string;
     required: boolean;        // false = informational; never fails the machine
     usedBy: string[];         // user-facing feature names, e.g. ["Remote control", "Screen peek"]
     checkable: boolean;       // false = the daemon cannot observe this grant
     requestable: boolean;     // true = POST /doctor/fix can make macOS ask
   };
   ```

   | Check | required | usedBy | requestable |
   | --- | --- | --- | --- |
   | `input` (Accessibility) | yes | Remote control, Agent chat decisions, Type from the watch | yes |
   | `screen` (Screen Recording) | yes on macOS | Screen peek, Zoom to text, Web console | yes |
   | `token` | yes | Everything off this Mac | no (fix is a command) |
   | `mux` | yes | Agent sessions | no |
   | `push` | no | Alerts when the app is closed | no |
   | `agents` | no | Start a session with… | no |
   | `exposures` | no | Exposed secrets | no |

2. The window groups rows: **Needed for what you use** (required, failures first) and
   **Other permissions** (collapsed by default, with *Nothing you use needs this right
   now* when `usedBy` is empty). Each row shows *Granted* / *Not granted* / *Can't be
   checked*; a not-granted requestable row gets *Request*; the two TCC rows keep their
   deep links. *Grant everything* stays at the top: it is the one button that works,
   because the daemon's processes ask. The footer says *macOS may ask to reopen the app
   after granting*, because it does.
3. The Mac's own Notifications row stays app-side (it is this app's grant, not the
   daemon's) and lands in *Other permissions* with `checkable: true`.

Files: `install/payload/meshd/doctor.ts`, `MeshDesktop/LocalDaemon.swift`,
`MeshDesktop/PermissionsView.swift`, and `scripts/check-mesh-doctor.sh` gains the
assertion that every check carries the four fields. The phone's setup section adopts
`usedBy` in a following slice.

---

## 9. On-device intent — Needle (proposed)

**The problem.** A person on the watch says or types *"tell claude yes"*, *"restart the
mac mini"*, *"paste this into the terminal"*. Today that text has to become a specific
daemon call by the person tapping through Remote → System → Restart. The phone and watch
should turn plain language into the call themselves, with no round trip to a large model
and no cloud.

**The tool.** [Needle 2](https://huggingface.co/Cactus-Compute/needle2) (Cactus Compute,
Apache-2.0): a 45M-parameter tool-calling model that is one 14 MB binary and runs a
session in about 28 MB of RAM. Text in, JSON out, constrained by a byte-level grammar
compiled from the declared tool schemas, with a calibrated confidence score and a
retrieval head that shows the model only the top five tools per turn from a larger
catalogue. It ships as static libraries for `ios-arm64`, `ios-sim-arm64`,
`watchos-arm64`, `macos-arm64` and `tvos-arm64`, plus a `macos-arm64/needle` CLI, and
LoRA fine-tuning runs on Apple Silicon (`pip install "cactus-needle[train,metal]"`). It
is text-only, which matches the standing decision that the local brain stays text-only.

**The design.**

1. **One tool catalogue**, `intent/mesh-tools.json`, generated from this document's
   section 5 and 6: `answer_agent(session, decision)`, `send_text(session, text)`,
   `send_key(session, key)`, `new_session(machine, cli, cwd, task)`, `kill_session`,
   `peek`, `wake(machine)`, `power(machine, sleep|restart|shutdown)`, `volume`,
   `media`, `paste`, `open_app`, `open_url`, `screen_peek(region)`, `switch_machine`.
   Every tool is a daemon route that already exists; Needle adds no capability, it
   removes taps. Enums come from live data (machine names, session names, installed
   agent CLIs) and are compiled into the grammar per turn, so the model cannot name a
   machine that does not exist.
2. **Where it runs.** On the watch first (the surface with the least room for taps),
   then the phone, then inside the daemon as the router in front of the large local
   brain (`/brain`, PR #119). Same `.cact`, same catalogue, three hosts.
3. **Confidence gate.** Above the threshold, act and show the one-line receipt
   (*Sent "yes" to claude on studio*). Below it, show the top candidate as a button
   instead of acting, and — on the phone and Mac — offer to send the text to the large
   brain. A wrong action on a machine is worse than one extra tap.
4. **Risk.** Every call passes through the same classifier the chat decisions use
   (`Shared/RiskClassifier.swift`); anything the classifier marks as needing a
   confirmation gets one, whatever the confidence.
5. **Fine-tune.** `needle generate-data --tools intent/mesh-tools.json` seeds examples;
   hand-written phrases from real use are the ones that matter. `needle finetune` on the
   Mac, export a `.cact`, commit it next to the catalogue. The frozen acceptance suite
   (`intent/cases.jsonl`: phrase → expected call) runs on the Mac with the
   `macos-arm64/needle` CLI in `scripts/check-intent.sh`, so the gate needs no device.
6. **Packaging.** An XCFramework from the per-platform `libneedle.a` files. There is no
   watchOS *simulator* library in the release, so the watch simulator build compiles a
   stub that returns "unsupported here"; the check runs on the Mac CLI, not the simulator.

**Alternative considered.** Apple's Foundation Models framework gives free on-device tool
calling on iOS 26 and macOS 26, but not on watchOS. One model on all three hosts means one
dataset and one acceptance suite, so Needle is the default; Foundation Models stays a
possible fallback on the phone and Mac.

**Not yet true.** Needle has not been run on this Mac. The first slice is
`pip install cactus-needle`, the bundled `wearable` environment against ten of our
phrases, and the numbers from that run — before any code lands in the apps.

---

## 10. Non-goals

- **A cloud relay.** If the phone cannot reach the machine, neither can we. That is the
  design.
- **VNC.** The daemon already serves screen and input over bearer-authed HTTP; setup never
  asks anyone to enable Screen Sharing.
- **An account system.** Pairing is a code the user's own machine printed.
- **Vision models on the local brain.** Text-only, by decision (2026-09-03).
- **A second answer to "what needs me".** One function.

---

## 11. Rules that outrank a green build

1. **Verify by running, not by building.** Three features shipped correct, compiling and
   dead. Every claim has a `scripts/check-*` that proves it without hardware where
   possible, and a device run where not.
2. **Gate on capabilities, name the symptom.** Never compare version strings; when a
   capability is missing, say what the user sees (*Zooming can't sharpen text*).
3. **The daemon is the source of truth for setup.** `/doctor` exercises the real path.
   A GUI never claims a grant on the daemon's behalf; macOS grants TCC to the process
   that asks.
4. **One module, two lines.** A daemon capability is its own file and a two-line patch to
   `server.ts`.
5. **Nothing leaves the machine unredacted.**
6. **`CONSTRAINTS.md` is the floor.** Do not weaken it to make a change pass.

---

## 12. Open decisions (owner: Arya)

1. Land 0.6 (PR #124), then the repository reset in `docs/product/RESET-2026-09-06.md`.
2. Ship the Mac menu bar app: notarised `.app` in the `mesh-install` release, installed
   by `mesh desktop` when absent, or a Homebrew cask. One of these.
3. Submit the newest TestFlight build for Beta App Review so the public link stops
   serving August.
4. Needle: approve the first slice in section 9 (a Mac-only measurement, no app code).
5. The permissions window in section 8: approve the four fields; then it is one slice.
