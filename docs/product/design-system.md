# LeSearch AI — design-system registry

A grep-able map of what a redesign would actually touch: tokens (colors, spacing,
radius, type, haptics) and where each is defined, every reusable SwiftUI view, every
top-level screen per surface with its screenshot path, and the interaction rules a
`scripts/check-*` already pins so a redesign doesn't quietly break one.

There is **no shared design-token file** in this codebase — no `Theme.swift`,
`Colors.swift` or `DesignSystem.swift` under `iOS/`, `Watch/`, `MeshDesktop/` or
`Shared/`. SwiftUI code uses ad-hoc literals (`Color.orange`, `.padding(12)`,
`.font(.caption)`) directly in each view; native platform styles (`.borderedProminent`,
system fonts, system colors) are the closest thing to a token system on the Apple
surfaces. The web landing page is the one place real CSS custom-property tokens exist.

---

## Tokens

### Web (`web/index.html`) — the one real token system

Defined once, in the `:root` block, `web/index.html:22-30`:

| Token | Value | Defined at |
| --- | --- | --- |
| `--bg` | `#191919` | web/index.html:23 |
| `--bg-2` | `#202020` | web/index.html:23 |
| `--panel` | `#1f1f1f` | web/index.html:23 |
| `--elev` | `#252525` | web/index.html:23 |
| `--hover` | `#2a2a2a` | web/index.html:23 |
| `--line` | `#2a2a2a` | web/index.html:24 |
| `--line-2` | `#373737` | web/index.html:24 |
| `--line-h` | `#525252` | web/index.html:24 |
| `--ink` | `#e9e9e7` | web/index.html:25 |
| `--ink-2` | `#9b9b9b` | web/index.html:25 |
| `--ink-3` | `#6b6b6b` | web/index.html:25 |
| `--ok` | `#4ade80` | web/index.html:26 |
| `--danger` | `#ef4444` | web/index.html:26 |
| `--mono` | `'JetBrains Mono','Fira Code','SF Mono',SFMono-Regular,Menlo,Consolas,monospace` | web/index.html:27 |
| `--radius` | `8px` | web/index.html:28 |
| `--wrap` | `1040px` | web/index.html:28 |

Body copy: `font-size:15.5px; line-height:1.65` (web/index.html:34-35). The header
comment names the rule directly: "Accent color is reserved for actions: green =
affirmative, red = destructive" (web/index.html:20-21) — `--ok` and `--danger` are the
only two colors with meaning; everything else is grayscale.

`web/privacy.html:16-23` defines the **identical** token block (same names, same
values, `--wrap:720px` instead of `1040px` — it is a prose page). `web/brand/index.html`
defines a parallel, prefixed set (`--lw-bg`, `--lw-ink`, …) at `web/brand/index.html:13-31`,
light by default with a dark override under `:root:not([data-theme="light"])` and an
explicit `:root[data-theme="dark"]` — this is the brand board's own copy, not shared
with the other two pages. None of the three files `@import` or otherwise share a single
source; a token changed in `index.html` has to be changed by hand in the other two.

### Where there are no tokens (iOS / Watch / MeshDesktop)

Every SwiftUI screen reaches for a literal directly. Counts below are `grep -c` across
`iOS/`, `Watch/`, `MeshDesktop/` (`*.swift`).

**Named colors** (`.orange`, `.red`, …, as in `.foregroundStyle(.orange)` or
`Color.red`):

| Literal | Count |
| --- | --- |
| `.orange` | 63 |
| `.red` | 43 |
| `.green` | 31 |
| `.white` | 30 |
| `.black` | 23 |
| `.blue` | 10 |
| `.gray` | 5 |
| `.purple` | 2 |

`.orange` is the de-facto "needs attention / warning" color and `.red` the de-facto
"destructive / error" color everywhere — the same two-color-with-meaning convention as
the web tokens (`--ok` / `--danger`), just never named as such in Swift. `Color(red:...)`
/ custom RGB literals appear 6 times total — the rest of color usage is system
semantic colors (`.primary`, `.secondary`, `Color(.systemBackground)`, etc.), which
already adapt to light/dark and are not counted here as "ad-hoc."

**Padding** (`.padding(<n>)`, literal only — bare `.padding()` also appears 4 times):

| Value | Count |
| --- | --- |
| `10` | 7 |
| `8` | 5 |
| `16` | 5 |
| `12` | 5 |
| `24` | 4 |
| `20` | 4 |
| `14` | 2 |
| `2` | 2 |
| `9` | 1 |

