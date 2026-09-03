# Screen crawler — every screen, every action, every release

*Design, 2026-09-03. Judged from two independent designs and four adversarial critiques; everything below is either measured on this Mac or marked as the thing a phase proves.*

## 1. Goal

A local-first pipeline that walks **every screen** of an iOS app, presses every safe control, watches what happens, gets back the way a user would, and leaves behind one folder per screen (screenshot, accessibility tree, action ledger, model-written annotation) plus **one index a cloud model reads in one sitting**. It runs for every release we cut (hours are fine), diffs release against release so a screen an agent silently broke is caught, and points at competitor App Store apps on the phone with the same layout so their behaviour is collected screen by screen.

Three uses, one tool: reviewing our app, building new apps, studying competitors.

## 2. Verified constraints

Device-stack facts (what `devicectl` can and cannot do, why iPhone Mirroring is pixels-only, the exact 4016 error, the untested `pymobiledevice3` probe) live in [HANDOFF-2026-09-01-notifications-and-device-testing.md](HANDOFF-2026-09-01-notifications-and-device-testing.md) and are not repeated here. That file is on commit `d65f5b1` (branch `fix/remote-trackpad-back-swipe`), not on `main` yet — see decisions.

Measured for this design (2026-09-02/03, read-only, nothing booted):

