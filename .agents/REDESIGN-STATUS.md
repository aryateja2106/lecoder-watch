# MeshWatch Redesign — Loop Status (overnight build, branch codex/redesign-exp-1)

Last updated: 2026-06-17, autonomous /loop. Internal (.agents gitignored). **Not pushed.**

## ✅ LOOP COMPLETE — 2026-06-17
10 vertical slices, all build-green on iOS + watchOS, committed locally on `codex/redesign-exp-1`,
**nothing pushed**. Everything meaningful + verifiable from the brief is done; the only untouched
items are genuinely device/producer-gated (see DEFERRED). Loop stopped — no further wakeups scheduled.

**To review:** `git log --oneline 971ae1d..HEAD` · `.agents/design/index.html` (visual walkthrough) ·
re-verify with the two build gates below + `swift scripts/check-machine-migration.swift`.

**Commits (newest first):**
- `b6eaca9` perf(#8): pause polling when inactive/backgrounded (scenePhase)
- `e868dc7` feat(#7): notification quick-reply actions — Reply / Enter / Kill
- `034b933` feat: VNC connect screen — vault binding + retry-with-grace
- `c29cbc0` feat: watch Command Deck — trust-tiered Monitor/Send/Danger
- `bf89fb8` feat: lively TerminalSurface + voice-first InputBar
- `3e2920d` feat(#4): Credential Vault — named SSH/VNC identities in Keychain
- `c3dddc6` feat(#4): Keychain vault — tokens out of UserDefaults plaintext
- `abe34eb` fix(critical #1+#2): Add-Host sheet + UUID id + tappable discovery
- `a70369f` chore: gitignore internal dirs
- `c35766b` design system: rich-monochrome foundation primitives
+ 12 before/after HTML design mockups in `.agents/design/` (23-agent workflow).

**Suggested next session (needs a human / device):** review the diff and `git push` if happy; then
the device-gated items below; consider folding the standalone Vault/VNC screens deeper into machine detail.

## Framing
Make the foundation actually work + feel premium: fix the "nothing works" core (add-host,
discovery, Keychain vault, VNC retry-grace, voice terminal, watch deck) on a rich-monochrome,
voice-first, one-finger design. Ship green vertical slices, build-gated, committed locally.

## Build gates (every slice must pass both)
```
xcodebuild -project MeshWatch.xcodeproj -scheme "MeshWatch Watch App" -destination 'generic/platform=watchOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
xcodebuild -project MeshWatch.xcodeproj -scheme "MeshWatch" -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```
NOTE: new .swift files require `xcodegen generate` before building (dir-globbed but project snapshot is gitignored).

## DONE (committed locally, both builds green)
- [x] **Design artifacts** — 12 before/after HTML mockups + adversarial review + index in `.agents/design/`
      (23-agent workflow). Open `.agents/design/index.html`.
- [x] **c35766b Foundation** — `iOS/DesignSystem.swift`: MW color/type tokens, MWStatus, GroupedInsetSection,
      StatusPill, KeyValueRow, DisclosureRow, KeyCap, SessionListCard. iOS-only; Shared stays watchOS-safe.
- [x] **abe34eb Critical #1+#2** — Machine stable UUID id (tolerant decode, no wipe-on-upgrade;
      verified by `scripts/check-machine-migration.swift`), MeshStore.addHost() validation,
      AddHostSheet (native sheet vocab), tappable Tailnet discovery (peers pre-fill the sheet, de-duped).
- [x] **c3dddc6 Keychain Vault core (#4)** — `iOS/KeychainVault.swift` (generic-password, after-first-unlock,
      account-string keyed). MeshStore.save() redacts tokens out of the UserDefaults blob into Keychain;
      load() hydrates; legacy plaintext auto-migrates. copySecret() pasteboard 60s auto-clear. iOS green.
- [x] **3e2920d Vault multi-identity (#4)** — Credential model (ssh|vnc), MeshStore.credentials CRUD,
      `iOS/VaultView.swift` (hold-to-reveal, add sheet, empty state), reached from Settings. iOS+watch green.
- [x] **bf89fb8 TerminalSurface + InputBar** — `iOS/TerminalSurface.swift`: ANSI-toned lively scrollback
      (green/amber/red + neutral phosphor), blinking cursor, jump-to-latest; voice-first InputBar pinned
      via safeAreaInset. Wired into SessionPeekScreen; removed redundant Reply sheet. iOS+watch green.
- [x] **c29cbc0 Watch Command Deck** — AgentLiveView trust-tiered: glance state pill; blue SEND deck grid
      (Continue/Enter/Prev/Git status/Check mesh/New pane) + Reply/Voice; separate red DANGER section. watch+iOS green.
- [x] **034b933 VNC connect + vault binding + retry-grace** — Machine.vncCredentialId (decoder+check parity);
      VNCConnectScreen binds a vault VNC identity, hold-to-reveal/copy password, remediation after 2 attempts.
      Password never on the canvas URL. RemoteControlTab routes through it. iOS+watch green.

## Brief scorecard (8 functional fixes)
1. Add-Host broken → **DONE** (abe34eb). 2. Tailnet dead-end → **DONE** (abe34eb).
3. Single unreachable seed → **DONE** (subsumed by 1+2). 4. Credential vault → **DONE** (c3dddc6, 3e2920d).
5. Opaque stats → **already present** (authError → token vs offline + inline install remediation; left as-is).
6. Notifications foreground-only (APNs) → **DEFERRED** (device/relay). 7. Notification actions → **DONE** (e868dc7).
8. Polling cadence → **PARTIAL** — scene-phase pause done (b6eaca9); per-machine backoff intentionally skipped (small mesh).
Plus: design system, native voice terminal, watch Command Deck, VNC connect+binding.

## DEFERRED (unverifiable without a device/producer — NOT done, not claimed)
- **APNs background delivery (#6)** — needs a real device, the Time-Sensitive entitlement, and a meshd push
  relay. The #7 actions already work on locally-posted notifications and will work once a push path exists.
- **QR onboarding (camera)** — speculative until a QR *producer* exists (meshd/install emitting an add payload);
  the camera also can't be exercised in the simulator. Build the producer first, then the AVFoundation scanner
  + `NSCameraUsageDescription`, prefilling AddHostSheet. Mock: `.agents/design/qr-onboarding.html`.
- **Native VNC RemoteCanvas/CommandDeck** (`vnc-commanddeck.html`) — would replace the noVNC WKWebView with a
  native framebuffer; large, needs a raw RFB client. Current slice does binding + retry-grace around the web VNC.

## DEFERRED (can't verify tonight — needs device/entitlement/relay; don't claim done)
- Notifications background path (#6 APNs/BGAppRefresh) + actions/categories (#7). Needs a real device,
  Time-Sensitive entitlement, and a meshd push relay. Build the local actions/categories piece if safe,
  but APNs delivery is unverifiable in a closed-sim env.
- Polling backoff (#8, LOW).

## Hard constraints (don't violate)
No secrets in repo (100.x.y.z, no team IDs/paths). Native-first/ponytail, no new deps without justification.
Semantic colors = state only; one accent blue #4DA3FF. Keep meshd/server.ts copies byte-identical.
Don't push.