**Stack spacing** (`spacing: <n>` in `VStack`/`HStack`/`LazyVGrid`, etc.):

`6` → 40, `8` → 29, `4` → 26, `10` → 22, `2` → 15, `3` → 11, `12` → 11, `0` → 10, `1` → 9,
`16` → 3. `6` and `8` between the most common — there is no single spacing scale, values
cluster loosely around 2/4/6/8/10/12/16 without a named step system.

**Corner radius** (`cornerRadius:`):

`14` → 12, `8`/`10` → 7 each, `12` → 4, `6`/`16` → 3 each, `22`/`24` → a handful, `5`/`9` → 1-2
each. `14` is the most common "card" radius; `8` matches the web token's `--radius: 8px`
by coincidence, not by a shared source.

**Type** (`.font(.<style>)`, Dynamic Type styles, no fixed-point sizes for body text):

`.caption` → 97, `.headline` → 33, `.callout` → 12, `.subheadline` → 10, `.footnote` → 8,
`.body` → 6, `.largeTitle` → 2. A handful of fixed `.system(size: N)` calls exist (11pt
watch labels, 44pt/40pt large glyphs) — these are the exception, not the rule; the vast
majority of text uses Apple's semantic Dynamic Type styles directly, which is itself a
form of "using the platform's token system" rather than inventing one.

**Haptics** — every haptic call in the codebase is `WKInterfaceDevice.current().play(...)`
on watchOS (24 call sites, all in `Watch/RemoteView.swift` and `Watch/WatchMeshStore.swift`);
there is no `UIImpactFeedbackGenerator`/`UINotificationFeedbackGenerator` call anywhere
in `iOS/` — the phone app has no haptic feedback of its own today. Watch haptic types
used: `.click` (pointer move / key send), `.success` / `.failure` (command result),
`.start` / `.stop` (drag-lock engage/release), `.retry`.

---

## Components

Every `struct ... : View` (including `private struct`) found by
`grep '^struct .*: View\|^private struct .*: View'`, grouped by surface and source
file. 67 in `iOS/`, 25 in `Watch/`, 6 in `MeshDesktop/` (98 total).

### iOS (67)

