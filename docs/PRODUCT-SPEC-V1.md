# PRODUCT SPEC V1 — take it to market in 7 days

Written 2026-08-28. One document, no companion reading required. Every claim cites a
file, a line, an issue, or a command output. Where a fact is unverified it says so.

Ground truth at time of writing: app `MARKETING_VERSION 0.5.1` (`project.yml:10`), daemon
`const VERSION = "0.5.3"` (`install/payload/meshd/server.ts:20`), latest published
installer `v0.5.2` (`gh release list -R LeSearch-AI/mesh-install`), `mesh.lesearch.ai`
**now resolves** and `/install.sh` 307-redirects to the GitHub release (verified by
`curl -sSI`) — the ROADMAP.md:30-34 DNS item is **done** and should be struck.

---

## 1. Identity — what this product is called, everywhere

### 1.1 Every user-facing name location, audited

| # | Where a human sees it | file:line | Current value | Proposed |
|---|---|---|---|---|
| 1 | iPhone Home Screen | `project.yml:64` → `Generated/iOS-Info.plist:12` | `LeSearch Mesh` | keep |
| 2 | Watch Home Screen / dock | `project.yml:169` → `Generated/Watch-Info.plist:8` | `LeSearch Mesh` | keep |
| 3 | Mac menu-bar app, name on disk | `project.yml:120`, `project.yml:128` → `Generated/Desktop-Info.plist:8` | `LeSearch Mesh` | keep |
| 4 | Live Activity / Dynamic Island extension | `project.yml:141` | `LeSearch Mesh Sessions` | keep |
| 5 | **Watch complication gallery** | `project.yml:199` | **`Agents waiting`** | **`LeSearch Mesh`** — the complication picker is a shopping list of app names; ours is the only entry that names a feature, so it is unfindable by product name |
| 6 | ASC app record / TestFlight app title | `docs/release-workflow.md:237`, app id `6803438426` (`scripts/release-testflight-asc.sh:48`) | `LeSearch Mesh` | keep |
| 7 | Website `<title>` | `web/index.html:6` | `LeSearch Mesh — answer your coding agents from your wrist` | keep |
| 8 | Website og:title | `web/index.html:10` | same | keep |
| 9 | Website nav brand | `web/index.html:259` | `LeSearch Mesh` | keep |
| 10 | Website hero body | `web/index.html:275` | `LeSearch Mesh puts every machine you own…` | keep |
| 11 | Website footer vendor | `web/index.html:602` | `LeSearch AI` | keep |
| 12 | Privacy page (5 places) | `web/privacy.html:6,77,89,98,194` | `LeSearch Mesh` / `LeSearch AI` | keep |
| 13 | README title | `README.md:1` | `# LeSearch Mesh` | keep |
| 14 | Menu-bar menu strings | `MeshDesktop/MeshDesktopApp.swift:28,71` | `LeSearch Mesh`, `Quit LeSearch Mesh` | keep |
| 15 | Pairing help text on the Mac | `MeshDesktop/PairView.swift:98` | `…open LeSearch Mesh → Machines…` | keep |
| 16 | Watch empty states | `Shared/WatchGlance.swift:98,116` | `Open LeSearch Mesh` | keep |
| 17 | iOS local-network prompt | `project.yml:78` | `LeSearch Mesh connects to your machines…` | keep |
| 18 | Watch local-network prompt | `project.yml:177` | same | keep |
| 19 | Face ID prompt | `project.yml:80` | `Unlock LeSearch Mesh…` | keep |
| 20 | Public repo the site links to | `web/index.html:264,282,568,604` | `LeSearch-AI/mesh` | keep |

### 1.2 Internal names — invisible to users, and pinned

| Where | file:line | Value | Verdict |
|---|---|---|---|
| Xcode project + target names | `project.yml:1,17,27,54,132,159` | `MeshWatch`, `MeshWatch Watch App`, `MeshWatchWidgets` | **keep.** Never appears in a UI. |
| Bundle ids | `project.yml` (`com.lecoder.meshwatch`, `.watchkitapp`, `.watchkitapp.glance`, `.widgets`, `com.lecoder.meshdesktop`) | `com.lecoder.*` | **keep forever.** `docs/app-store-submission.md:208-217` is explicit: changing these means a new App Store app, a new TestFlight link, every tester re-invited, every machine re-paired, and push broken until the APNs topic moves. |
| Pairing URL scheme | `project.yml:89` | `meshwatch` | keep — pinned by the same argument, and by the QR the daemon already emits (`MeshDesktop/LocalDaemon.swift:178-183`, `install/payload/meshd/qr.ts:592`) |
| App Group | `project.yml` / `docs/release-workflow.md:241` | `group.com.lecoder.meshwatch` | keep |
| CLI binary | `install/payload/bin/mesh` | `mesh` | keep |