| Fact | Evidence |
|---|---|
| Xcode 26.6 (17F113) + Xcode-beta 27.0; xcodegen 2.46.0; bun 1.3.14; `uvx`, `ffmpeg`, `jq` present | `xcodebuild -version`, `xcodegen --version`, `which` |
| Simulators: `LeSearch Preview` + `iOS265-repro` (iOS 26.5), `iOS27-repro` (27.0); runtime id `com.apple.CoreSimulator.SimRuntime.iOS-26-5`; device type `com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro` | `xcrun simctl list` |
| `LeSearch Preview` is **paired to the live fleet** (netIdentity blob names this Mac and dataflowagents; tokens in the sim Keychain survive reinstall) | critique evidence, plist inspection |
| XCUIAutomation: `XCUIApplication(bundleIdentifier:)` is the designated initializer; `activate`, `launchArguments`, `snapshot()`, `performAccessibilityAudit` (iOS 17+), `XCUIDevice.shared.system.openURL(_:)` all public | `XCUIApplication.h:35,77,93,149`, `XCUIElement.h:358`, `XCUISystem.h:13` |
| `TEST_RUNNER_<VAR>` env is stripped and passed to test runner processes | `man xcodebuild` |
| `xcrun xcresulttool export attachments --path … --output-path …` writes files + `manifest.json` | `--help` |
| `idb_companion` 1.1.8 (brew, Aug 2022) has **zero** `accessibility_action` symbols, HID only, and prints an objc duplicate-class warning against Xcode 26.6 | `strings`, `--version` |
| meshd env knobs: `MESHD_PORT/HOST/TOKEN/EVENTS_PATH`, `MESH_MUX`, `CMUX_BIN`, `CMUX_SOCKET_HINT`; the mux is invoked as a **shell string** `${MUX} list-sessions …` | `install/payload/meshd/server.ts:17-34,174-605` |
| meshd executes absolute-path binaries for `/system` (pmset, osascript shutdown/restart), `/open`, `/apps` POST (`open -a`), `/clipboard` (pbcopy/pbpaste), `/volume`, `/screen.jpg` (screencapture), `/fs/mkdir`, `/fs/move`, `/doctor/fix`, `/wake`, `/push/*` — none of it depends on `HOME` | `input.ts:161-193,246,359-430,458-483`, `files.ts:105-120`, `doctor.ts:100`, `server.ts:994` |
| Only the pointer helper is `HOME`-relative: `~/.mesh/bin/mesh-input`, reused if its mtime is newer than the source | `input.ts:37,85-86` |
| `/pair/new` is loopback-only and `/pair/claim` adopts the whole `~/.mesh/hosts.json` fleet | `pair.ts` header, `HOSTS_PATH` |
| The app: zero `accessibilityIdentifier`s; AppLock key `mesh.requireBiometrics.v1` in `UserDefaults.standard`, on by default, fails open without passcode/biometry (simulator default); Pair sheet needs address **and** code, `Pair` is disabled otherwise; deep link `meshwatch://pair?h=&p=&c=` prefills the sheet and the user taps `Pair`; `-uiRemote` selects the Remote tab | `iOS/AppLock.swift:22-38`, `iOS/PairMachineView.swift:14-38,71`, `iOS/MeshStore.swift:872-885`, `iOS/ContentView.swift:10,27` |
| The app calls: `/agents…`, `/apps`, `/clipboard`, `/displays`, `/doctor(/fix)`, `/events`, `/fs`, `/fs/mkdir`, `/health`, `/input`, `/la/token`, `/open`, `/push/register`, `/screen.jpg`, `/stats`, `/system`, `/tailnet`, `/usage`, `/volume`, `/wake` | `Shared/MeshClient.swift` |
| `scripts/check-all.sh` runs **every** `scripts/check-*.sh`; CI runs `check-all.sh` on the apps job (`ci.yml:131`); `check-docs-index.sh` scans `docs/*.md` only and resolves links into subfolders | read |
| `.claude/scripts/gates.sh` and `docs/factory/` do not exist on `main`; `*.xcodeproj`, `build/`, `DerivedData/` are gitignored; `build/DerivedData` holds a 27 Aug (stale) simulator build | `ls`, `.gitignore` |
| Local brains: Mference `:8080` (text-only, `qwen3.6-35b-a3b`) and LM Studio `:1234` (start only via `svc`) both answered `/v1/models` on 2026-09-02; `GET /brain` (PR #119) is not on `main` | critique evidence, `grep` |

### Refuted — do not re-propose

| Idea | Why it is dead |
|---|---|
| `idb ui tap "<label>"` on the simulator | needs the `accessibility_action` gRPC method; the installed companion has none. HID-by-coordinate is all it can do, and a newer companion is a new dependency. |
| "Spare meshd with an isolated `HOME` is a sandbox" | `/system`, `/open`, `/apps`, `/clipboard`, `/volume`, `/fs/*`, `/wake`, `/push`, `/doctor/fix` exec real binaries regardless of `HOME`; rmux/tmux sockets are per-user in `/tmp`. |
| iPhone Mirroring + meshd `input` as the pixels-only fallback | the helper needs per-binary Accessibility trust (voided on rebuild), `/screen.jpg` needs Screen Recording a shell-started bun lacks, and Mirroring dies the moment the phone is unlocked — you cannot watch an unlocked phone over it. |
| A `-crawl` launch argument that disables AppLock | a lock bypass in the shipped binary. `simctl spawn … defaults write` flips the same key with zero product code; on the phone it is a one-time Settings toggle. |
| Crawling **our** app on the phone as the release gate | the phone's install is paired to the real fleet with no erase; the simulator covers the same screens and code. |
| A label-regex denylist as the safety boundary for our app | `continue`, `Enter`, `Click`, `Send`, `Kill session`, `Wake`, app names — plain labels that act on real machines. The boundary must be a daemon that cannot act. |
| An LLM map-reduce to build the index | a template render of `index.json` is already ≤ 15K tokens for 100 screens. |

## 3. Architecture

**First rule: a MeshWatch paired to a real daemon is a Mac controller; the crawler never runs against one.** Every tap on the Terminal, Remote, Monitor, Files or Settings screens is an HTTP call that runs a binary on the paired machine. The crawler only ever sees (a) an erased, unpaired app, or (b) an app paired to the **sandbox daemon** below.

```
project.yml ─xcodegen─▶ MeshWatch.xcodeproj  (+ target MeshWatchCrawler, type bundle.ui-testing, NO host app)
                                     │ xcodebuild build-for-testing (once per version)
                                     ▼
              build/DerivedData/Build/Products/MeshWatchCrawler_*.xctestrun
                                     │
scripts/crawl.sh ────────────────────┤ round loop: xcodebuild test-without-building -xctestrun … (≤ N screens per round)
  ├─ sim: simctl create/erase/boot/install/privacy/spawn defaults         │  TEST_RUNNER_CRAWL_* env
  ├─ device: DEVELOPER_DIR=Xcode-beta, -destination id=<udid>              ▼
  └─ after a round: read state.json (sim, direct write) or        MeshWatchCrawler-Runner.app  (XCUITest)
     xcresulttool export attachments (device)                      XCUIApplication(bundleIdentifier: CRAWL_BUNDLE_ID)
                                                                   snapshot() · screenshot() · tap/swipe/typeText
                                                                            ▼
                                                     MeshWatch (sim, paired to the sandbox daemon on :8898)
                                                     or any competitor bundle on the phone
                                                                            │
                       ~/.mesh/crawls/<bundle>/<version>+<build>/<target>/  ◀── screens/, state.json, index.json
                                     │
scripts/crawl-index.ts  annotate | index | diff  ── local brain over files (never in the loop) → annotation.json, INDEX.md, DIFF.md
scripts/check-screen-crawl.sh ── SKIP unless MESH_CRAWL_GATE is set; reads DIFF.md; new check-*.sh, nothing existing edited
```

Files, all of them:

| File | What | Size |
|---|---|---|
| `project.yml` block | the `MeshWatchCrawler` target + scheme (below) | 20 lines |
| `Crawler/CrawlTests.swift` | two tests: `testCrawl` (BFS) and `testAttachProbe` (60-second competitor gate) | ~60 |
| `Crawler/Crawler.swift` | BFS, action enumeration, denylist, overlay policy, back ladder, replay | ~600 |
| `Crawler/Snapshot.swift` | tree walk → JSON, skeleton hash, dHash, `CrawlStore` (direct write + `XCTAttachment`) | ~300 |
| `scripts/crawl.sh` | orchestrator: build once, prepare target, round loop with a wall-clock kill, export attachments | ~120 |
| `scripts/crawl-index.ts` | `annotate` (brain over files), `index` (INDEX.md), `diff` (DIFF.md + exit code); bun, no packages | ~350 |
| `scripts/check-screen-crawl.sh` | the gate | ~40 |
| `install/payload/meshd/server.ts` | `MESHD_SANDBOX=1` guard, ~6 lines (decision 1) + `scripts/check-daemon-sandbox.sh` | ~6 + 30 |
| `docs/screen-crawler.md`, `docs/crawls/README.md` | this doc; the per-release summary index | — |

Zero new dependencies. Not added: Appium, WebDriverAgent, fb-idb, Maestro, any npm package.

### The runner target (host-less, like WebDriverAgent)

```yaml
targets:
  MeshWatchCrawler:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - path: Crawler
    info:
      path: Generated/Crawler-Info.plist
      properties: {}
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.lecoder.meshwatch.crawler
        TARGETED_DEVICE_FAMILY: "1"
    # No `dependencies: [MeshWatch]` on purpose. The runner attaches by bundle id, so it
    # never needs a host app installed beside it, and a competitor round on the phone must
    # not reinstall MeshWatch over the tester's TestFlight build.
schemes:
  MeshWatchCrawler:
    build:
      targets:
        MeshWatchCrawler: all
    test:
      targets:
        - MeshWatchCrawler
      config: Debug
```

The runner never calls `XCUIApplication()`; always `XCUIApplication(bundleIdentifier: cfg.bundleId)`, so the code path is identical for our app on the simulator, our app on a phone, and a competitor. Being host-less also means any archived `.app` of any version can be installed and crawled — that is what makes release-to-release diffs of old builds possible. If Xcode refuses a UI-test bundle with no target application, phase 1 learns it in the first build; the fallback is the `MeshWatch` dependency for simulator builds only.

### The sandbox daemon (phase 2)

The real `server.ts` from the checkout, run so that it answers everything and does nothing:

```sh
SB=$HOME/.mesh/crawls/_sandbox; mkdir -p "$SB/home/.mesh/bin"
printf '#!/bin/sh\ncat >/dev/null\n' > "$SB/home/.mesh/bin/mesh-input"; chmod +x "$SB/home/.mesh/bin/mesh-input"
touch "$SB/home/.mesh/bin/mesh-input"                    # newer than the source → input.ts:85 keeps the stub
# fakemux: canned answers in the exact -F formats server.ts uses (L174, L184, L451, L499); every other verb exits 0
HOME="$SB/home" MESHD_SANDBOX=1 MESHD_PORT=8898 MESHD_HOST=127.0.0.1 MESHD_TOKEN=throwaway \
  MESH_MUX="$SB/fakemux" CMUX_BIN=/usr/bin/false CMUX_SOCKET_HINT=/nonexistent \
  bun run install/payload/meshd/server.ts > "$SB/meshd.log" 2>&1 &
```

Four layers, each structural:

1. **`MESHD_SANDBOX=1`** (new, ~6 lines after the `authed()` check): every non-`GET` except `/events` and `/agents/*` returns `{ok:true, sandbox:true}`; `GET /clipboard` returns `{text:""}`; `/health` reports `sandbox:true`. That neuters `/input`, `/system`, `/open`, `/apps` POST, `/clipboard`, `/volume`, `/fs/mkdir|move`, `/doctor/fix`, `/wake`, `/push/*`, `/la/token`, `/kb`. It is capability-reducing, env-gated, never on in a shipped daemon, and doubles as a demo mode for screenshots. Covered by a new `scripts/check-daemon-sandbox.sh` (boot on a random port, `POST /system {action:"shutdown"}` → 200 `sandbox:true`).
2. **`MESH_MUX=fakemux`**: `list-sessions`/`list-panes`/`has-session`/`capture-pane` answer with two canned sessions and a fixture pane; `send-keys`, `kill-session`, `new-session`, `split-window` exit 0. The Terminal tab is populated and every button on it is inert. `CMUX_BIN=/usr/bin/false` makes cmux discovery fail closed.
3. **Isolated `HOME`**: no `hosts.json` (pairing adopts nothing but the sandbox), no real events file, no real kb.sqlite, and the stub helper above.
4. **The crawler still denylists app-local irreversibles** (`unpair|forget|remove|delete|reset|sign ?out|revoke|rotate`) because those change the crawl's own world, not the Mac.

Seeded content: `POST /events` on the sandbox (the shape `addEvent` accepts, `server.ts:1009`) creates a needs-approval card so the approval screens exist. `GET /screen.jpg` from a shell-started bun returns whatever `screencapture` is allowed to see (wallpaper without a Screen Recording grant, possibly the real screen with one) — decision 5.

Pairing the simulator to it, zero product code: `CODE=$(curl -s http://127.0.0.1:8898/pair/new | jq -r .code)`, then the runner (with `CRAWL_SEED_URL="meshwatch://pair?h=127.0.0.1&p=8898&c=$CODE"`) calls `XCUIDevice.shared.system.open(url)` after launch, taps `Pair`, waits for the `Paired` title, taps `Done`. Sequenced inside the test process, so no orchestrator/runner race.

## 4. Crawl algorithm

Deterministic BFS over screens, DFS over the actions of one screen, frontier persisted after every action. **No model in the loop**: the tree decides what exists, the crawler decides what to press, the brain annotates afterwards. That is what keeps runs replayable and the token budget entirely for annotation.

```
state.json = { round, screens: {id → Screen}, frontier: [id], edges: [{from, action, to, outcome}] }
Screen = { id, kind: screen|overlay, title, tab, depth, firstPath: [Action], treeless, status: done|partial|unreachable, actions: [Action+outcome] }
Action = { id: "A7", type, identifier, label, centerNorm: [x,y], scrollPage }   // enough to replay without identifiers
```

**Round entry.** `app.launch()` → settle → capture root. If `state.json` exists in `CRAWL_OUT`, load it (resume is implicit; a fresh run is `rm -rf` of the folder). If `CRAWL_SEED_URL` is set and the state is empty, run the seed. Pop the frontier; if the popped screen is not the current one, replay its `firstPath`. Stop the round at `CRAWL_ROUND_SCREENS` finished screens or `CRAWL_ROUND_SECONDS`; flush `state.json` after every action outcome.

**Settle.** XCUITest already waits for quiescence before each event. On top: wait ≤ 2 s for `app.state == .runningForeground`, then 400 ms. `.notRunning` after an action → outcome `crash`, relaunch.

**Capture.** `shot.png` (`XCUIScreen.main.screenshot()`), `tree.json` (one `snapshot()` walk, depth ≤ 14, ≤ 1,500 nodes; `debugDescription` as `tree.txt` if `snapshot()` throws), `meta.json` (nav title, selected tab, overlay flags, content hash, `performAccessibilityAudit` issues when `CRAWL_AUDIT=1`). Scroll discovery: on a screen with a `ScrollView`/`Table`/`CollectionView`, `swipeUp` up to 3 pages, snapshot each, union the actionable set (each action remembers its `scrollPage`), `swipeDown` back and confirm the id is unchanged.

**Enumerate (ordered, deduplicated).** Types: Button, Link, Cell, TabBar>Button, Switch/Toggle, SegmentedControl>Button, MenuButton, MenuItem, DisclosureTriangle, TextField/SecureTextField/SearchField/TextView; Picker/Slider observe-only; Image/StaticText only as the sole hittable child of a Cell. Require `enabled`, on-screen, ≥ 8×8 pt. Dedup key `(type, identifier, normalized label, frame/8)`. Order: tab bar → nav bar → content top-to-bottom, left-to-right. Cap `CRAWL_ACTIONS_PER_SCREEN` (40); overflow recorded `not_exercised`. Re-location at tap time: `identifier` → `type + label` predicate → **coordinate tap** at the recorded centre (the path that works on an app with zero identifiers). `isHittable` is asked only for the element about to be tapped (each query is an IPC round trip).

**Per action.**
```
denylisted            → record skipped(denylist), continue
text field            → tap, typeText("crawl"), dismiss keyboard, record; never submit
switch/toggle         → tap, capture, tap again (restore), record both
tap → settle → after = capture()
  app.state == notRunning              → crash            (relaunch)
  app.state != runningForeground       → left_app         (activate(); relaunch if still not foreground)
  overlay present                      → overlay:<kind>   (its own screen, kind=overlay; dismissed by the overlay policy)
  after.id == origin.id, content same  → noop
  after.id == origin.id, content diff  → in_place_change
  after.id new                         → navigated_new    (frontier push, depth+1 ≤ CRAWL_MAX_DEPTH)
  after.id known                       → navigated_known  (edge only)
record; returnToOrigin(origin)
```

**Overlays.** `app.alerts/sheets/menus/popovers/keyboards` plus snapshot nodes of type Alert/Sheet/Dialog/Menu/Popover. Least-committal button first: `Cancel, Not Now, Later, Dismiss, Close, Done, OK, No Thanks, Skip`, then any non-denylisted button, then `swipeDown` on the sheet, then a tap outside its frame, then relaunch. Keyboards: `Return|Done|Go|Search`, then the toolbar `Done`, then swipe the keyboard down. **System prompts** (SpringBoard): `addUIInterruptionMonitor` chooses `Allow`/`OK` for `CRAWL_PERMISSIONS=allow` and `Don't Allow`/`Not Now` for `deny`; because the monitor only fires when an interaction is blocked, `XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts` is polled after each action. On the simulator `simctl privacy grant all` pre-empts most prompts (it has no `notifications` service; the monitor covers that one).

**Denylist** (`CRAWL_DENY`): `app` = the app-local irreversibles above (our app under the sandbox); `full` = `app` + `\b(erase|wipe|clear (all|history|data)|pay|buy|purchase|subscribe|upgrade|restore purchases|checkout|send|submit|post|publish|share|call|report|block|unfollow|stop|kill|shut ?down|restart|sleep|power|wake|create|open|paste|copy)\b`, SF-symbol labels `trash`, `xmark.bin`, any button inside an alert whose message matches, and every Switch observe-only (competitor apps on a real account); `off` never. Matching is over label ∪ identifier ∪ value ∪ enclosing cell label, case-insensitive. Skipped actions are recorded with the reason so the annotation can say "10 buttons, 8 exercised, 2 skipped as destructive".

**Return-to-origin ladder** (stop at the first rung that restores `origin.id`): overlay policy → nav-bar back button (`navigationBars.buttons.element(boundBy: 0)` when the title changed) → left-edge pan (`coordinate(0.01,0.5).press(forDuration: 0.05, thenDragTo: 0.9,0.5)`) → sheet `swipeDown` / `Close|Done|X` → the origin's tab → `pressButton(.home)` + `activate()` → **relaunch-and-replay** `firstPath` with the id checked after every step. A diverging replay marks the origin `unreachable` (kept in the index so the diff sees it) and moves on. Every round starts with rung 7, so the rarely-needed path is exercised constantly.

**Budgets.** `CRAWL_MAX_DEPTH` 4, `CRAWL_MAX_SCREENS` 200, `CRAWL_ACTIONS_PER_SCREEN` 40, `CRAWL_ROUND_SCREENS` 20, `CRAWL_ROUND_SECONDS` 1200, orchestrator `--hours`. Quiescence is XCUITest's own bound (up to ~60 s per event on a screen that never idles); the runner cannot pre-empt a blocked `tap()`, so the orchestrator kills a round at `CRAWL_ROUND_SECONDS + 300` and `state.json` is the truth (simulator) — on the phone, rounds are small enough (≤ 10 screens) to end before the kill so their attachments arrive. If a screen costs 40 minutes because it never idles, that is accepted for a multi-hour run; the known fix is WDA's private-API quiescence skip (`XCUIApplicationInteractionOptionSkipPreEventQuiescence` exists in the framework binary) — not built.

**Cycle detection.** A known id is never re-expanded; `(origin id, action key)` is recorded once, so replays across rounds never double-count. Frontier empty → `complete`; budget hit → `partial` with the frontier listed.

**Treeless screens** (skeleton < 4 nodes: WebView-only, the Remote tab's full-bleed screen image, canvases): photographed, hashed by dHash, given the generic gestures (back ladder, one swipe) and **not expanded**. `ponytail:` the ceiling is competitor apps that are mostly WebView; the upgrade path is one VLM `ground_elements` call from the runner to the Mac's brain for those screens only.

## 5. Screen identity

`id = sha1(bundleId | skeleton)[0..12]`, `kind ∈ {screen, overlay}`.

**Skeleton** — structural and content-blind. Pre-order walk of the snapshot, depth ≤ 12, one token per node: `type` + `#identifier` + `"label*"` **only for chrome types** (Button, TabBar children, NavigationBar — its identifier is the title —, Link, Switch, SegmentedControl, SearchField, TextField placeholder, MenuItem), where `label*` = lowercased, digits → `#`, whitespace collapsed, cut at 32 chars. Content-bearing types (StaticText, Cell, Image, TextView, Table rows beyond the first 3) contribute only their type. Frames are excluded (rotation, keyboard, Dynamic Type would fork ids). `Other`/`Group` nodes with no identifier or label collapse into their parent so SwiftUI wrapper noise cannot affect the hash. Overlays are cut out of the parent's skeleton and hashed separately with `kind: overlay` and a `parent` link, so the same Pair sheet reached from two tabs is one overlay.

So "3 machines" vs "5 machines", live terminal output, timestamps and counters give the **same** id; a screen whose buttons, tabs or title changed gives a **new** id — exactly the event the diff exists to surface.

**Content hash** — `sha1` of all labels/values, stored beside the id, never part of it. Equal → `noop`; different → `in_place_change`. Also what lets the diff say "same screen, text changed".

**Treeless fallback** — dHash of the screenshot (9×8 grayscale via CoreGraphics, 64-bit row differences; Hamming ≤ 6 = same screen); the record carries `treeless: true`, which is the flag the annotator uses to decide a screen earns a vision call.

**Cross-version pairing** — by id, then by exact nav title; anything else is `vanished`/`new`. Two genuinely different screens with identical chrome collapse into one id by design; the record keeps the first-seen screenshot only. No Jaccard thresholds, no variants list, no RENAMED heuristics until a real 0.5.x-vs-0.5.y diff is noisy.

## 6. Input and read routes per target

| | Simulator, our app (phase 1–2, the gate) | Phone, competitor App Store app (phase 3) | Phone, our app (optional, phase 4) |
|---|---|---|---|
| Input | XCUITest events in-process (`tap`, `press(forDuration:thenDragTo:)`, `swipeUp/Down`, `typeText`, `pressButton(.home)`) | same runner, same API | same |
| Tree | `snapshot()` → `XCUIElementSnapshot` (type, identifier, label, value, placeholder, frame, enabled, selected, focus) | same (served by the app process over the test daemon; `containerAccessible:false` is irrelevant) | same |
| Screenshot | `XCUIScreen.main.screenshot()` | same (replaces the 5.5 s Wi-Fi `devicectl` capture) | same |
| App state | `app.state`; SpringBoard alerts by bundle id | same | same |
| Egress | direct write to `CRAWL_OUT` (host filesystem; asserted at start, attachments as fallback) | `XCTAttachment` (`.keepAlways`) → `xcresulttool export attachments` after every round | attachments |
| Prerequisites | none | USB cable (never connected), Developer Mode, Settings › Developer › UI Automation, device registered to team B5B87F7AXF, phone unlocked with Auto-Lock Never, `DEVELOPER_DIR` = Xcode-beta 27 for iOS 27 | as competitor, plus an isolated install (decision 3) |

**Contingency per open unknown**

1. *USB + accessibility probe — labels or pixels?* Moot on the primary route: the tree comes from XCUITest, not from `pymobiledevice3`. That probe (`uvx pymobiledevice3 developer accessibility list-items` over USB) becomes relevant only if unknown 2 fails, as the last remaining read route (labels in VoiceOver order, no frames).
2. *Does XCUITest attach to third-party App Store apps on this iOS 27 phone?* `testAttachProbe` (activate → snapshot → node count → `probe.json`) costs one minute and runs before any competitor investment. Pass → full route with `CRAWL_PERMISSIONS=deny`, `CRAWL_DENY=full`, depth 4, no launch arguments. Fail → WebDriverAgent is the same initializer inside the same kind of bundle and would fail identically, so it is not a fallback; and the pixels-only Mirroring route is refuted above. What remains is a separate 30-minute experiment — `pymobiledevice3 developer core-device universal-hid-service tap` (virtual touchscreen, needs the USB tunnel and may hit its `dtuhidd` auth gate) plus `devicectl` screenshots and the focus-walk for labels — and Arya decides whether it is worth building a second driver for. Until then competitor mode is blocked, and the doc says so rather than pretending.
3. *Signing / keeping a runner installed.* Automatic signing with the paid team (365-day profiles) via `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`; `xcodebuild test-without-building` reinstalls the runner every round anyway, and only the runner is installed — nothing of ours goes on the phone in competitor mode.
4. *Annotation quality vs cost.* Text-first, vision only for `treeless` screens or a second pass when `confidence < 0.5`; the first 10 phase-1 screens are hand-labelled and every engine is graded on `state` agreement (≥ 0.8) and valid-JSON rate (≥ 0.95) before it becomes the default — with PR #119's `scripts/brain-eval/` when it lands, with a 20-line loop in `crawl-index.ts` until then.

## 7. Brain contract

**Who navigates:** nobody but the BFS. The model never picks the next action; it labels what happened, offline, over files, after the crawl. A run completes with no brain up at all.

**Brain selection** (`crawl-index.ts annotate`): probe `http://127.0.0.1:8080/v1/models` (Mference) then `:1234` (LM Studio, started only through `svc`); `GET /brain` on meshd when PR #119 lands. Vision probe: one `chat/completions` with a 16×16 PNG data URL; a 4xx or refusal sets `vision=false`. Images are never sent to a text-only engine.

**What the model sees per step** (`temperature 0`, `max_tokens 900`, `response_format json_schema`, two retries with local validation, then `annotation.error`):

| Piece | Form | Tokens |
|---|---|---|
| system | the rules below | ≈ 450 |
| header | app, version, target, screen id/kind, breadcrumbs (`Machines › Pair a machine`), depth, parent's one-line annotation | ≈ 150 |
| `tree.txt` | one line per node, `··`-indented: `Button "Pair machine" (12,88 351×44) [enabled]`; unlabeled Other/Group dropped, StaticText cut at 80 chars, runs of > 5 sibling StaticTexts collapsed to `StaticText ×N (first: …)`, ≤ 300 lines | ≤ 6,000 |
| actions | `A3 \| tap Button "Terminal" (tab bar) \| navigated_known → S2 "Terminal"` / `A7 \| Button "Unpair" \| SKIPPED denylist`, ≤ 40 rows | ≤ 1,000 |
| audit | `performAccessibilityAudit` issues, ≤ 10 lines | ≤ 200 |
| images (vision only) | `shot.png` + one representative `after/A<n>.png`, 512 px longest side, JPEG q70 | 1–2K each, max 2 |
| output | the schema below | ≤ 900 |
| **total** | text-only ≈ **8.7K**, vision ≈ **12K**, hard cap 16K by truncation | well under the 32K design target |

System prompt:

> You are auditing one screen of an iOS app for a QA report (mode `qa`) or describing it for a product study (mode `study`). You receive the accessibility tree (indented; type, label, identifier, frame in points), a table of every actionable element with what the crawler observed after tapping it, and sometimes screenshots. Judge only what is in front of you; never invent behaviour. (1) `works` = every exercised action produced a plausible result; `partial` = some were no-ops or errored; `broken` = a crash, an error alert, or a dead primary affordance; `unknown` = fewer than half the actions were exercised. (2) A `noop` on a Button is a defect unless the label implies a toggle or the screen shows a state change. (3) Name the screen the way a user would (the navigation title if present). (4) List visible affordances the crawler did NOT exercise so a human can cover them. (5) In `study` mode, `issues` are friction you can see, not defects. Reply with JSON matching the schema, nothing else.

Schema (`annotation.json`):

```json
{"type":"object","required":["screen_name","purpose","state","issues","actions","untested","confidence"],
 "properties":{
  "screen_name":{"type":"string","maxLength":60},
  "purpose":{"type":"string","maxLength":240},
  "state":{"enum":["works","partial","broken","unknown"]},
  "issues":{"type":"array","maxItems":8,"items":{"type":"object","required":["severity","what","evidence"],
    "properties":{"severity":{"enum":["blocker","major","minor"]},"what":{"type":"string","maxLength":200},"evidence":{"type":"string","maxLength":200}}}},
  "actions":{"type":"array","items":{"type":"object","required":["id","expected","observed_ok","note"],
    "properties":{"id":{"type":"string"},"expected":{"type":"string","maxLength":120},"observed_ok":{"type":"boolean"},"note":{"type":"string","maxLength":120}}}},
  "untested":{"type":"array","maxItems":12,"items":{"type":"string","maxLength":80}},
  "confidence":{"type":"number","minimum":0,"maximum":1}}}
```

**When vision is worth paying for:** `treeless: true` (the screenshot is the only evidence); a text-pass `confidence < 0.5`; or `--vision on` for a competitor study where visual design is part of what is being studied. Everywhere else the tree is cheaper and more precise.

**How a crawl becomes one index** — no model tokens: `crawl-index.ts index` renders `INDEX.md` from `index.json` + every `annotation.json` (≈ 120 tokens per screen; 100 screens ≈ 15K, which a cloud model reads in one sitting). Over 150 screens the screen map is split per tab and the executive part stays ≤ 3K. An optional `--summarize` sends `INDEX.md` (≤ 25K) to the brain once for a narrative paragraph. Every `brain call` is logged to `brain.jsonl` (endpoint, model, prompt/completion tokens, ms, valid) so budgets are measured, not assumed.

## 8. Artifact layout and the index

```
~/.mesh/crawls/                                   # outside git; ~/.mesh exists
├── _sandbox/                                     # sandbox daemon home, fakemux, fixture pane, meshd.log
└── <bundleId>/                                   # com.lecoder.meshwatch · ai.perplexity.app
    └── <version>+<build>/                        # 0.5.0+1 (MARKETING_VERSION+CURRENT_PROJECT_VERSION); competitors from devicectl's app list
        └── <target>/                             # sim | device
            ├── meta.json        git sha, xcode, device/runtime, start/end, rounds, budgets, seed used
            ├── state.json       frontier + screens + edges; rewritten after every action → resumable
            ├── index.json       final: screens[] (id, kind, name, title, tab, depth, status, treeless, firstPath, actions summary, audit count), edges[]
            ├── INDEX.md         the holistic index (format below)
            ├── DIFF.md          vs the previous version folder for the same bundle+target
            ├── brain.jsonl      one line per model call
            ├── rounds/          round-<n>.xcresult, deleted once index.json is written unless --keep-xcresult
            ├── probe.json       phase 3 only
            └── screens/<screen-id>/
                ├── shot.png             before any action
                ├── tree.json            raw snapshot walk        tree.txt   compacted, what the brain reads
                ├── meta.json            title, tab, overlay flags, scroll pages, contentHash, audit issues
                ├── actions.json         every enumerated action + outcome + skip reason + duration
                ├── after/A<n>.png       only when outcome ≠ noop (the before shot IS the noop case)
                └── annotation.json      brain output, or annotation.error
```

A 60-screen crawl at 25 actions/screen with after-shots as JPEG q80 is ≈ 100 MB; `state.json`/`index.json` stay under 2 MB.

`INDEX.md` format:

```
# com.lecoder.meshwatch 0.5.1+3 — sim — crawled 2026-09-10 (git ab12cd3)
Coverage: 58 screens (52 complete, 4 partial, 2 unreachable) · 913/1,040 actions exercised · 41 skipped (denylist) · 0 crashes · 6 audit issues
## Broken / partial, ranked
- [3f9a2c1b0d4e] Machine detail — broken — "Open VNC" → left_app never returns (after/A9.png) → screens/3f9a2c1b0d4e/
## Screen map
| id | name | reached by | depth | ok/total | state | audit |
## Flows
S1 Machines --"Pair a machine"--> S7 Pair a machine (overlay)
## Skipped as destructive — a human runs these
## Unreachable / not expanded (depth or budget)
## Diff vs 0.5.0+1   (DIFF.md, pasted)
```

## 9. Version diffing, the gate, the committed summary

`bun scripts/crawl-index.ts diff <base-folder> <head-folder>` needs no model. Screens pair by id, then by exact nav title. For each pair, actions pair by `(type | identifier | label)`. `DIFF.md` lists: screens **vanished** / **new**; per matched screen, actions vanished / new; **outcome changes** (`navigated_* → noop`, `* → crash`, `* → left_app`, `overlay → noop`); audit-issue deltas; coverage delta. Exit code 1 on any vanished screen, any crash in head, or any `navigated → noop` regression — the "an agent silently broke a screen" signals.

**Gate** — `scripts/check-screen-crawl.sh`, a new `check-*.sh`; nothing existing is edited:

- unset `MESH_CRAWL_GATE` → prints `SKIP: check-screen-crawl (set MESH_CRAWL_GATE=1 to validate, =run to crawl)` and exits 0. Mandatory: `check-all.sh` runs every `check-*.sh` and CI runs `check-all.sh` on the apps job, and no fresh clone or worktree has a crawl folder.
- `MESH_CRAWL_GATE=1` → requires `~/.mesh/crawls/com.lecoder.meshwatch/<MARKETING_VERSION>+*/sim/DIFF.md` and fails with the offending screen ids if the diff's exit code was 1.
- `MESH_CRAWL_GATE=run` → runs `scripts/crawl.sh` first (hours), then validates. This is what `release-workflow.md` gains as a pre-TestFlight step (decision 6).

**Committed per release**: `docs/crawls/<bundle>-<version>.md` = `INDEX.md` without image links, plus the `DIFF.md` section; one row appended to `docs/crawls/README.md` by `crawl.sh`. `docs/README.md` gets exactly one new row pointing at `crawls/README.md` (the index check scans `docs/*.md` only and resolves subfolder links). No artifact links into `~/.mesh` — a reviewer on another machine could not follow them.

## 10. Competitor mode

Same runner, same layout, same index, same diff: `scripts/crawl.sh --target device --bundle ai.perplexity.app`. Differences are all flags: `CRAWL_PERMISSIONS=deny`, `CRAWL_DENY=full`, every Switch observe-only, depth 4, no seed, no launch arguments, annotation `mode=study`. The version comes from `xcrun devicectl device info apps --device <id> --include-all-apps --json-output` (bundle version per the handoff's stable JSON), so `~/.mesh/crawls/ai.perplexity.app/2.31.1/device/` diffs against `2.30.0` with the same `DIFF.md` — "what did they ship between versions" for free. `probe.json` is written before any crawl. Never run on an account that matters (decision 4): a text denylist cannot see an icon-only destructive button or a non-English label.

## 11. Phased build plan

Phase 1 is the whole toolchain on the simulator, today, against an **erased, unpaired** app — no daemon at all, so nothing it taps can reach a machine. Both critiques called that an "empty shell"; it is: the point of phase 1 is proof-of-life of every primitive the later phases lean on, and the sandbox daemon in phase 2 is what fills the screens.

### Phase 1 — today, simulator, depth 2, ≤ 12 screens, no brain required (~25 minutes)

Repo edits: the `project.yml` block above, `Crawler/` (phase-1 slice ≈ 400 lines: config, tree walk + skeleton hash + dHash, enumerate, denylist, `Cancel/Done` overlay rung, nav-back + tab + relaunch-and-replay rungs, `CrawlStore`), nothing else.

```sh
cd /Users/aryateja/Projects/lecoder-watch
git log -1 --date=short --format='%h %cd %s'              # AGENTS.md rule 2: is this tree current?

# 0. project + app, built the way CI does (build/DerivedData from 27 Aug is six commits stale — never reuse it)
xcodegen generate
xcodebuild -project MeshWatch.xcodeproj -scheme "MeshWatch" \
  -destination "generic/platform=iOS Simulator" -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -2
APP=build/DerivedData/Build/Products/Debug-iphonesimulator/MeshWatch.app

# 1. the runner, once
xcodebuild build-for-testing -project MeshWatch.xcodeproj -scheme MeshWatchCrawler \
  -destination "generic/platform=iOS Simulator" -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -2
XCTESTRUN=$(ls build/DerivedData/Build/Products/MeshWatchCrawler*iphonesimulator*.xctestrun | head -1)
plutil -convert json -o - "$XCTESTRUN" | jq 'to_entries[] | select(.key|startswith("MeshWatchCrawler")) | .value | {TestHostBundleIdentifier, UITargetAppPath}'

# 2. a throwaway simulator — never LeSearch Preview (paired to the live fleet), never iOS265-repro (a repro)
UDID=$(xcrun simctl create MeshCrawl com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5)
xcrun simctl boot "$UDID" && xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant all com.lecoder.meshwatch
xcrun simctl spawn "$UDID" defaults write com.lecoder.meshwatch mesh.requireBiometrics.v1 -bool false   # belt and braces; the sim fails open anyway
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3

# 3. round 1
OUT=$HOME/.mesh/crawls/com.lecoder.meshwatch/0.5.0+1/sim; rm -rf "$OUT"; mkdir -p "$OUT"
TEST_RUNNER_CRAWL_BUNDLE_ID=com.lecoder.meshwatch TEST_RUNNER_CRAWL_OUT="$OUT" \
TEST_RUNNER_CRAWL_MAX_DEPTH=2 TEST_RUNNER_CRAWL_MAX_SCREENS=12 TEST_RUNNER_CRAWL_ROUND_SECONDS=600 \
TEST_RUNNER_CRAWL_DENY=app TEST_RUNNER_CRAWL_PERMISSIONS=allow \
xcodebuild test-without-building -xctestrun "$XCTESTRUN" \
  -destination "platform=iOS Simulator,id=$UDID" \
  -only-testing:MeshWatchCrawler/CrawlTests/testCrawl \
  -test-timeouts-enabled NO -parallel-testing-enabled NO \
  -resultBundlePath build/DerivedData/crawl-round-1.xcresult 2>&1 | tail -6

# 4. look at what came back
jq '{round, screens: (.screens|length), frontier: (.frontier|length)}' "$OUT/state.json"
FIRST=$(ls "$OUT/screens" | head -1)
jq -r '.. | objects | select(.type=="Button") | .label' "$OUT/screens/$FIRST/tree.json" | sort -u | head -20
jq -r '.actions[] | "\(.type) \"\(.label)\" -> \(.outcome)"' "$OUT"/screens/*/actions.json | sort | uniq -c | sort -rn | head -30
xcrun xcresulttool export attachments --path build/DerivedData/crawl-round-1.xcresult \
  --output-path build/DerivedData/crawl-round-1-att && ls build/DerivedData/crawl-round-1-att | head -5

# 5. round 2 = resume (same OUT, no rm)
TEST_RUNNER_CRAWL_BUNDLE_ID=com.lecoder.meshwatch TEST_RUNNER_CRAWL_OUT="$OUT" \
TEST_RUNNER_CRAWL_MAX_DEPTH=2 TEST_RUNNER_CRAWL_MAX_SCREENS=12 \
xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "platform=iOS Simulator,id=$UDID" \
  -only-testing:MeshWatchCrawler/CrawlTests/testCrawl -test-timeouts-enabled NO \
  -resultBundlePath build/DerivedData/crawl-round-2.xcresult 2>&1 | tail -3
jq '.round' "$OUT/state.json"

# 6. index (no brain) and, only if one answers, annotate
bun scripts/crawl-index.ts index "$OUT" && head -40 "$OUT/INDEX.md"
curl -sf http://127.0.0.1:8080/v1/models >/dev/null && bun scripts/crawl-index.ts annotate "$OUT"

# 7. tidy
xcrun simctl shutdown "$UDID"
```

**Proof of life** — each line is a file or an exit code, not a feeling:

1. `xcodegen generate` and `build-for-testing` exit 0 with a **host-less** `bundle.ui-testing` target; the `.xctestrun` shows no `UITargetAppPath`. This is the one structural unknown of the simulator route.
2. `state.json` has ≥ 5 screens; `tree.json` of the root has > 20 nodes; the five tabs (Machines, Terminal, Remote, Monitor, Settings) and `Pair a machine` appear as labelled `Button`/`Cell` nodes — or we learn today that SwiftUI hands us `Other` soup, before writing another line.
3. The runner attached through `XCUIApplication(bundleIdentifier:)`, i.e. the path competitor mode depends on, not the test-host shortcut.
4. `$OUT/screens/…` exists (direct host-filesystem write from the runner) **and** the attachment export contains the same PNGs — the device egress channel is already exercised.
5. Every screen has `firstPath`; every action has an `outcome`; the Pair sheet appears as `overlay:sheet`; a text field was typed into and the keyboard dismissed; a Settings link that leaves the app came back as `left_app` and the crawl continued; at least one `skipped:denylist`; a toggle was flipped and restored; no `unreachable` at depth 2.
6. Round 2 reports `round: 2` and no `(screen, action)` pair was exercised twice (action counts unchanged, frontier shorter or empty).
7. `INDEX.md` renders from `index.json` alone; if a brain answered, every `annotation.json` validates against the schema and `brain.jsonl` shows prompt tokens < 12K per screen.

### Phase 2 — the release gate: our app, populated, inert (2–3 days)

1. `MESHD_SANDBOX=1` guard in `server.ts` (decision 1) + `scripts/check-daemon-sandbox.sh`; fakemux + fixture pane + stub helper under `~/.mesh/crawls/_sandbox/`; the seed via `CRAWL_SEED_URL`; `POST /events` seeding one needs-approval card.
2. Full crawl, depth 4, `CRAWL_DENY=app`, `CRAWL_AUDIT=1`. **Zero-side-effect proof**: `ls /tmp/tmux-$(id -u)/` unchanged, `pbpaste` unchanged, `meshd.log` shows only `sandbox:true` answers to every non-GET, the Terminal tab's `Kill session`, the Power sheet's `Shut down`, and `Wake` all recorded as `in_place_change`/`overlay` with nothing happening on this Mac.
3. `scripts/crawl.sh` (build once, prepare, round loop with the wall-clock kill, export, index), `crawl-index.ts diff`, `check-screen-crawl.sh`, `docs/crawls/README.md`. **Diff proof**: crawl `0.5.0+1`, then a deliberately broken build (one tab renamed, one screen's push removed) → `DIFF.md` names the vanished screen and the `navigated → noop` action and exits 1; `sh scripts/check-all.sh` stays green with the gate unset.
4. Hand-label 10 screens; grade Mference text-only and LM Studio (via `svc`) with and without vision; pick the default.

### Phase 3 — competitor mode on the phone (½ day if the probe passes)

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer      # the phone is iOS 27
DEV=AA729359-402F-563A-918F-F3867D85D8F7
system_profiler SPUSBDataType | grep -c iPhone                            # the cable, plugged in for the first time
xcodebuild build-for-testing -project MeshWatch.xcodeproj -scheme MeshWatchCrawler \
  -destination "platform=iOS,id=$DEV" -derivedDataPath build/DerivedData \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration 2>&1 | tail -2
XCTESTRUN=$(ls build/DerivedData/Build/Products/MeshWatchCrawler*iphoneos*.xctestrun | head -1)
TEST_RUNNER_CRAWL_BUNDLE_ID=ai.perplexity.app xcodebuild test-without-building -xctestrun "$XCTESTRUN" \
  -destination "platform=iOS,id=$DEV" -only-testing:MeshWatchCrawler/CrawlTests/testAttachProbe \
  -resultBundlePath build/DerivedData/probe.xcresult 2>&1 | tail -3
xcrun xcresulttool export attachments --path build/DerivedData/probe.xcresult --output-path build/DerivedData/probe-att
cat build/DerivedData/probe-att/*probe*                                    # nodes > 3 → unknown 2 is answered
```

Then `scripts/crawl.sh --target device --bundle ai.perplexity.app --depth 3` with `CRAWL_PERMISSIONS=deny CRAWL_DENY=full`, rounds of 10 screens, `--hours 3`. Proof: a `device/` folder with `probe.json`, ≥ 20 screens, `INDEX.md` in `study` mode, and the phone's other apps untouched.

### Phase 4 — only if asked

Our app on the phone with an isolated install (decision 3); a dark-mode capture-only pass; VLM grounding for treeless screens; PR #119's `GET /brain` and `brain-eval`.

## 12. Decisions only Arya can make

1. **`MESHD_SANDBOX=1` in `server.ts`** (~6 lines, capability-reducing, env-gated, plus one new check). Without it the crawl of a paired app is limited to observe-only screens; the alternative is a ~30-line bun proxy in `scripts/` that forwards only `GET`, `/pair/claim`, `/events`, `/agents/*` — more code, no product change.
2. **Land the handoff doc on `main`** (cherry-pick `d65f5b1`) so this doc's link resolves, and add both rows to `docs/README.md` (this file; `crawls/README.md`).
3. **Our app on the physical iPhone**: not part of the gate. If wanted later, choose between a separate-bundle-id build (`project.yml` suffix, keeps the tester's install and Keychain untouched) and forgetting the fleet hosts by hand before each run — or skip it.
4. **Competitor mode prerequisites and risk**: plug the cable in, Developer Mode, UI Automation, Auto-Lock Never, phone parked and unlocked for hours; and which Apple ID / app accounts are signed in — the crawler presses real buttons in real apps, so a throwaway account or logged-out apps are strongly recommended.
5. **What may leave the Mac**: crawl folders can hold real Mac screen content (`/screen.jpg` under the sandbox) before a cloud model reads `INDEX.md`; say whether the Remote tab should get a fixture image (2 lines) or the folders stay local until reviewed.
6. **Gate policy**: the crawl stays opt-in (`MESH_CRAWL_GATE`); should a red `DIFF.md` block `release-testflight.sh` or only warn?
7. **Default brain**: Mference text-only vs LM Studio with a VLM (started through `svc`); and whether the 10-screen grading set is worth an hour of hand labels now.
8. **Budgets**: depth 4 / 200 screens / 40 actions per screen / 20 per round are guesses; change them once a real run reports its numbers.
9. **`accessibilityIdentifier`s on MeshWatch's tab bar and primary buttons** (product change, small): makes replay exact and screen ids immune to copy changes. Optional.
10. **Names**: `docs/screen-crawler.md`, top-level `Crawler/`, `~/.mesh/crawls/`.

## 13. Not built, on purpose

- fb-idb (dead on this companion), WebDriverAgent/Appium (same API as our runner), pymobiledevice3 HID (parked behind the probe), iPhone Mirroring driving (refuted).
- A driver interface, a TS state machine for rounds, twelve env knobs: one runner, one shell loop, eight knobs.
- Screen variants, Jaccard thresholds, RENAMED pairing, dHash for non-treeless screens: add when a real diff is noisy.
- LLM map-reduce for the index, `classify_action_risk` calls, a dark pass, a `-crawl` launch argument: the template render, the denylist, and `simctl spawn defaults write` cover them.
- Any change to an existing `scripts/check-*`, to `AGENTS.md`, or to the (absent) gates policy.

## Build plan

1. **Phase 1a — add the host-less MeshWatchCrawler target to project.yml and the Crawler/ phase-1 slice (CrawlTests.swift, Crawler.swift, Snapshot.swift ≈ 400 lines: config, snapshot walk + skeleton hash + dHash, enumerate, denylist, Cancel/Done overlay rung, nav-back/tab/relaunch-and-replay rungs, CrawlStore with direct write + XCTAttachment)** — proves: xcodegen accepts a bundle.ui-testing target with no host app and Xcode 26.6 builds it for the simulator — the only structural unknown of the simulator route

```sh
cd /Users/aryateja/Projects/lecoder-watch && git log -1 --date=short --format='%h %cd %s' && xcodegen generate && xcodebuild -project MeshWatch.xcodeproj -scheme "MeshWatch" -destination "generic/platform=iOS Simulator" -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -2 && xcodebuild build-for-testing -project MeshWatch.xcodeproj -scheme MeshWatchCrawler -destination "generic/platform=iOS Simulator" -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO 2>&1 | tail -2 && XCTESTRUN=$(ls build/DerivedData/Build/Products/MeshWatchCrawler*iphonesimulator*.xctestrun | head -1) && plutil -convert json -o - "$XCTESTRUN" | jq 'to_entries[] | select(.key|startswith("MeshWatchCrawler")) | .value | {TestHostBundleIdentifier, UITargetAppPath}'
```

2. **Phase 1b — create a throwaway MeshCrawl simulator (never LeSearch Preview: it is paired to the live fleet), install the fresh app, pre-grant privacy, turn AppLock off with zero product code, pin the status bar** — proves: the crawl target is unpaired and deterministic; no tap can reach a machine because no daemon exists

```sh
UDID=$(xcrun simctl create MeshCrawl com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-5) && xcrun simctl boot "$UDID" && xcrun simctl bootstatus "$UDID" -b && xcrun simctl install "$UDID" build/DerivedData/Build/Products/Debug-iphonesimulator/MeshWatch.app && xcrun simctl privacy "$UDID" grant all com.lecoder.meshwatch && xcrun simctl spawn "$UDID" defaults write com.lecoder.meshwatch mesh.requireBiometrics.v1 -bool false && xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3
```

3. **Phase 1c — round 1: depth 2, ≤ 12 screens, 10-minute cap, direct write to ~/.mesh/crawls** — proves: attach by bundle id; a usable snapshot() tree from a zero-identifier SwiftUI app (five tab buttons + 'Pair a machine' as labelled nodes); direct host-FS writes; BFS + return-to-origin; sheet/keyboard/left_app/denylist/toggle handling; state.json flushed per action

```sh
OUT=$HOME/.mesh/crawls/com.lecoder.meshwatch/0.5.0+1/sim; rm -rf "$OUT"; mkdir -p "$OUT" && TEST_RUNNER_CRAWL_BUNDLE_ID=com.lecoder.meshwatch TEST_RUNNER_CRAWL_OUT="$OUT" TEST_RUNNER_CRAWL_MAX_DEPTH=2 TEST_RUNNER_CRAWL_MAX_SCREENS=12 TEST_RUNNER_CRAWL_ROUND_SECONDS=600 TEST_RUNNER_CRAWL_DENY=app TEST_RUNNER_CRAWL_PERMISSIONS=allow xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "platform=iOS Simulator,id=$UDID" -only-testing:MeshWatchCrawler/CrawlTests/testCrawl -test-timeouts-enabled NO -parallel-testing-enabled NO -resultBundlePath build/DerivedData/crawl-round-1.xcresult 2>&1 | tail -6 && jq '{round, screens: (.screens|length), frontier: (.frontier|length)}' "$OUT/state.json" && FIRST=$(ls "$OUT/screens" | head -1) && jq -r '.. | objects | select(.type=="Button") | .label' "$OUT/screens/$FIRST/tree.json" | sort -u | head -20 && jq -r '.actions[] | "\(.type) \"\(.label)\" -> \(.outcome)"' "$OUT"/screens/*/actions.json | sort | uniq -c | sort -rn | head -30
```

4. **Phase 1d — attachment export, then round 2 as a resume on the same folder** — proves: the device egress channel (XCTAttachment → xcresulttool) delivers the same PNGs; the frontier persists and no (screen, action) pair is exercised twice

```sh
xcrun xcresulttool export attachments --path build/DerivedData/crawl-round-1.xcresult --output-path build/DerivedData/crawl-round-1-att && ls build/DerivedData/crawl-round-1-att | head -5 && TEST_RUNNER_CRAWL_BUNDLE_ID=com.lecoder.meshwatch TEST_RUNNER_CRAWL_OUT="$OUT" TEST_RUNNER_CRAWL_MAX_DEPTH=2 TEST_RUNNER_CRAWL_MAX_SCREENS=12 xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "platform=iOS Simulator,id=$UDID" -only-testing:MeshWatchCrawler/CrawlTests/testCrawl -test-timeouts-enabled NO -resultBundlePath build/DerivedData/crawl-round-2.xcresult 2>&1 | tail -3 && jq '.round' "$OUT/state.json"
```

5. **Phase 1e — scripts/crawl-index.ts with `index` (template render, no model) and `annotate` (probe :8080 then :1234, JSON-schema annotation, brain.jsonl token log); run index unconditionally, annotate only if a brain answers; shut the simulator down** — proves: INDEX.md renders from index.json alone; when a brain is up every annotation.json validates and prompt tokens stay < 12K per screen — the measured token budget

```sh
bun scripts/crawl-index.ts index "$OUT" && head -40 "$OUT/INDEX.md" && (curl -sf http://127.0.0.1:8080/v1/models >/dev/null && bun scripts/crawl-index.ts annotate "$OUT" && jq -s 'map(.prompt_tokens) | max' "$OUT/brain.jsonl" || echo 'no brain up; annotation deferred') && xcrun simctl shutdown "$UDID"
```

6. **Phase 2a — the sandbox daemon: MESHD_SANDBOX=1 guard in server.ts (decision 1) + scripts/check-daemon-sandbox.sh; fakemux, fixture pane and stub mesh-input under ~/.mesh/crawls/_sandbox; seed pairing through CRAWL_SEED_URL (XCUIDevice.shared.system.openURL of meshwatch://pair?h=&p=&c=) and one POST /events needs-approval card** — proves: a populated MeshWatch (sessions, approvals, remote, files, settings) can be crawled with zero side effects: every non-GET answered sandbox:true, tmux socket list unchanged, clipboard unchanged

```sh
SB=$HOME/.mesh/crawls/_sandbox; mkdir -p "$SB/home/.mesh/bin" && printf '#!/bin/sh\ncat >/dev/null\n' > "$SB/home/.mesh/bin/mesh-input" && chmod +x "$SB/home/.mesh/bin/mesh-input" && touch "$SB/home/.mesh/bin/mesh-input" && HOME="$SB/home" MESHD_SANDBOX=1 MESHD_PORT=8898 MESHD_HOST=127.0.0.1 MESHD_TOKEN=throwaway MESH_MUX="$SB/fakemux" CMUX_BIN=/usr/bin/false CMUX_SOCKET_HINT=/nonexistent bun run install/payload/meshd/server.ts > "$SB/meshd.log" 2>&1 & sleep 2 && curl -s http://127.0.0.1:8898/health | jq '{sandbox, capabilities}' && curl -s -X POST -H 'authorization: Bearer throwaway' -d '{"action":"shutdown"}' http://127.0.0.1:8898/system && ls /tmp/tmux-$(id -u)/ > /tmp/tmux-before.txt && pbpaste | md5 > /tmp/clip-before.txt && CODE=$(curl -s http://127.0.0.1:8898/pair/new | jq -r .code) && TEST_RUNNER_CRAWL_SEED_URL="meshwatch://pair?h=127.0.0.1&p=8898&c=$CODE" TEST_RUNNER_CRAWL_BUNDLE_ID=com.lecoder.meshwatch TEST_RUNNER_CRAWL_OUT="$OUT" TEST_RUNNER_CRAWL_MAX_DEPTH=4 TEST_RUNNER_CRAWL_DENY=app TEST_RUNNER_CRAWL_AUDIT=1 xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "platform=iOS Simulator,id=$UDID" -only-testing:MeshWatchCrawler/CrawlTests/testCrawl -test-timeouts-enabled NO -resultBundlePath build/DerivedData/crawl-full-1.xcresult 2>&1 | tail -3 && diff /tmp/tmux-before.txt <(ls /tmp/tmux-$(id -u)/) && diff /tmp/clip-before.txt <(pbpaste | md5) && grep -c 'sandbox' "$SB/meshd.log"
```

7. **Phase 2b — scripts/crawl.sh orchestrator (build once, prepare sim, round loop with a wall-clock kill at ROUND_SECONDS+300, export, index), crawl-index.ts `diff`, scripts/check-screen-crawl.sh (SKIP unless MESH_CRAWL_GATE), docs/crawls/README.md + one row in docs/README.md** — proves: DIFF.md names a screen that vanished and an action that went navigated→noop in a deliberately broken build and exits 1; check-all.sh stays green with the gate unset; the committed per-release summary lands in docs/crawls/

```sh
sh scripts/crawl.sh --target sim --bundle com.lecoder.meshwatch --depth 4 --hours 3 && BASE=$(ls -d ~/.mesh/crawls/com.lecoder.meshwatch/*/sim | sort -V | tail -2 | head -1) && HEAD=$(ls -d ~/.mesh/crawls/com.lecoder.meshwatch/*/sim | sort -V | tail -1) && bun scripts/crawl-index.ts diff "$BASE" "$HEAD"; echo "diff exit: $?" && head -30 "$HEAD/DIFF.md" && sh scripts/check-all.sh 2>&1 | tail -3 && MESH_CRAWL_GATE=1 sh scripts/check-screen-crawl.sh; echo "gate exit: $?" && sh scripts/check-docs-index.sh
```

8. **Phase 2c — grade the brains: hand-label 10 phase-1 screens, run annotate against Mference text-only and LM Studio (started via svc) with --vision off/auto, report state agreement and valid-JSON rate** — proves: unknown 4: which engine becomes the default and whether vision earns its tokens on treeless screens

```sh
bun scripts/crawl-index.ts annotate "$OUT" --brain http://127.0.0.1:8080 --vision off && cp -r "$OUT" "$OUT-mference" && bun scripts/crawl-index.ts annotate "$OUT" --brain http://127.0.0.1:1234 --vision auto && bun scripts/crawl-index.ts grade "$OUT-mference" "$OUT" --labels ~/.mesh/crawls/_labels/0.5.0.json
```

9. **Phase 3 — competitor mode on the phone: cable in, Xcode-beta 27, build the runner for the device with automatic signing, run testAttachProbe on ai.perplexity.app, then a deny-permissions crawl in 10-screen rounds** — proves: unknowns 2 and 3: XCUITest attaches to an App Store app on this iOS 27 device and the runner installs/signs with the paid team; a device/ folder with probe.json, ≥ 20 screens and a study-mode INDEX.md

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && DEV=AA729359-402F-563A-918F-F3867D85D8F7 && system_profiler SPUSBDataType | grep -c iPhone && xcodebuild build-for-testing -project MeshWatch.xcodeproj -scheme MeshWatchCrawler -destination "platform=iOS,id=$DEV" -derivedDataPath build/DerivedData -allowProvisioningUpdates -allowProvisioningDeviceRegistration 2>&1 | tail -2 && XCTESTRUN=$(ls build/DerivedData/Build/Products/MeshWatchCrawler*iphoneos*.xctestrun | head -1) && TEST_RUNNER_CRAWL_BUNDLE_ID=ai.perplexity.app xcodebuild test-without-building -xctestrun "$XCTESTRUN" -destination "platform=iOS,id=$DEV" -only-testing:MeshWatchCrawler/CrawlTests/testAttachProbe -resultBundlePath build/DerivedData/probe.xcresult 2>&1 | tail -3 && xcrun xcresulttool export attachments --path build/DerivedData/probe.xcresult --output-path build/DerivedData/probe-att && cat build/DerivedData/probe-att/*probe* && CRAWL_PERMISSIONS=deny CRAWL_DENY=full sh scripts/crawl.sh --target device --bundle ai.perplexity.app --depth 3 --round-screens 10 --hours 3
```

## Decided since the synthesis (2026-09-03)

- **Text-only.** Arya dropped the vision lane ("it will take too much memory"): no VLM in LM Studio, no model-written look at screenshots. Annotation works from the accessibility tree and the action ledger; screenshots are kept as evidence for humans and cloud models.
- **The device probe answered TEXT.** Over USB, `pymobiledevice3 developer accessibility list-items` returns captions + platform identifiers for any foreground app on this iOS 27 iPhone, with no sudo, tunneld or signing; `AccessibilityAudit` also exposes `move_focus`, `move_focus_next` and `perform_press`. That is a focus-walk-and-press route for competitor apps that needs no WDA — pending one proof that `perform_press` works on a process without `task_for_pid-allow` (the docstring warns it may not). `devicectl` screenshots take 1 s over USB. Screen recording is still absent over USB.

## Decisions only Arya can make

- Allow the ~6-line MESHD_SANDBOX=1 guard in install/payload/meshd/server.ts (capability-reducing, env-gated, plus a new scripts/check-daemon-sandbox.sh)? Without it, crawling a paired MeshWatch is limited to observe-only screens; the alternative is a ~30-line bun proxy in scripts/ that forwards only GET, /pair/claim, /events and /agents/* (more code, no product change).
- Cherry-pick d65f5b1 (docs/HANDOFF-2026-09-01-notifications-and-device-testing.md, currently only on fix/remote-trackpad-back-swipe) onto a main-bound branch so this doc's link resolves, and add the two rows to docs/README.md (screen-crawler.md and crawls/README.md).
- Our app on the physical iPhone is NOT part of the release gate (the simulator covers the same screens and code). If wanted later: a separate-bundle-id build via a project.yml suffix (keeps the tester's install and Keychain untouched) vs. forgetting the fleet hosts by hand before each run — or skip it entirely.
- Competitor mode on the phone: plug the USB cable in for the first time, enable Developer Mode and Settings > Developer > UI Automation, set Auto-Lock to Never, park the phone unlocked for hours, and decide which Apple ID / app accounts are signed in — the crawler presses real buttons in real apps, so a throwaway account or logged-out apps are strongly recommended.
- What may leave the Mac: under the sandbox, /screen.jpg may capture real Mac screen content into crawl folders before a cloud model reads INDEX.md. Add a 2-line fixture image for the Remote tab, or keep folders local until reviewed?
- Gate policy: the crawl stays opt-in via MESH_CRAWL_GATE (SKIP by default because check-all.sh and CI run every check-*.sh). Should a red DIFF.md block release-testflight.sh, or only warn?
- Default annotator: Mference text-only at :8080 vs LM Studio with a VLM (started only through svc); and whether an hour of hand-labelling 10 screens now is worth it to grade them.
- Budgets: depth 4 / 200 screens / 40 actions per screen / 20 screens per round / 1200 s per round are guesses to be corrected after the first real run.
- Optional product change: accessibilityIdentifiers on MeshWatch's tab bar and primary buttons (small) so replay is exact and screen ids survive copy edits.
- Names and locations: docs/screen-crawler.md, a top-level Crawler/ folder for the XCUITest bundle, artifacts under ~/.mesh/crawls/ (with ~/.mesh/crawls/_sandbox for the daemon home).