| Component | Purpose | Source file | Used from |
| --- | --- | --- | --- |
| `ContentView` | App shell: the 5-tab layout (Machines, Monitor, Terminal, Remote, Settings) | iOS/ContentView.swift | App root |
| `MonitorBell` | The bell icon + badge shown in every tab's top bar | iOS/ContentView.swift | ContentView toolbar |
| `AppsTab` | The Apps tab container | iOS/ContentView.swift | ContentView |
| `MonitorView` | Usage/limits + events feed, opened from the bell | iOS/ContentView.swift | MonitorBell sheet |
| `LocalNetworkBlockedBanner` | iOS Local Network permission nudge | iOS/ContentView.swift | MachinesTab |
| `MachinesTab` | The Machines list with live thumbnails | iOS/ContentView.swift | ContentView |
| `MachineDetailView` | One machine's detail screen | iOS/ContentView.swift | MachinesTab row |
| `SessionStateBadge` | Small colored state chip for a session | iOS/ContentView.swift | MachineDetailView, session rows |
| `MachinePowerSection` | Power actions (sleep/restart/shutdown/etc.) | iOS/ContentView.swift | MachineDetailView |
| `DaemonUpdateSection` | "Your daemon is out of date" banner + action | iOS/ContentView.swift | MachineDetailView |
| `WakeRow` | Wake-on-LAN row | iOS/ContentView.swift | MachinePowerSection |
| `MachineSetupSection` | Setup-as-one-line summary | iOS/ContentView.swift | MachineDetailView |
| `AttentionRow` | A session row needing the user's attention | iOS/ContentView.swift | MachinesTab, MonitorView |
| `SessionLimitsBanner` | Usage-limit warning banner | iOS/ContentView.swift | MachineDetailView |
| `UsageRows` | Per-provider usage rows | iOS/ContentView.swift | MonitorView, Settings |
| `LimitRow` | One provider's usage gauge row | iOS/ContentView.swift | UsageRows |
| `SettingsTab` | Settings screen: quick commands, pinned limits, app lock, guides | iOS/ContentView.swift | ContentView |
| `DiagnoseRow` | One `/doctor` check row | iOS/ContentView.swift | SettingsTab, MachineDetailView |
| `PinnedLimitEditor` | Choose which usage limits are pinned | iOS/ContentView.swift | SettingsTab |
| `RemoteWebScreen` | Fallback WebView for the daemon's own web console | iOS/ContentView.swift | SettingsTab |
| `StatRow` | Generic label/value stat row | iOS/ContentView.swift | Multiple detail screens |
| `ServiceStatusRow` | Daemon/service up-down row | iOS/ContentView.swift | MachineDetailView |
| `SectionLabel` | Small section header label | iOS/ContentView.swift | Multiple screens |
| `MachineThumbnail` | Live screen thumbnail image for a machine row | iOS/ContentView.swift | MachinesTab |
| `AppsLibraryView` | Cross-machine apps library, grouped by app | iOS/AppsLibraryView.swift | AppsTab |
| `MeshAppRow` | One app row (install/open) | iOS/AppsLibraryView.swift | AppsLibraryView, MeshAppsScreen |
| `PairingScannerSheet` | QR camera sheet for pairing | iOS/PairingScanner.swift | PairMachineView |
| `RemoteScreenView` | Screen + trackpad + capsule + key bar | iOS/RemoteScreenView.swift | MachineDetailView |
| `LaunchSheet` | Pick an app/terminal to launch on the remote machine | iOS/RemoteScreenView.swift | RemoteScreenView capsule |
| `FileViewer` | Read one file (Markdown/HTML/code/text) | iOS/FileViewer.swift | FileBrowserView |
| `MarkdownDocument` | Rendered Markdown body | iOS/FileViewer.swift | FileViewer |
| `LockScreen` | Face ID / passcode lock overlay | iOS/AppLock.swift | App root, over ContentView |
| `LevelMeter` | Microphone level meter | iOS/VoiceInput.swift | VoiceInput sheet |
| `PairMachineView` | Pairing entry screen (code / QR / manual) | iOS/PairMachineView.swift | NoMachinesView, Settings |
| `StepRow` | One numbered onboarding step | iOS/PairMachineView.swift | PairMachineView |
| `CopyableCommand` | Tap-to-copy shell command block | iOS/PairMachineView.swift | PairMachineView, GuidesView |
| `NoMachinesView` | First-run empty state | iOS/PairMachineView.swift | MachinesTab (empty) |
| `MachineStatsRow` | One load metric row (mem/disk/CPU) | iOS/MachineStatsView.swift | MachineStatsView |
| `MachineStatsView` | Load-at-a-glance gauges + chart + process list | iOS/MachineStatsView.swift | MachineDetailView |
| `ExposedSecretsScreen` | List of redacted exposures | iOS/ExposedSecretsScreen.swift | SettingsTab |
| `ExposureRow` | One exposure row, mark-rotated action | iOS/ExposedSecretsScreen.swift | ExposedSecretsScreen |
| `GuidesView` | Static how-to guides list | iOS/GuidesView.swift | SettingsTab, empty states |
| `AgentChatView` | Full chat transcript for one agent session | iOS/AgentChatView.swift | Session row |
| `MenuCard` | An agent's own on-screen menu, read as tappable buttons | iOS/AgentChatView.swift | AgentChatView |
| `DecisionCard` | Risk-classified yes/no decision card | iOS/AgentChatView.swift | AgentChatView |
| `SentDecisionLine` | Already-answered decision, shown inline | iOS/AgentChatView.swift | AgentChatView |
| `ChatBubble` | One chat message bubble | iOS/AgentChatView.swift | AgentChatView |
| `MarkdownBlocks` | Rendered Markdown inside a chat bubble | iOS/AgentChatView.swift | ChatBubble, ToolResultCard |
| `ThinkingDisclosure` | Collapsible "thinking" block | iOS/AgentChatView.swift | AgentChatView |
| `ToolResultCard` | A tool call's result, rendered | iOS/AgentChatView.swift | AgentChatView |
| `ExpandedDetailBlock` | Expanded detail under a card | iOS/AgentChatView.swift | ToolResultCard |
| `TerminalFallbackBlock` | "Open in Terminal instead" fallback card | iOS/AgentChatView.swift | AgentChatView |
| `ArtifactCardView` | An app/artifact an agent produced, as a card | iOS/AgentChatView.swift | AgentChatView |
| `ArtifactDetailSheet` | Full-screen artifact detail | iOS/AgentChatView.swift | ArtifactCardView |
| `SuggestionChip` | Tappable quick-command chip | iOS/AgentChatView.swift | AgentChatView composer |
| `AccountView` | Create/sign-in form for the optional feedback account | iOS/AccountView.swift | SettingsTab |
| `FeedbackView` | "Report a problem" form | iOS/FeedbackView.swift | SettingsTab |
| `TerminalTab` | Terminal tab shell (session list, bridge, new-session) | iOS/TerminalView.swift | ContentView |
| `ManualBridgeScreen` | Add a host manually by address | iOS/TerminalView.swift | TerminalTab |
| `MeshAppsScreen` | Per-machine apps screen | iOS/TerminalView.swift | Machine ⋯ menu |
| `NewSessionSheet` | Start a session: CLI, cwd, task | iOS/TerminalView.swift | TerminalTab |
| `SessionPeekScreen` | Recent output + answer for one session | iOS/TerminalView.swift | Session row |
| `FlowButtons` | Quick agent-menu action buttons | iOS/TerminalView.swift | SessionPeekScreen |
| `BridgeTerminalScreen` | Live xterm.js WebView terminal | iOS/TerminalView.swift | TerminalTab |
| `StatPill` | Small pill-shaped stat badge | iOS/TerminalView.swift | Session rows |
| `LimitHandoffBanner` | "Continue with…" hand-off banner | iOS/TerminalView.swift | SessionPeekScreen |
| `FileBrowserView` | Filesystem browser | iOS/FileBrowserView.swift | MachineDetailView |

