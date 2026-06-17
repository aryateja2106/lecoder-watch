# LeScout / MeshWatch product context — 2026-06-05

This document captures Arya's feedback after testing the current iPhone/watch terminal UI. It is a handoff for the next agent. Do not treat the current UI as successful just because data flows; the human experience is still below usable.

## One-sentence product goal

LeScout should become a mobile/watch mission-control surface for persistent terminal coding-agent sessions across Arya's Macs, VMs, containers, and remote hosts.

## Why this matters

Arya's bottleneck is his own workflow. He wants to build apps faster, use hackathon/event resources quickly, connect API keys/VMs/containers/agents safely, and eventually monetize this workflow. The app should make his real machine state understandable and actionable from phone/watch.

## Current state

Working pieces exist:

- iPhone app shows machines, sessions, usage metrics, and basic stats.
- Watch app shows machines/sessions and can send quick controls.
- `meshd` serves machine stats, session lists, output capture, sends, panes, and usage data.
- `rmux-bridge` streams terminal sessions through a web/xterm surface.
- Simulator builds pass for iOS and watchOS.

But Arya's tested feedback is clear:

- The phone terminal view is not usable for real work.
- Rendering is bad; output is hard to view and understand.
- Basic `ls` / navigation feels hard, so TUI coding agents are impossible.
- Current session peek is a start, but the output block is visually wrong.
- User cannot understand what is happening in the agent at a glance.
- Keyboard/input behavior must be intentional, not triggered by random taps.

## Target user workflow

A power user with terminal agents should be able to:

1. Pick a machine or project.
2. See per-project/per-session CPU and memory cost.
3. Understand which agents/terminals are running.
4. Navigate folders with basic commands (`cd`, `ls`, autocomplete-like affordances).
5. Start agent commands from presets/shortcuts.
6. Peek high-level agent state without opening full terminal.
7. Use voice minimally for command/reply input.
8. Approve risky operations from phone/watch.
9. Keep persistent sessions across device disconnects.
10. Cleanly stop stale experiments/processes.

## Product principles

- Phone is the primary operator UI.
- Watch is quick-look, notification, approval, and simple-control UI.
- Full terminal emulation on watch is a trap.
- Terminal must be readable before it is powerful.
- Session state should be summarized semantically, not only as terminal pixels.
- Input should be explicit: tap Reply/Type/Command first.
- The app should reveal resource cost per project/session/agent.
- Secure orchestration matters, but only after the UI loop is understandable.

## Comparison target from Arya's screenshot

The Superset-like resource panel is the north-star for resource visibility:

- top-level total CPU / RAM / RAM share
- app/project group rows
- nested process/session rows
- per-row CPU and memory
- clear grouping by workspace/project/session

For LeScout, translate that into:

- Machine → Project → Session → Pane/Process
- CPU %, memory MB/GB per level
- stale/idle/running/waiting status
- ability to stop or inspect from each row

## Immediate UX problems to solve next

### P0 — usability blockers

1. Terminal output is too raw and visually broken.
2. Session peek should show clean agent messages/status, not mangled TUI boxes.
3. Basic `ls`, `pwd`, `cd`, and command-send operations must be obvious.
4. Quick-send options must be editable/configurable.
5. Active pane count and pane switching need to be visible.
6. Stale processes from experiments need a safe cleanup view.

### P1 — product depth

1. Process metrics per project/session.
2. Agent status detection: thinking, waiting, error, done.
3. Notifications for waiting-for-input and completed tasks.
4. Security checks/actions surfaced from the app.
5. Container/VM visibility and orchestration.
6. Voice-assisted command entry with preview/confirmation.

## What not to do next

- Do not add more daemons or LaunchAgents before UI is usable.
- Do not claim terminal usability from simulator screenshots alone.
- Do not optimize for watch terminal rendering.
- Do not bury the user in old Tommy/PAI prompt context.
- Do not expand MCP/tooling sprawl until the core session loop works.

## Recommended next slice

A small, useful slice would be:

> Replace the terminal preview block with a semantic session summary card and a clean output-tail card, then add editable quick commands.

Acceptance criteria:

- iPhone session detail loads without opening keyboard.
- The top of the screen shows status: machine, session, panes, running/waiting.
- Output tail is readable, not a raw mangled TUI screenshot.
- Quick-send buttons are visible and editable from Settings or session screen.
- `ls`, `pwd`, `git status`, `continue`, `Ctrl-C`, `Enter` are one tap.
- Full terminal is still available behind an explicit Open Terminal button.
