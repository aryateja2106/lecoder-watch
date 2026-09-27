# UX audit — walk every screen, then fix in order

The owner's verdict after the first device day: many working parts, many rough screens.
This is the repeatable way to find all of them without a person tapping through the app
for an hour, and the prompts to hand any agent (Claude Code, Cursor, Antigravity, Codex).

## The loop

1. **Crawl** — a runner drives the app on a simulator, visits every tab and every button it
   can reach, waits for the screen to settle, and saves one screenshot plus the
   accessibility tree per screen. Output: `docs/audit/<date>/<screen>.png` + `.txt`.
2. **Grade** — a second agent reads every screenshot and tree and writes one row per
   screen: what is on it, what is unreadable, what overlaps, what is inconsistent with the
   rest of the app, which tap did nothing. Output: `docs/audit/<date>/REPORT.md`, severity
   ordered, with the screenshot name on every row.
3. **Fix** — one issue per commit, smallest diff, verified by re-crawling that screen.

The crawler must never run against an app paired to a real machine: every tap in this app
can type into a live agent or move a real mouse. Pair the simulator to a throwaway daemon
(`MESHD_PORT=8898 …`, see AGENTS.md) or to nothing.

## Prompt 1 — crawl (Haiku or Sonnet, one per tab is fine)

```
Repo: /Users/aryateja/Projects/lecoder-watch-ade (branch feat/ade-0.6). Read AGENTS.md rule 1.
Goal: capture every screen of the iPhone app on the booted simulator `iOS27-repro`.
Never pair the simulator app to 127.0.0.1:8899 (the owner's real Mac). Start a throwaway
daemon first:
  MESHD_HOST=127.0.0.1 MESHD_PORT=8898 MESHD_TOKEN=audit-token-0123456789abcdef0123456789 \
  MESHD_EVENTS_PATH=/private/tmp/audit/e.jsonl MESHD_EXPOSURES_PATH=/private/tmp/audit/x.json \
  MESHD_TELEMETRY=off HOME=/private/tmp/audit/h bun install/payload/meshd/server.ts &
  rmux new-session -d -s audit-shell   # so the session list is not empty
Build and install: xcodegen generate; xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch
  -destination 'id=<sim udid>' -derivedDataPath /private/tmp/audit/dd build; xcrun simctl install
  booted <app>; xcrun simctl launch booted com.lecoder.meshwatch.
Pair it to http://127.0.0.1:8898 with the claim code from `curl -s http://127.0.0.1:8898/pair/new`.
Then, for the tab <TAB>: visit every screen reachable from it — every row, button, menu item,
sheet, toggle — in a depth-first order. Before each tap and after each screen settles
(sleep 1.5), save `xcrun simctl io booted screenshot docs/audit/<date>/<tab>-<n>-<name>.png`
and the accessibility tree (`xcrun simctl ui booted …` is not available; use the XCUITest
runner in UITests/ if you can drive it, else describe the screen from the screenshot).
Log every tap that produced no visible change as "dead tap" with its screenshot. Never type
into a terminal or chat composer; never tap Stop, Allow, Deny, Kill, Remove, Restart, Shut
down, Sleep or Lock. Uninstall the sim app when done. Report: the list of screenshots, the
dead taps, and any crash (check `xcrun simctl spawn booted log stream` for the bundle id).
```

Run it once per tab: Machines, Terminal, Remote, Monitor, Settings. Five short runs beat one
long one that dies on the session limit.

## Prompt 2 — grade (Sonnet)

```
Read every file under docs/audit/<date>/ (screenshots + notes) for the LeSearch Mesh iPhone
app. For each screen write one row: screen | what a first-time user is meant to do here |
what is wrong (unreadable text, overlap, clipped edges, inconsistent spacing or type,
controls that look tappable but are not, two ways to do one thing, jargon) | severity
(blocks a task / confuses / cosmetic) | screenshot. Then a second table of cross-screen
inconsistencies (three different button styles, two different "back" behaviours, capitalisation).
Then the ten fixes that remove the most confusion per line of code, each as a one-paragraph
task with the file to open (iOS/ContentView.swift, iOS/TerminalView.swift, iOS/AgentChatView.swift,
iOS/RemoteScreenView.swift, Shared/…). Facts only; do not propose redesigns.
```

## Prompt 3 — fix (any strong model, one issue per run)

```
Repo: /Users/aryateja/Projects/lecoder-watch-ade. Read AGENTS.md rules 1 and 2. Fix exactly
this issue from docs/audit/<date>/REPORT.md: <paste the row>. Smallest diff that removes it;
no redesign; keep every existing behaviour. Build with xcodebuild (see AGENTS.md → Build and
verify), re-take the screenshot of that screen on the simulator the same way Prompt 1 did,
and put the before/after pair in docs/audit/<date>/fixed/. Commit with a message that names
the screen and the symptom. Never push.
```

## What we already know is wrong (from the device day, before any crawl)

- Chat: key row belongs to the terminal, not the chat (removed); the keyboard dismiss
  button overlapped (removed); the keyboard stuck after leaving Settings' quick-command
  field (fixed); pills were hardcoded (now the user's quick commands).
- Voice: the transcript vanished on a pause (the recognizer restarts on silence; now
  accumulates), Stop & Review showed nothing (same cause), two screens where one will do.
- Terminal: panes are unreadable at phone width and cannot be closed cleanly; two ways to
  reach the terminal from chat (one removed).
- Monitor: usage limits were below a growing event list with no way to dismiss (moved up,
  dismiss + clear added).
- Settings → connection diagnosis: one of three checks red for the Mac; which one is still
  unknown — needs the label from the screen.