### 1.3 Inconsistencies to fix (30 minutes total, zero risk)

1. `project.yml:199` — complication display name `Agents waiting` → `LeSearch Mesh`. **The only genuine user-facing naming defect in the repo.**
2. `CONTEXT.md:1` — `# CONTEXT — MeshWatch` → `LeSearch Mesh`. Dev-facing, but it is the first file every agent and contributor reads, and it teaches the wrong name.
3. `PROGRESS.md:1` — `# PROGRESS — clean watch app that controls the whole Mac`; no product name at all.
4. `.agents/design/*.html` — 7 mockups titled `MeshWatch — …`. Cosmetic; batch-fix or delete.
5. **Repo-name sprawl:** private `aryateja2106/lecoder-watch`, public `LeSearch-AI/mesh`, installer `LeSearch-AI/mesh-install`, plus `LeSearch-AI/meshwatch` from an earlier clean-slate push. Four names for one product. Nothing breaks, but a visitor cannot tell which is canonical.
6. **Version drift is unguarded.** App is 0.5.1, daemon is 0.5.3. `scripts/check-mesh-version.sh` only enforces CLI == daemon, not app == daemon; `docs/backlog.md:150` grades "Check one version across app, daemon, changelog and release" as `partial`.

### 1.4 Decision — OVERRIDDEN by the owner, 2026-08-28: the product is `MeshWatch`

This section originally recommended staying `LeSearch Mesh` (20/20 strings agreed, the
ASC record matched, a rename costs a review cycle). The owner heard that case in the
spec interview and decided the other way: **MeshWatch, published by LeSearch AI** —
the watch-first identity is the wedge nobody else owns, and the binary, bundle id and
URL scheme already said meshwatch. `CONTEXT.md`'s Names section is the canonical record.

The in-repo rename shipped the same night (`a0b8c5d`, 19 files, both builds green, zero
survivors). What the original recommendation predicted still holds and is now simply the
bill: the ASC record `6803438426` must be renamed to `MeshWatch` (metadata through
review — owner action), and the App Store subtitle should carry the phone half of the
story: `Your Mac, from your wrist`.

---

## 2. The product, in one sentence

**LeSearch Mesh puts every machine you own — and every coding agent running on it — on
your iPhone and Apple Watch, over your own network, with no account and no server of ours
in the path: one pasted command in, one command out.**

**Who it is for.** Solo builders and small teams who run coding agents (Claude Code,
Codex) on their own Macs and Linux boxes, and who step away from the desk — to the kitchen,
the gym, the school run — while the agent is still working. The agent blocks on a
permission question; today that is twenty dead minutes. This makes it one buzz and one tap.

**The wedge, stated so a competitor cannot copy it in a week** (`docs/competitive-position.md`):

- **No SSH, ever.** Moshi's own setup guide asks the user to install Tailscale, run
  `sudo tailscale up --ssh`, brew-install mosh and tmux, find the tailnet IP, and enable
  macOS Remote Login — then warns that skipping one breaks everything
  (`docs/competitive-position.md:75-79`). We ship our own daemon, mint our own token, and
  pairing hands back **every host that machine already knows**, so a four-machine fleet
  takes one 8-character code (`CONTEXT.md:113-117`).
- **Full Mac GUI control from phone *and* watch.** The agent-terminal camp (Moshi, Happy,
  Omnara, ShadowTerm) has no screen at all. The remote-desktop camp (Jump, Screens, VNC)
  has no agent concept. Nobody spans both (`docs/competitive-position.md:6-18,36-42`).
- **A real terminal on the wrist.** Moshi's own docs say its watch app cannot attach to a
  shell, cannot attach to tmux, cannot show scrollback, cannot dictate
  (`docs/competitive-position.md:22-27`). Ours does all four (commit `5ef5167`).