### Watch (25)

| Component | Purpose | Source file | Used from |
| --- | --- | --- | --- |
| `RemoteView` | Remote-control hub root | Watch/RemoteView.swift | WatchRootView |
| `RemoteHubView` | Tab picker across Remote sub-screens | Watch/RemoteView.swift | RemoteView |
| `RemoteKeysView` | Key bar (arrows, Esc, chords) | Watch/RemoteView.swift | RemoteHubView |
| `RemoteWindowView` | Window list / activate | Watch/RemoteView.swift | RemoteHubView |
| `RemoteMediaView` | Media transport keys | Watch/RemoteView.swift | RemoteHubView |
| `RemoteSystemView` | System actions (power, etc.) | Watch/RemoteView.swift | RemoteHubView |
| `RemoteClipboardView` | Read/send clipboard | Watch/RemoteView.swift | RemoteHubView |
| `RemoteKeyboardView` | Text-entry keyboard | Watch/RemoteView.swift | RemoteHubView |
| `RemoteAppsView` | App launcher / activate-by-name | Watch/RemoteView.swift | RemoteHubView |
| `TypeSheet` | Type/dictate sheet | Watch/RemoteView.swift | RemoteKeyboardView |
| `DictateLink` | Entry point into dictation | Watch/WatchViews.swift | WatchRootView, AgentLiveView |
| `WatchRootView` | App root: machines → sessions | Watch/WatchViews.swift | App entry |
| `MachinesListView` | Machines list | Watch/WatchViews.swift | WatchRootView |
| `AttentionRow` | Attention-needed session row | Watch/WatchViews.swift | SessionsView |
| `EventsView` | Recent events list | Watch/WatchViews.swift | Machine detail |
| `OpenOnMacButton` | Push a link to the Mac | Watch/WatchViews.swift | AgentLiveView |
| `SessionStateChip` | Small session state chip | Watch/WatchViews.swift | SessionsView, AttentionRow |
| `SessionsView` | Session list for a machine | Watch/WatchViews.swift | MachinesListView |
| `FollowsTail` (ViewModifier) | Auto-scroll-to-bottom modifier | Watch/WatchViews.swift | AgentLiveView |
| `AgentLiveView` | Crown-scrollable live terminal | Watch/WatchViews.swift | SessionsView row |
| `ScreenPeekView` | Screen-peek image view | Watch/WatchViews.swift | RemoteHubView |
| `UsageView` | Usage gauges list | Watch/WatchViews.swift | WatchRootView |
| `WatchLimitRow` | One usage-limit row | Watch/WatchViews.swift | UsageView |
| `GaugeRow` | Generic gauge row | Watch/WatchViews.swift | UsageView, MachineStats-equivalent |
| `MenuOptionRow` | One agent-menu option row | Watch/WatchViews.swift | AgentLiveView menu |

### MeshDesktop (6)

| Component | Purpose | Source file | Used from |
| --- | --- | --- | --- |
| `PairView` | Pairing QR + code on the Mac's own screen | MeshDesktop/PairView.swift | Menu → Pair iPhone |
| `MenuContent` | The menu-bar dropdown contents | MeshDesktop/MeshDesktopApp.swift | MenuBarExtra |
| `PermissionsView` | "What this Mac still needs" window | MeshDesktop/PermissionsView.swift | Menu → Permissions |
| `CheckRow` | One `/doctor` check row | MeshDesktop/PermissionsView.swift | PermissionsView |
| `NotificationRow` | Notifications-permission row (app-side, not daemon) | MeshDesktop/PermissionsView.swift | PermissionsView |
| `DaemonDown` | "Daemon isn't running" empty state | MeshDesktop/PermissionsView.swift | PermissionsView |

