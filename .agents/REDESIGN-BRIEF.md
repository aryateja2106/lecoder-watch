# LeSearch Mesh Redesign — Orchestration Prompt (paste into the waiting Opus 4.8 session)

> This is a **hand-off prompt**, not docs. Paste everything below the line into the Opus 4.8 (max / ultracode) session that is sitting on branch `codex/redesign-exp-1`. It is grounded in a completed 5-agent analysis of the RealVNC refs, the old LeCoder terminal, the two codex taste skills, the live code gaps, and a SwiftTerm/Popovers library eval. Internal only (`.agents/` is gitignored).

---

You are the lead of a **mini design+build team** for **LeSearch Mesh** — a native watchOS + iOS SwiftUI client (plus the `meshd` Bun daemon) for running and steering machines and AI coding agents over Tailscale. You are on branch `codex/redesign-exp-1` in `/Users/aryateja/Projects/lecoder-watch`. Run this as a **dynamic Workflow**: specialized agents in parallel where independent, a barrier only where a later stage needs all of an earlier stage's output, and an **adversarial design-review pass** before you commit anything. Ship in vertical slices that each build green — not one giant rewrite.

## Mission
Make the foundation actually *work* and feel premium. Today most of it doesn't: only one (unreachable) machine ever shows, you can't add an SSH/VNC host, discovered Tailscale peers are a dead end, credentials sit in plaintext, stats are opaque, notifications only fire while foregrounded. Fix the functional core **and** give it a rich-monochrome, voice-first, one-finger, small-screen-power-user design.