- **One-command uninstall, stated as a promise** (`README.md:74-86`). No competitor
  advertises one.

Honest counterweight: Moshi ships herdr/tmux/zellij pickers, watch approvals, Parakeet
on-device voice, an in-app diff viewer and a git-aware file browser, at **$7.99/mo**, with
4.7 stars across 482 ratings. **We do not race them on the phone terminal**
(`docs/competitive-position.md:87-90`). Omnara went cloud and archived
(`.agents/RELAUNCH.md:16-18`).

---

## 3. MVP-core inventory

### 3.1 SOLID — shipped, reachable from the UI, and guarded by a check

| Capability | Evidence | Guard |
|---|---|---|
| Pairing + whole-fleet adoption | `install/payload/meshd/pair.ts`; verified live: mint refused from tailnet (403), wrong code refused, replay refused, 5 wrong guesses burn the code, 3 hosts returned with 127.0.0.1 rewritten (`PROGRESS.md:135-143`) | `check-pairing.swift`, `check-mesh-pair.sh`, `check-pair-qr.sh` |
| Machine management (rename, remove, re-pair) | Fixed this week — `CHANGELOG.md` Unreleased; commits `569ab25`, `4219359` | `check-ios-smoke.sh` |
| Phone terminal | `iOS/TerminalView.swift`; scroll-back no longer yanked, smart-quoting off (0.5.0) | `check-watch-terminal-wiring.sh` (key contract) |
| Watch terminal (crown scroll, auto-follow, key bar, VoiceOver) | commit `5ef5167`; `openspec/specs/terminal-sessions/spec.md` | `check-watch-scrollback.swift`, `check-watch-terminal-wiring.sh` |
| Screen watch + control, phone and watch, incl. watch **Inspect** | `iOS/RemoteScreenView.swift` (1095 ln), `Watch/RemoteView.swift:534-620` (Inspect); pan buttons landed today, commit `041fe2a` | `check-screen-zoom.swift`, `check-inspect-crop.sh`, `check-remote-screen-gestures.sh`, `check-preview-mapping.swift` |
| Agent alerts → wrist → answer | Verified end to end on the live daemon: hook fired in a real rmux session → event → Reply and Continue both landed, `REPLY-FROM-WRIST-LANDED` echoed back (`PROGRESS.md:195-210`, `S21` at 211-225) | `check-mesh-hooks.sh`, `check-mesh-push.sh`, `check-alert-gating.swift`, `check-risk.swift` |
| Wake-on-LAN via a peer | `install/payload/meshd/wol.ts`; CHANGELOG 0.4.0 | `check-wol.sh` (fails on the macOS placeholder MAC specifically) |
| Live Activity + Dynamic Island | `MeshWatchWidgets/`; fleet count added 0.4.0 | `check-live-card.swift` (5 states, negative-tested twice) |
| APNs signed direct from meshd | `install/payload/meshd/push.ts`; prod/sandbox gateway retry (`PROGRESS.md:186-194`) | `check-apns-env.swift`, `check-mesh-push.sh` |

Two caveats that must not be dropped from launch copy:

- **APNs delivery to a cold TestFlight device is still unproven** (`ROADMAP.md:44-45`,
  `docs/launch-posts.md:88-90`). Say "free beta, tell me if your wrist buzzes".
- **Live Activity push-to-start does not exist** — the card only starts while the app is
  foregrounded (`ROADMAP.md:46-48`, `PROGRESS.md:268-271`).

### 3.2 BUILT-BUT-ROUGH