---

## Screens

Per-surface top-level screens (tabs, sheets, pushed views) with source file and the
screenshot path the orchestrator will capture. **No image files are created by this
document** — these are the paths a later capture step is expected to fill in.

### iPhone

| Screen | Source file | Screenshot |
| --- | --- | --- |
| Machines tab | iOS/ContentView.swift (`MachinesTab`) | docs/product/shots/iphone-machines.png |
| Terminal tab | iOS/TerminalView.swift (`TerminalTab`) | docs/product/shots/iphone-terminal.png |
| Apps tab | iOS/AppsLibraryView.swift | docs/product/shots/iphone-apps.png |
| Settings tab | iOS/ContentView.swift (`SettingsTab`) | docs/product/shots/iphone-settings.png |
| Report a problem | iOS/FeedbackView.swift | docs/product/shots/iphone-report-a-problem.png |
| Pair a machine | iOS/PairMachineView.swift | docs/product/shots/iphone-pair.png |

Also present but with no requested capture: Monitor sheet, Remote screen & control,
Files, Agent chat, Account, Guides, Exposed secrets, Voice input (see the component
and feature tables above for their files).

### Apple Watch

| Screen | Source file | Screenshot |
| --- | --- | --- |
| Machines list | Watch/WatchViews.swift (`MachinesListView`) | docs/product/shots/watch-machines.png |
| Agent live session | Watch/WatchViews.swift (`AgentLiveView`) | docs/product/shots/watch-session.png |

Also present, no requested capture: Root, Sessions list, Events, Usage, Remote hub,
Type sheet + dictation.

### Mac menu bar

| Screen | Source file | Screenshot |
| --- | --- | --- |
| Menu bar dropdown | MeshDesktop/MeshDesktopApp.swift (`MenuContent`) | docs/product/shots/mac-menubar.png |

Also present, no requested capture: Permissions window, Pair iPhone window.

---

## Interaction rules enforced by checks

Rules that a `scripts/check-*` pins structurally, so a redesign that violates them
fails a check rather than shipping silently broken:

| Rule | Enforced by | What breaks if violated |
| --- | --- | --- |
| Every `TextField` whose value reaches a shell binds through `.shellSafe` (iOS/ShellSafeText.swift), not a plain `$var` | check-phone-input-and-wake.sh | iOS smart punctuation turns straight quotes into curly ones, breaking any quoted shell command typed on the phone |
| Watch key strip only sends keys the daemon's `KEY_SEND_KEYS` map (install/payload/meshd/server.ts) actually knows | check-watch-terminal-wiring.sh | A watch button sends a key the daemon silently drops — "clean but unusable" |
| Modifier chords (⌘⇧4, etc.) are sent as a real down/hold/up sequence, never a single event with flags | check-mesh-chords.sh | A chord loses a modifier in transit and types garbage into whatever has focus |
| Full-pad trackpad: one tap = left click, a second tap inside the same window = right click | check-trackpad-clicks.swift | Tap targets misfire on the remote screen |
| The watch's drag-lock toggle must send `.release` from its `onDisappear` teardown path, not only from the toggle itself | check-drag-lock-release.sh | Leaving the Remote screen with drag-lock on leaves the Mac's mouse button physically held down |
| Watch → phone commands without a reply handler are still delivered (`PhoneConnectivity.session(_:didReceiveMessage:)`), and a failed one returns `mesh-error: <reason>` instead of a silent tick | check-relay-ack.swift, check-relay-receiver.sh | A watch command looks sent but never arrives, with no error shown |
| The Live Activity picks the one session `sessionsNeedingAttention(from:)` names — never a second, independently computed "what needs me" | check-live-card.swift | Lock Screen/Dynamic Island/watch Smart Stack disagree with each other about what's waiting |
| Feedback reports never read `SecureStore` from `FeedbackView`, and the cloud session is only ever saved/loaded/deleted through `SecureStore` from `LeSearchCloud` | check-feedback-cloud.sh | An auth token ends up in `UserDefaults` (plaintext) instead of the Keychain |
| Every secret shape the daemon's redactor knows is replaced before a feedback bundle is built | check-feedback-redact.swift | A token or key leaks into a problem report shared outside the machine |
| iOS and daemon Supabase anon keys must be byte-identical | check-feedback-cloud.sh | The app and the daemon silently point at different (or broken) feedback backends |
