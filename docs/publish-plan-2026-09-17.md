# Publish plan — everything between this tree and invited users

*2026-09-17. Built from the release-readiness review, the planning review and the security
review in [review-2026-09-17.md](review-2026-09-17.md), each finding confirmed by a
separate skeptic agent against this tree. Ordered by dependency. `blocking` means users
cannot be invited without it. Owner `human` means it needs Arya's hands, password, or
Apple account; `agent` means any harness can do it behind the gate; `either` is either.
Every task names the proof that closes it, because three features here shipped compiling
green and dead.*

Measured starting point:

| Surface | State on 2026-09-17 |
|---|---|
| Repo | apps `MARKETING_VERSION` 0.5.1, daemon `VERSION` 0.6.0, CHANGELOG top `[Unreleased]`, `gates.sh full` GREEN |
| TestFlight (public link pVYPTxc7) | Newest build 202608270920, uploaded 2026-08-27, externally IN_BETA_TESTING. The text-box crash fix landed at 21:47 that night, after the upload. **Invitees today get the crasher** |
| Installer (LeSearch-AI/mesh-install) | v0.5.2, 2026-08-27 |
| Fleet | An unpublished 0.5.4 on this Mac; dataflow and pi on 0.5.x |
| Public repo and landing page | Served from `main`, which is 112 commits behind the release branch; public CHANGELOG top is 0.4.0 |
| Physical device proof | 0.6 Debug builds ran on the iPhone via cable on 2026-09-04/05. No TestFlight-signed build, no production-APNs round trip, no 0.6 run on the watch is on record |
| Release gate on this Mac | `xcrun simctl` hangs (CoreSimulator 1166 vs the shim's 1051.55); eight iPhone 17 Pro simulators exist. The hang guard exists only on this branch, not on `release/lesearch-mesh-0.6` |

## Phase 0 — unblock (this week, mostly human)

| ID | Task | Owner | Effort | Blocking | Depends | Proof | Issue |
|---|---|---|---|---|---|---|---|
| T00 | **Decide the ship branch and land it.** PR #124 (`release/lesearch-mesh-0.6` into `main`, 378 files, MERGEABLE, CI green) is the unlisted step that publishes 0.6 on the web; this branch's three commits (the gate, the hang guard, the map) must ride on whatever ships, or both release scripts hang on this Mac. Then re-target #126, #128, #131 at `main` | human | S | yes | | `git merge-base --is-ancestor adbdf48 origin/main`; `gh pr list` shows no PR based on the release branch | #124 |
| T01 | **Fix the simctl hang once**, as admin: `sudo xcodebuild -runFirstLaunch`. Eight iPhone simulators already exist, so nothing else is needed | human | S | yes | | `MESH_SMOKE_REQUIRED=1 sh scripts/check-ios-smoke.sh` prints `check-ios-smoke: OK … ran on: iPhone 17 Pro · iOS 26.x` on this Mac | |
| T02 | Align the three version numbers on 0.6.0 and make `check-mesh-version.sh` assert app == daemon. Do not fold the changelog yet; both release scripts read `[Unreleased]` | agent | S | yes | T00 | `grep MARKETING_VERSION project.yml` → 0.6.0; the check goes red when the two differ and green when aligned; `gates.sh fast` GREEN | #67 |
| T03 | **Rotate the demo fleet's tokens.** pi's `hosts.json` entry is the literal nine-character default and tokens were once printed into a transcript. Every phone paired to this Mac inherits them | human | S | yes | | `mesh token rotate --yes` on macbook, dataflow and pi; `mesh doctor` shows no weak-token row; `mesh hosts` all 200 | #100 |
| T04 | Fill `docs/factory/CHARTER.md` (twenty minutes: `TIER: greenfield`, load-bearing globs = `Shared/**`, `install/payload/meshd/{server,auth,pair}.ts`, `project.yml`, `.github/workflows/**`; `CHARTER_STATUS: ready`) and apply the `factory:*` labels with `.factory/scripts/bootstrap-github.sh --apply`, or delete `docs/factory/`. Pick one review-queue number | human | S | no | | `gh label list` shows `factory:*`; `CHARTER_STATUS: ready`; one STOP_IF number, CLAUDE.md says "see charter" | |
| T05 | Prune the sprawl: `git remote set-head origin -a` in every clone (the local `origin/HEAD` still points at `backup/2026-07-02`); close #4, #118 (contained in HEAD), #127 (fold into #124/#128); `git worktree prune`; delete the 7 remote branches that are ancestors of HEAD | either | M | no | T00 | `git worktree list` shows only live trees; `gh pr list` ≤ the charter's limit | |

## Phase 1 — fix what the reviews found before anyone else installs

| ID | Task | Owner | Effort | Blocking | Depends | Proof | Issue |
|---|---|---|---|---|---|---|---|
| T06 | **Relay receiver:** implement `session(_:didReceiveMessage:)` on the phone so reply-less watch commands (screen peek, new session, kill, split, RemoteView keys, volume, watched output) stop being dropped over the relay | agent | S | yes | | Physical pair: phone reachable, watch opens screen peek and a new session; recorded under `docs/factory/runs/`. No grep counts | ARCH-01 |
| T07 | **Honest relay acks:** return `RelayReply.failure` from every `try?` catch and every `guard … return nil` in `MeshStore.handle`; decode it in `WatchLink.acknowledge` | agent | S | yes | | A reply to a dead session shows a failure line on the watch, not a tick; a `check-*.swift` drives the pure routing function both ways | ARCH-02 |
| T08 | **Bearer on `/pair/new`** plus teach `MeshDesktop/LocalDaemon.swift` to read `~/.mesh/token`; cherry-pick PR #129's `loopback-trust.ts`, `authed()` change and `MESHD_TRUST_LOOPBACK=0` kill switch onto the ship branch (not the whole PR: its `capabilities.ts` drops five 0.6 capabilities); move `handlePair` below the cross-site check; one `isLoopback` | agent | S | yes | T00 | A tokenless `GET /pair/new` over loopback answers 401; `mesh pair` and MeshDesktop pairing still work; `check-mesh-pair.sh`, `check-token-rotate.sh`, new `check-mesh-loopback-trust.sh` green | SEC-03, SEC-04, SEC-07, #129 |
| T09 | Rebase PR #130 onto the ship branch and merge (fs read bounds, push token perms, WoL broadcast validation) | human | S | no | T00 | `check-wol.sh` and the files check green on the merged tree | SEC-08, #130 |
| T10 | Fix the two notification blockers: #99 (push gate silences every info-level event; Codex producers never push) and #80 (attention banner raised then deleted). Blocking for any cohort that includes Codex users; non-blocking only if the first cohort is explicitly Claude-Code-only | agent | M | yes* | | Each issue's done-when reproduces green and a `check-*` goes red on revert (`check-mesh-push.sh`, `check-live-card.swift`) | #99, #80 |
| T11 | Decide whether draft PRs #120 (one Live Activity card per wait) and #126 (voice session deaths) ride 0.6.0 or 0.6.1; neither head is on the release branch | human | M | no | T00 | Both heads are ancestors of the ship branch with CI green, or the changelog says they are not in this build | #120, #126 |
| T12 | Serve `/a/` hosted apps from a separate origin (or add a CSP sandbox and drop the loopback exemption for `/fs` and `/screen.jpg`), and mint 128-bit `/a/` keys. Agent-built apps run untrusted code same-origin with the token today | agent | S | no | | A hosted page's `fetch("/fs/read?path=…/.mesh/token")` is refused; existing 8-hex apps still open | skeptic, SEC-06 |
| T13 | Add chat, redact, apps and handoff to `DaemonCapabilities.expected` so an old daemon says "update available" instead of hiding Chat | agent | S | no | | `check-daemon-gaps.sh` green with the four rows; a fixture `/health` lacking `chat` yields one gap | |
| T14 | Add the reinstall sentinel so delete-and-reinstall does not resurrect stale Keychain machines (this manufactured the 2026-08-28 outage report) | agent | S | no | | A `check-*.swift` drives keep and start-clean; smoke green | #101 |
| T15 | Finish the rename in user-visible strings (permission prompts still say "MeshWatch connects…", "Unlock MeshWatch"; eight Swift strings; "terminal/VNC" on the watch) and add a naming grep to `check-all.sh` | agent | S | no | | The grep returns nothing user-facing; `gates.sh fast` GREEN | #51 |
| T16 | In-app Privacy Policy row and a Report-a-problem path in Settings; an issues link on the landing page | agent | S | no | | Smoke test finds both rows; `check-links.sh` green | |
| T17 | Remove the stock-Mac first-run cliffs: `ensure_tmux` aborts with `brew install tmux` on a Mac that has no Homebrew, and nothing mentions the Command Line Tools that `mesh-input` needs | agent | M | no | | A new `check-*` runs `install.sh` with rmux and no tmux and asserts it installs; `mesh doctor` names `xcode-select --install`; README Requirements lists CLT | #88 |
| T18 | Install the Codex hook instead of printing instructions | agent | S | no | | `mesh hooks install` writes the Codex `notify` entry; a `check-*` asserts it | #20 |
| T19 | Register `PermissionRequest` in `HOOK_EVENTS`, populate `Agent.sessionId` on `/agents` rows, so a notification can carry Allow/Deny buttons. 0 of 312 recorded events were replyable | agent | M | no | | Physical watch: a real permission prompt arrives with buttons and Allow is obeyed; recorded run | #23 |

*T10 is blocking if Codex users are in the first cohort.

## Phase 2 — ship 0.6.0 to all three surfaces, in this order

| ID | Task | Owner | Effort | Blocking | Depends | Proof | Issue |
|---|---|---|---|---|---|---|---|
| T20 | **Cut the 0.6.0 TestFlight build and submit for Beta App Review (external).** ASC still holds a stray 1.0 pre-release, so the downgrade hatch is required | human | M | yes | T01, T02, T06-T08 | `asc auth status`; `MESH_ALLOW_VERSION_DOWNGRADE=1 sh scripts/release-testflight-asc.sh --external`; `asc testflight distribution view --build-id <id>` → IN_BETA_TESTING; the Beta group lists it | #74 |
| T21 | **Prove the TestFlight-signed build on the real iPhone and Apple Watch:** install from the TestFlight app (not devicectl), pair, hook, make Claude Code stop on a prompt, the watch buzzes, Continue sends Enter; `curl /push` shows a production device and an LA update token; the watch app opens its machine list | human | M | yes | T20 | Recorded as a run file under `docs/factory/runs/` with the device and build number | #103 |
| T22 | **Publish meshd 0.6.0 to mesh-install and upgrade the fleet, only after T20 is IN_BETA_TESTING** (the 0.6 bridge requires a token; a phone app older than 0.6 loses Terminal mode against it) | human | S | yes | T20 | `sh scripts/release-mesh-install.sh --publish`; `gh release view --repo LeSearch-AI/mesh-install` → v0.6.0; a fresh machine's `/health` reports 0.6.0 with redact/chat/apps; `mesh upgrade` on dataflow and pi | #74 |
| T23 | Fold CHANGELOG `[Unreleased]` into `[0.6.0] — <date>`, add a one-line 0.5.4 entry, fix the ROADMAP lines that still claim the Aug 21/24 builds are the newest and PRODUCT-SPEC's "daemon is 0.5.3" | agent | S | no | T20, T22 | `grep -n '^## \[' CHANGELOG.md \| head -2`; `gates.sh fast` GREEN | #72 |
| T24 | Write "## Published means" in `release-workflow.md`: build IN_BETA_TESTING at this version, installer tag == daemon `VERSION`, dated changelog, one fleet `/health` at that version, one non-owner install produced a push. Close #74 against it | agent | S | no | T23 | The five lines exist; #74 closed with the link | #74 |
| T25 | Push the curated 0.6 snapshot to the public LeSearch-AI/mesh repo (the landing page routes /changelog and /roadmap there; its top is 0.4.0) | human | S | no | T00, T23 | Public CHANGELOG has `[0.6.0]`; `check-links.sh` green | |
| T26 | Automate a watchOS smoke test beside the iOS one; CI builds the watch app and never launches it | agent | M | no | | New `scripts/check-watch-smoke.sh` launches the watch app on a watch simulator, honours `MESH_SMOKE_REQUIRED=1`, prints `ran on:` in CI | #103 |

## Phase 3 — invite the first cohort

| ID | Task | Owner | Effort | Blocking | Depends | Proof | Issue |
|---|---|---|---|---|---|---|---|
| T27 | Consolidate the plan of record: merge PR #128 (`PRODUCT.md` + drift check); delete `PLAN-0.6.md` and `TASKS-2026-09-04.md` once their open rows are issues; one "## Now" in ROADMAP; move `CLI-FIRST-ROADMAP.md` to the dated table; fix the MEMORY.md scanner paragraph, the openspec telemetry principle and the naming record in CONTEXT.md | agent | S | no | T00 | `check-docs-index.sh` and `check-product-spec.sh` green; `grep -c '## Now' ROADMAP.md` → 1 | P1, P8, P9, P11 |
| T28 | Triage the queue in one sitting: close #105, #106, #107, #109, #117, #87, #78, #79 with the commit; label #100-#117; regenerate `backlog.md`; add an issue template; record the four owner decisions (relay = A, TLS before off-LAN; harness spike deferred; Screen peek; next version) in `DECISIONS.md` and close #7, #68 | either | M | no | | `gh issue list --json labels` shows no unlabeled open issue; `backlog.md` "done" > 0 | P4, P12 |
| T29 | Rewrite landing and store copy to the proven record: lead with the watch terminal and Mac control; drop the FAQ "Yes" to away-from-home and "your wrist buzzes" until T19 and T21 are on record; unify Allow / Deny / Reply / Stop | agent | S | no | T21 | `web/index.html` has no unproven claim from `docs/launch-0.6.md`'s "Do not say" list; six-label audit passes | |
| T30 | Invitee guide and invite message: iOS 26+, tmux/Homebrew or rmux, Command Line Tools, same LAN or Tailscale, the Local Network prompt, the four commands, where to report | agent | S | no | T17 | A page reachable from the landing page that a fresh reader follows to a paired watch in under three minutes; `check-links.sh` covers its URLs | #42 |
| T31 | **Invite the cohort.** Claude-Code-only unless T10 landed. Open GitHub Sponsors "Founding Supporter" the same day (zero code) per the monetization brief | human | S | | T21, T22, T30 | One non-owner install produced a wrist buzz (the PRODUCT-SPEC success metric); recorded | |

## Phase 4 — App Store and the first paid tier (after the cohort)

| ID | Task | Owner | Effort | Depends | Proof | Issue |
|---|---|---|---|---|---|---|
| T32 | App Store review pack: Demo Host in the machine list, a live throwaway host, physical-device demo video, 1320×2868 iPhone screenshots (the watch set is already an accepted size), review notes, 4.2.7 statement | either | L | T21, T16 | Every checkbox in `docs/app-store-submission.md` ticked with the artefact named | |
| T33 | `mesh doctor` proves the alert loop end to end (synthetic PermissionRequest through hook, `/events`, APNs, device ack), red when buttons are absent | agent | M | T19 | `mesh doctor` prints the loop row; red when the hook is unregistered | #23 |
| T34 | Bind default to the Tailscale IPv4 else loopback, `--lan` opt-in with a warning; then self-signed TLS with the fingerprint pinned from `/pair/claim`, and drop `NSAllowsArbitraryLoads`. Prerequisite for any off-LAN copy and for charging customer C | agent | L | | `mesh pair` never prints a LAN address without `--lan`; the phone refuses a mismatched fingerprint | SEC-01 |
| T35 | One Apple-managed non-consumable IAP "Mesh Pro" gating app-side conveniences only; daemon stays MIT | either | M | T32 | Sandbox purchase unlocks the gated surfaces; free build still completes the alert-to-answer loop | |
| T36 | Ship MeshDesktop signed and notarized, or make `mesh desktop` print a download URL and never mention xcodebuild | human | L | T22 | `spctl -a -vvv` on a Mac that never built it reports Notarized Developer ID | #49, #77 |
| T37 | Architecture debt worth paying once the cohort is in: one `Mux` interface (ARCH-03), `wire.ts` + `version.ts` and `strict` for `server.ts` (ARCH-08), `Shared/Core` split so the relay routing is checkable headless (ARCH-09), a single `/snapshot` poll (ARCH-06) | agent | L | | The named checks exist and are green; `check-all.sh` DEPS is `Shared/Core/*.swift` | |

## Already done, still listed as open somewhere

Close these or fix the document; the record shows them shipped.

- `PrivacyInfo.xcprivacy` on all four Apple targets; `ITSAppUsesNonExemptEncryption: false` set. `docs/app-store-submission.md` still shows both unchecked.
- Local Network denial diagnostic with a Settings deep link (`ContentView.swift:174`). The submission doc still asks for it.
- In-app QR camera scanning shipped (#105 open; MEMORY.md says the opposite).
- One-command daemon release with tarball proof and sha256 (#43, #70, #47 open).
- `mesh doctor --fix` parsing fixed in 0.5.1 (#87 open).
- Modifier chords landed on the release branch (#109 open).
- CI runs the strict iOS smoke test on a real simulator (#75 open).
- Version lineage decision recorded in `docs/updating.md` (#68 open).
- `mesh.lesearch.ai` DNS and `/install.sh` live; four published links answer 200.
- The factory gate is no longer MISCONFIGURED (this branch).
- The 0.5.0 text-box crash is fixed in code and guarded; what is not done is getting that build onto TestFlight (T20).

## Open questions only the owner can answer

- Which build do the existing testers have, and is any on the stray 1.0 lineage? A
  delete-and-reinstall wipes the Keychain and un-pairs every machine; the invite note must
  say so.
- Is the first cohort Claude Code only? That decides whether T10 blocks.
- Has the 0.6 watch app ever run on the physical Series 9? T21 covers it once.
- Does the TestFlight group still exist under the name "Beta"? The script looks it up by
  name.
- Was the Xcode Cloud workflow ever created? It is a TestFlight path that does not need the
  local simulator, and deliberately does not run the smoke test either.
- Do the daily heartbeats arrive? The Supabase row count could not be checked from here.