| Item | Issue | State | Launch week? | Why |
|---|---|---|---|---|
| herdr / TUI interaction in the phone terminal | **#108** (EPIC) | Owner could not view or interact with a herdr session; keys unreliable | **OUT** | It is an epic, and it is the one race `docs/competitive-position.md:87-90` says explicitly not to run. Ship the wrist and the screen; say the phone terminal is "good enough" and mean it. |
| Simultaneous modifier chords (⌘space, ⌘⇧2) | **#109** | Chords arrive as separate keypresses | **IN — half day** | This is the demo. "Remote control your Mac" that cannot open Spotlight fails the first thing anyone tries. Single fix in `input.ts` / `mesh-input.swift`. |
| Folder browser for working directory | **#106** | Drowns in dotfiles and `node_modules` | **OUT** | Every session start touches it, but a dotfile filter is cosmetic against a launch. Day-8 item. |
| Session-creation latency + progress UI | **#107** | Slow, zero feedback | **IN — measure only** | Instrument it, ship a spinner. Do not optimise; you cannot optimise what you have not measured, and a spinner removes the "is it broken?" read for free. |
| MeshDesktop menu-bar app | **#111** | Built and working, unsigned, never shipped (`docs/backlog.md:122`) | **OUT of the store, IN the README** | Signing + notarising is a multi-day Apple loop. Ship the source and `mesh desktop`. |
| In-app QR camera scan | **#105** | Deliberately absent | **OUT — and contested** | `MEMORY.md:49-55` records this as a *settled decision*: the human comparing the pre-filled code against the terminal IS the verification layer, and auto-claim deletes it. #105 asks to remove that layer. See §6. |

### 3.3 NOT BUILT

| Item | Issue | Launch week? | Why |
|---|---|---|---|
| Voice input into terminal / agent prompts | **#110** | **OUT** | System dictation already ships (0.4.0). Local ASR is a Mac-side lane (`docs/VOICE-INPUT-SPEC.md`) and watchOS has **no Speech.framework at all** (`MEMORY.md:29-37`). Moshi wins voice; do not contest it in week one. |
| Agentic shared memory across machines | **#112** | **OUT** | Weeks of design. Builds on kb.ts FTS5, which is real, but nothing about it makes a first user stay. |
| Container / macOS-sandbox isolation | **#113** | **OUT** | Linux `--user` per-agent meshd already ships and is proven; that is the story to tell. Containers are v2. |
| Local model + harness selection | **#114** (EPIC) | **OUT** | `openspec/changes/local-brain-and-harness/` concludes the daemon is already the converged design and the local model must be *staged*, not shipped as the brain — open models trail closed by ~4 months / 8 ECI points and the whole Terminal-Bench 2.1 top is closed. |
| **Off-network reachability (no VPN)** | *no issue filed* | **OUT of the build, IN the copy** | `openspec/changes/reach-my-mac-from-anywhere/` is the single most important open item and it is **not** in #105-114. Today the product works on your LAN or your own VPN, full stop (`README.md:145-151`). Launch honestly on that; do not promise "from anywhere". |

### 3.4 Open defects that gate launch week

- **#99 `blocker`** — the push gate silences every info-level event, and the setting that
  claims to restore them does not restore push. Fix before external TestFlight: it makes
  the flagship loop look dead.
- **#100** — pairing hands out every `hosts.json` token verbatim, **including pi's literal
  `testtoken`**. `openspec/changes/reach-my-mac-from-anywhere/proposal.md` flags the same
  thing. Rotate and fix before any stranger pairs.
- **#101** — delete-and-reinstall does not reset: the Keychain survives and stale machines
  resurrect. This is the first thing a confused new user tries.
- **#87, #88, #89** `high`, install path — `mesh doctor --fix` reads the flag from the
  wrong bag (already fixed in 0.5.1 per CHANGELOG, verify the issue is stale),
  `ensure_tmux` aborts the whole install when tmux is missing, `mesh uninstall --yes`
  leaves the bridge behind. All three are on the one-command promise.
- **#103** — the watch app is built in CI but never launched. `check-ios-smoke.sh` covers
  iOS only.

---

## 4. Isolating the screen/control module

The owner wants the option of extracting screen watch + control as a standalone
capability. It is closer to separable than anything else in the repo, because the daemon
already follows the "one module plus a two-line `server.ts` patch" rule (`CONTEXT.md:56-60`).

**Daemon side — the module (≈1,240 lines):**

| File | Lines | Owns |
|---|---:|---|
| `install/payload/meshd/input.ts` | 489 | `/input`, `/screen.jpg` (full frame **and** region since 0.5.0), `/displays`, `/clipboard`, `/volume`, `/apps`, `/system` |
| `install/payload/meshd/input-linux.ts` | 177 | xdotool path (X11; no Wayland, no capture) |
| `install/payload/bin/mesh-input.swift` | 421 | CGEvent + AXUIElement helper, NDJSON on stdin, long-lived child |
| `install/payload/meshd/wol.ts` | 152 | `/wake` — separate route, `server.ts:1040` |
| `install/payload/meshd/desktop.html` | — | the browser console served at `/desktop` |