## Hard constraints (do not violate)
- **No secrets in the repo, ever.** No bearer tokens, real Tailscale IPs (use `100.x.y.z`), Apple Team IDs, `/Users/...` paths, real names/emails. This repo ships from clean history.
- **Native-first / ponytail.** Prefer SwiftUI controls, SF Symbols, system type, materials, haptics, native `.sheet`/`.popover`. Add **no new dependency** without a one-line justification that a few lines of native can't do it. (Eval already done: **SwiftTerm — SKIP** (no watchOS, needs a raw PTY stream we don't expose; iOS WKWebView bridge already works). **Popovers — SKIP** (native `.sheet` already used everywhere; lib dormant since 2022).)
- **Semantic status color contract:** green = working/ok, orange = needs input/auth, red = destructive/error, secondary = idle/offline. **At most one** non-status accent (our blue `#4DA3FF`).
- **Banned AI-default visuals:** purple-blue glow, glass-everywhere, nested cards, marketing-hero type, decorative blobs, random serif emphasis, gratuitous animation.
- **Two `server.ts` copies stay byte-identical:** `meshd/server.ts` and `install/payload/meshd/server.ts`. (You likely won't touch them — visual+client work — but if you do, `cp` and `diff`.)
- **Don't touch transport/store/bridge for a visual change:** avoid editing `MeshStore`, `WatchMeshStore`, `WatchLink`, `PhoneConnectivity`, `MeshClient`, `install/payload/rmux-bridge/*` *unless the task is explicitly a behavior fix* (the functional gaps below are explicit behavior fixes — those are allowed and expected).

## Build gates (every slice must pass)
```bash
xcodegen generate   # only if project.yml changed or .xcodeproj missing
xcodebuild -project MeshWatch.xcodeproj -scheme "MeshWatch Watch App" \
  -destination 'generic/platform=watchOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
xcodebuild -project MeshWatch.xcodeproj -scheme "MeshWatch" \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```
Both must end `** BUILD SUCCEEDED **`.

---

## Design system (establish this first, as a shared foundation other agents consume)
- **Rich monochrome, premium-but-readable.** Near-black surfaces, greyscale hierarchy, one blue accent. Dense screens stay *calm*; the accent directs the eye to **state** and **actions** only.
- **Lively terminal, not a boring black box.** The terminal surface is a framed card on near-black with real ANSI green/amber/red, a blinking cursor, and a jump-to-latest chip. The shell around it is monochrome; the terminal is where the life is.
- **Voice-first input.** Replace the dead "Tap to type" bar with a dual-mode **InputBar**: a mic (tap or hold → dictate, "tap here to speak"), a center tap that raises the keyboard + command deck, a send button that brightens with text. Modes: idle / dictating / typing.
- **One finger, very small screen, low attention.** 44pt minimum targets, thumb-zone layout, symbol-plus-short-label, everything scrollable, text fits small watch sizes without hiding the next action.
- **Accessible.** Dynamic Type survives, VoiceOver labels on icon-only controls, no undiscoverable bare-icon affordances (add labels or a first-run coachmark).
- **Native iOS sheet vocabulary everywhere:** grabber handle, centered title, trailing circular **Done** check pill, grouped-inset sections.
- **Taste dials (variance / motion / density):** Watch session 4/2/8 · iPhone terminal 4/3/7 · Settings/installer 2/1/7 · Empty/onboarding 5/3/4. Motion explains a state change, never decorates.

---

## Component library (build these as reusable SwiftUI views; specs from the RealVNC + old-LeCoder refs)

**From RealVNC (machine-detail + VNC control surfaces):**
- `GroupedInsetSection` — the one styling primitive: rounded inset container, hairline dividers, optional header/footer caption. Everything dense is built from it.
- `ConnectionInfoCard` — read-only facts for a connected machine: centered bold name + trailing `StatusPill`, body = stack of `KeyValueRow`s. States: connected / connecting / disconnected(greyed).
- `KeyValueRow` — label · spacer · grey value, optional secondary subtext (e.g. Estimated Speed with RTT beneath). Non-interactive *or* disclosure mode.
- `DisclosureRow` — `KeyValueRow` + trailing chevron → presents a picker. **The chevron is the IA split:** facts have none, actions/settings do.
- `StatusPill` — compact live state: success check / connecting spinner / warning amber / offline grey-outline; doubles as a sheet **Done** affordance.
- `CommandDeck` — **floating, collapsible** toolbar over the canvas: left `ModifierKeyStrip`, center `TextInjectionField`, right preview toggle + collapse chevron (shrinks to a handle so the canvas stays maximized); auto-hides on idle. **Never frame the canvas in a navbar.**
- `ModifierKeyStrip` — scrollable row of `KeyCap`s; **sticky** ctrl/alt/cmd latch & combine with the next press, del/esc fire immediately. **Do not truncate the last key** (RealVNC's bug) — wrap or add an overflow; demote rare keys (win/opt) to overflow.
- `KeyCap` — single key button, ≥44pt, states normal/pressed/latched(persistent accent border)/disabled.
- `TextInjectionField` — inline pill field that streams a typed/pasted string into the remote (great for pasting a command/token/path into an agent) — lead with this over the mirrored OS keyboard (which eats half the canvas).
- `RemoteCanvas` — full-bleed, chrome-free framebuffer + soft cursor: one-finger drag = move, tap = click, two-finger = scroll, pinch = zoom, pan for hi-res desktops.
- `GestureGuideSheet` + `GestureRow` — mode-aware "How to control" cheat sheet: glyph + plain-language table; content swaps with interaction mode.
- `QualityPicker` (Automatic/High/Med/Low, with bandwidth/latency caption) + `InteractionModePicker` (Mouse/Touch, swaps gesture help).

**From the old LeCoder terminal (the lively layer):**
- `StatusHeader` — search-or-ssh **CONNECT** pill; on terminal: back · status dot · host-user · tmux/native badge.
- `InputBar` — the voice-first dual-mode bar above (the centerpiece of the redesign).
- `TerminalSurface` — green-accented live terminal card; mono scrollback, ANSI green/amber/red, blinking cursor, jump-to-latest chip.
- `ActionMenuPopover` — premium icon-row sheet: New Connection · Attach Tmux · File Browser · Network/Process Explorer · System Load.
- `SessionListCard` — reusable host/vault/key/session row: accent icon · title · subtitle · trailing chevron/dot/X; active/connecting/offline variants.
- `SegmentedSettingRow` — choice lists (Native/Tmux/Mosh/None) right-checkmark + green-on toggles.
- `SessionTabStrip` — multi-session chips with status dot + close X, trailing **+** opens New Connection.

---

## Functional fixes (the "nothing works" backlog — fix in this order; criticals first)

1. **Add-machine is broken (CRITICAL)** — `iOS/MeshStore.swift:136` appends `Machine(host:"new-machine", ip:"", …)`; empty IP never resolves, row is permanently offline; `Machine.id == host` so two unrenamed adds collide in `ForEach`/`onDelete`. → Build a real **Add-Host sheet** (required: IP/tailnet host + credential; optional: name/port/bridge/VNC), validate non-empty+unique, `store.update()` to persist, then `refresh()` that one machine and show reachable/auth status inline. Give `Machine` a **stable UUID id** separate from `host` (migrate the Codable + `firstIndex(where: id)` lookups).
2. **Tailnet peers are a dead end (CRITICAL)** — `iOS/ContentView.swift:132` renders discovered pi/dataflow/jetson as non-interactive `StatRow`. → Wrap each peer in a **Button that pre-fills the Add-Host sheet** (ip = first dotted IP, host = peer.host sans tailnet suffix). De-dup/disable peers already configured. This is the single highest-leverage fix: discovery already works end-to-end (`/tailnet`), it just has no tap target.
3. **Single unreachable seed (HIGH)** — `Shared/Models.swift:63` seeds one bogus `100.100.100.100` row. → Fixed by 1+2; optionally auto-offer to add online peers from the first reachable machine's `/tailnet`. Make the empty default obviously a setup placeholder that routes to discovery.
4. **CREDENTIAL VAULT — the headline feature (HIGH).** Today `save()` JSON-encodes the whole `[Machine]` (tokens included) into **UserDefaults plaintext** (`MeshStore.swift:120`), and tokens get copied to the pasteboard freely. → Build a **local-first Keychain vault**:
   - Move every secret out of the `Machine` Codable: UserDefaults holds only non-secret fields; secrets live in **Keychain** (`kSecClassGenericPassword`, keyed by machine UUID + credential id, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`). Load lazily when building `MeshClient`.
   - Model **multiple credentials per machine**: N **SSH** identities (user + password *or* key) and N **VNC** identities (user + password), each named/selectable. A machine references credential ids; the secret bytes never leave Keychain.
   - **Never** put a secret on the pasteboard without an auto-clear timeout; prefer not at all.
   - **No new dependency** — iOS Keychain *is* the local-first vault. (If an external OSS vault for cross-device sync is wanted later, it layers on this same model — leave a clean seam, don't build it now. `ponytail:` note the seam.)
   - UX: a `SessionListCard`-style **Vault/Credentials** screen to add/name/pick SSH & VNC identities, and a per-machine picker to bind which identity each connection uses.
5. **Opaque stats (HIGH)** — `MeshStore.swift:171` gates stats on a combined catch; an unreachable *or* 401 machine shows "not available" with no signal. → Distinguish **unreachable (network)** from **auth-rejected (token)**; on auth error show inline remediation (copy install command) at the top of the card; don't gate all stats on one catch.
6. **Notifications only fire foregrounded (CRITICAL)** — everything derives from an 8s foreground `Timer` (`MeshStore.swift:146`); nothing survives suspension. → Add a real background path: **APNs** (register remote notifications; have `meshd`/a tiny relay push on needs-input/finished/error/offline using its existing `/events` ingest, `server.ts:330`), with **BGAppRefreshTask** as a lighter interim. Stop relying solely on the foreground timer.
7. **No notification actions/categories (MEDIUM)** — `NotificationManager.swift:111`; a "needs input" ping with no quick-reply defeats the point. → Register `UNNotificationCategory`s with actions (Reply via `UNTextInputNotificationAction`, Approve/Enter, Kill), set `categoryIdentifier` per kind, handle in `didReceive` by sending to `meshd`. Add the **Time Sensitive Notifications entitlement** (the code already wants `.timeSensitive` but iOS silently downgrades it). Ensure every event host maps to a real `Machine` (fixed by 1–3).
8. **Polling: fixed 8s, no backoff, full fan-out every cycle (LOW)** — `MeshStore.swift:146`. → Decouple cadences (stats/agents/events short; tailnet/usage/bridge/VNC every 30–60s or on demand), exponential backoff for unreachable/auth-rejected machines, slow/pause when scene inactive.

## VNC connection UX — retry-with-grace
RealVNC asks for credentials **2–3 times before closing**; our flows should too. When a connection is rejected, **don't drop it** — show an inline retry with the bound credential pre-filled, let the user pick a different vault identity, and only after a few attempts surface a clear "still failing — check Screen Sharing / token" remediation. Non-technical users need room for mistakes across many machines.

## Watch surface — Command Deck, not a terminal
The watch is for **glance → decide → send a tiny intervention** (the iPhone WKWebView bridge stays the full terminal). Build the watch session screen as: glance layer (latest output + session state + pane awareness) → a **Command Deck** of preset actions (Continue, Enter, Stop, Git status, Check mesh, New pane, Reply, Voice command) → dictation/Scribble for ad-hoc input → **trust-tiered controls: Monitor (read-only) → Send (keystroke) → Danger (stop/kill)** with Danger visually separated and red. No custom keyboard on watch.

## Suggested workflow shape
1. **Foundation (barrier):** one agent lands the design-system primitives (`GroupedInsetSection`, color/type tokens, `StatusPill`, `KeyCap`) so every later agent builds on the same base. Build green before fan-out.
2. **Parallel build (pipeline):** independent agents per slice — (a) Add-Host sheet + UUID id + tappable tailnet discovery; (b) Keychain credential vault + multi-SSH/VNC model + binding UI; (c) VNC control screen (`CommandDeck`/`RemoteCanvas`/gesture guide) + retry-with-grace; (d) voice-first `InputBar` + `TerminalSurface` polish; (e) notifications background path + actions; (f) watch Command Deck. Each verifies its own build.
3. **Adversarial design review (before commit):** a reviewer agent checks every slice against the semantic-color contract, the banned-visuals list, 44pt/Dynamic Type/VoiceOver, the read-vs-act chevron split, and "does the smallest patch touch transport/store unnecessarily?" Reject and bounce back what fails.
4. **Commit** in focused vertical slices with honest messages; never claim a feature the code doesn't have.

Start by confirming the framing in one line, then stand up the foundation slice.