**Coupling point 1 — already a single seam.** `server.ts:1031` is literally
`const remote = await handleInput(req, url); if (remote) return remote;` and it claims
`/screen.jpg` before any other route matches (`server.ts:672-674`). Extraction is a lift of
the five files plus that one line — the cheapest seam in the codebase.

**Coupling point 2 — auth does NOT come with it, and this is the trap.** `input.ts` is
safe only because `server.ts` runs, in order: the browser/DNS-rebinding gate (Origin,
`Sec-Fetch-Site`, `Host` validation), then the loopback exemption judged from
`server.requestIP`, then the constant-time bearer check in `auth.ts`
(`CONTEXT.md:96-100`, `MEMORY.md` auth block). A standalone screen server that ships
without all three is an unauthenticated remote-input surface. **Port `auth.ts` and the
Host/Origin gate with the module or do not extract it.**

**Client side:**

| File | Lines | Coupling |
|---|---:|---|
| `Shared/ScreenZoom.swift` | 153 | **None.** Pure geometry, mutation-tested four ways. Lifts clean. |
| `Shared/MeshClient.swift` | 503 | Screen/control methods at `:148 screenImage`, `:174 screenImageQuery`, `:199 screenFrame`, `:206 displays`, `:334 inputStatus`, `:340 input`, `:346 clipboard`, `:358 volume`, `:369 apps`, `:397 wake`, `:405 system`, `:419 systemAction`. **These are ~40% of one class that also carries agents, events, stats and KB** — the split is a real refactor, not a file move. |
| `iOS/RemoteScreenView.swift` | 1095 | Depends on `MeshClient`, `Machine` (`Shared/Models.swift`), `ScreenZoom` |
| `Watch/RemoteView.swift` | 1611 | Same, plus the relay: `Watch/WatchLink.swift` → `iOS/PhoneConnectivity.swift` when off-tailnet |
| `Shared/DaemonCapabilities.swift` | — | Gates on `screenRegion`, `power`, `paste`; `check-daemon-gaps.sh` holds both ends |

**Coupling point 3 — the watch relay is general-purpose, not screen-specific.**
`WatchLink.request` and the phone's handler carry every read, so a standalone watch client
inherits the whole relay or loses the off-tailnet path entirely.

**Verdict.** Daemon side: extractable in a day, *if* auth goes with it. Client side: the
`MeshClient` split is the real cost. Do not do this during launch week — it buys nothing a
user can see and it puts a hand inside the one subsystem that is currently green.

---

## 5. Seven days to market

Launch **is** TestFlight-public + landing page. App Store *follows* — Apple averages
"90% of submissions reviewed in less than 24 hours" but Beta App Review for the first
external build is its own ~24h gate and full App Review is a separate one
(`docs/app-store-submission.md:236-246`). Do not put an App Store date in a launch post.

### Day 1 (Fri 28 Aug) — ship what is already finished

- `sh scripts/release-mesh-install.sh --publish` → **mesh-install v0.5.3**. The daemon here
  is 0.5.3 (`server.ts:20`); the published tarball is 0.5.2 and predates the 14.5s→0.12s
  shell fix (`CHANGELOG.md` 0.5.3 block, commit `1d3bff1`). Every new user currently
  installs the slow-shell bug. The script gates on `check-all.sh`, proves the tarball
  version, and refuses NUL bytes.
- Fix **#100** (pairing hands out `testtoken`) and rotate every token in the fleet. This is
  the one item that must not reach a stranger.
- Fix **#99** (push gate silences info events). Blocker severity; it makes the flagship
  loop read as broken.
- Strike the DNS item from `ROADMAP.md:30-34` — it is done.

### Day 2 (Sat 29 Aug) — make the first-run path unbreakable

- **#101** delete-and-reinstall must actually reset (Keychain + machine list).
- **#88** `ensure_tmux` must not abort the install; **#89** `mesh uninstall --yes` must take
  the bridge with it. Both are load-bearing on "one command in, one command out", which is
  the headline claim.
- Verify **#87** is genuinely fixed by 0.5.1 and close it.
- Run the whole first-run on a clean machine, timed. If it is not under three minutes,
  that is the bug.

### Day 3 (Sun 30 Aug) — branding + the one visible naming fix

- `project.yml:199` complication name → `LeSearch Mesh`.
- `CONTEXT.md:1`, `PROGRESS.md:1`, `.agents/design/*.html` headers.
- Bump `project.yml:10` `MARKETING_VERSION` to **0.5.3** so app and daemon agree, and add
  the app-vs-daemon assertion to `scripts/check-mesh-version.sh` (`docs/backlog.md:150`).
- Fold the `## [Unreleased]` CHANGELOG block into `## [0.5.3]` — it is the source of the
  TestFlight "What to Test" notes.

### Day 4 (Mon 31 Aug) — TestFlight external, and the demo it needs

- `sh scripts/release-testflight-asc.sh --external`. **One command**, four gates
  (dirty tree, version downgrade, ASC silence, and the smoke test which has no escape
  hatch). It adds the build to the internal group *and* submits for Beta App Review — the
  step whose absence left the public link serving the 20 Aug build
  (`docs/updating.md:85-108`, `ROADMAP.md:35-41`).
- Start the Beta App Review clock **today**; everything else this week can run in parallel
  while Apple looks at it.
- Fix **#109** modifier chords while waiting — half a day, and it is what every demo tries
  first.

### Day 5 (Tue 1 Sep) — landing page + assets

- `web/index.html` refresh against `docs/competitive-position.md:113-121`: lead with the
  **watch terminal** (nobody else has one) and the **agent-blocked → screen-control**
  end-to-end story; state the one-command uninstall as a promise, not a footnote.
- Correct the reachability copy so it matches `README.md:145-151` — "your home network or
  any VPN you already run", never "from anywhere".
- **Screenshots are not App Store ready.** The five in `docs/screenshots/` are 331×720
  (README thumbnails) and 422×514 (Ultra 3). App Store requires a 6.9″ iPhone set at
  1260×2736 / 1290×2796 / 1320×2868 and one consistent watch size — 416×496 is the
  sensible default (`docs/app-store-submission.md:146-154`). Regenerate with the
  `simctl` recipe at `docs/app-store-submission.md:167-190`; strip alpha, upload serially.
- Add the in-app **Privacy Policy** row. `grep -rn privacy --include=*.swift` returns
  **nothing** — 5.1.1(i) requires the policy inside the app as well as in ASC metadata, and
  this is a documented common rejection (`docs/app-store-submission.md:122-124`).
  `web/privacy.html` already exists; this is a link.

### Day 6 (Wed 2 Sep) — App Store submission package

Work `docs/app-store-submission.md` top to bottom. Nine unchecked boxes remain; three are
already satisfied and just need ticking (`PrivacyInfo.xcprivacy` exists on **both** targets;
`ITSAppUsesNonExemptEncryption: false` is set at `project.yml:67` and `:172`; there are no
accounts). Six are real work:

1. **Demo Host** in the machine list, no pairing, exercising every feature — the reviewer
   cannot install our daemon (2.1(a)).
2. **A live throwaway host** kept up through the review window, its pairing code in the
   notes.
3. **An unlisted 2–3 minute demo video** — curl install through to answering on the wrist.
4. **In-app privacy link** (Day 5).
5. **Local network permission pre-prompt + recovery deep link.** Deny it once and discovery
   silently returns nothing forever.
6. **Sign and notarize `meshd`** — Developer ID. Load-bearing for the per-binary
   Accessibility and Screen Recording grants.

Write the review notes from the template at `docs/app-store-submission.md:80-98`. The rule
that can kill this app is **4.2.7**, not 2.5.2: lead with *"a generic mirror of your own
Mac"* in those words, and request prior approval for demo mode on the **first** submission.

### Day 7 (Thu 3 Sep) — launch

- `docs/launch-posts.md` already holds LinkedIn long, LinkedIn short, and X drafts, plus a
  "what NOT to claim" list (`:87-101`). Update them for 0.5.3 and swap in the real
  TestFlight link `https://testflight.apple.com/join/pVYPTxc7`.
- **Sequence:** X thread in the morning (hero: the watch terminal, 12s screen recording),
  LinkedIn long-form the same day, Hacker News *Show HN* only if the first two draw real
  replies — the repo is MIT and public, which is the HN-shaped part.
- **Product Hunt: not this week.** PH rewards a polished store listing and a launch-day
  team; you will have a TestFlight link and one person. Hold it for the App Store approval
  and use PH as the *second* wave — a launch has two shots and spending one on a beta link
  wastes it.
- Ask for exactly one thing in every post: *install it and tell me if your wrist buzzes.*
  APNs-to-cold-device is the unproven leg (§3.1) and 15 installs answer it in a day.

---

## 6. Open decisions — sharp questions, with recommended answers

1. **Pricing at launch: free beta, or price it now?**
   → **Free while in TestFlight, and say "free during beta" — not "free".** The observed
   category is freemium + annual + lifetime (`docs/competitive-position.md:98-111`). With
   10–15 people waiting, mirror Moshi's Founder tier: a permanently discounted
   early-supporter SKU (**$3/mo or $29/yr, locked for life**) announced *at* launch and
   redeemable when the App Store build lands. That converts the beta list and seeds the
   first reviews. Charging nothing forever trains the list that this is a hobby.

2. **App Store name: `LeSearch Mesh` or `MeshWatch by LeSearch AI`?**
   → **DECIDED by the owner 2026-08-28: `MeshWatch`** (see §1.4 — the recommendation
   here argued the other way and was overridden). Repo rename shipped in `a0b8c5d`;
   the ASC rename is an owner action. Subtitle: `Your Mac, from your wrist`.

3. **Do the bundle ids stay `com.lecoder.*`?**
   → **Yes, forever, and out of scope for any branding pass.** Already decided at
   `docs/app-store-submission.md:208-217`. Re-opening it costs a new App Store app, a new
   TestFlight link, every tester re-invited, every machine re-paired, and dead push.

4. **Which of #105-114 make launch week?**
   → **DECIDED by the owner 2026-08-28: "most of the above", built overnight.** Shipped
   the same night on this branch, each behind its own green gate: #105 (in-app QR),
   #106 (folder search, PR #115), #107 (latency measured — the 989ms is a hardcoded
   900ms daemon sleep, filed as #117 — plus the progress UI), #109 (modifier chords),
   and the herdr-visibility subset of #108 (PR #116). Still out: full #108 epic, #110,
   #111, #112, #113, #114.

5. **#105 asks for an in-app QR scanner. `MEMORY.md:49-55` says that was deliberately
   rejected. Which one is the current decision?**
   → **RESOLVED 2026-08-28: both, because the memory's real objection was auto-claim,
   not the camera.** The shipped scanner (`b5a2f38`) pre-fills the fields and stops;
   the human still compares the code against the terminal and taps Pair — the
   verification layer survives intact. Camera permission is asked only when the user
   taps Scan, never on the first-run path. The paragraph below records the original
   reasoning; if conversion data ever argues for auto-claim, the fix is
   better copy on the pair sheet, not a scanner. **This is the one place where a filed
   issue contradicts a recorded decision — resolve it in writing today.**

6. **Do we ship the off-network relay, or say plainly that we do not have one?**
   → **Say it plainly this week; decide the relay after the first cohort.**
   `openspec/changes/reach-my-mac-from-anywhere/` proves "no servers of ours" and "works
   from anywhere with zero setup" are mutually exclusive, and that the blocking
   prerequisite is **pinned self-signed TLS**, not the relay. Today `meshd` is a bearer
   token over plain HTTP on `0.0.0.0:8899` — defensible on a home LAN, indefensible the
   moment it is internet-reachable. **Do not expose anything off-LAN before TLS lands.**

7. **Does the App Store submission gate the launch?**
   → **No.** Launch on the public TestFlight link plus the landing page. Submit to the App
   Store in parallel and treat approval as the second launch wave (Day 7, Product Hunt).

8. **What is the one number that says this worked?**
   → **Installs that produce a wrist buzz.** Not downloads, not stars. The daemon's daily
   heartbeat already reports coarse hook-event counters by level
   (`install/payload/meshd/telemetry.ts`, `README.md:169-183`), so this is measurable
   today without adding anything to the apps — and the apps stay "Data Not Collected".
