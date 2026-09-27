# Impeccable setup plan for LeSearch Mesh / LeScout

Arya asked to start using Impeccable as a working design-quality baseline for this project. Do not install during handoff-only mode; this file records the exact next steps.

## Source

```text
https://github.com/pbakaus/impeccable
https://impeccable.style
```

## Goal

Use Impeccable to audit and improve the current iPhone/watch/web terminal UI, especially the bad terminal rendering and generic AI-slop visual patterns.

## Recommended install path

From the project root:

```bash
cd /Users/aryateja/Projects/lecoder-watch
npx impeccable skills install
```

This should auto-detect the harness and write compiled skills to the correct location.

## Alternative repo-local installs

For Pi:

```bash
cp -r dist/pi/.pi /Users/aryateja/Projects/lecoder-watch/
```

For Claude Code:

```bash
cp -r dist/claude-code/.claude /Users/aryateja/Projects/lecoder-watch/
```

For Codex-style agents:

```bash
cp -r dist/agents/.agents /Users/aryateja/Projects/lecoder-watch/
```

## CLI detector usage

Use the standalone detector even before skills are wired:

```bash
cd /Users/aryateja/Projects/lecoder-watch
npx impeccable detect iOS/ Watch/ Shared/
npx impeccable detect --fast --json . > /tmp/meshwatch-impeccable.json
```

For the rmux bridge web UI:

```bash
cd /Users/aryateja/Projects/terax-ai-agentfirst
npx impeccable detect packages/rmux-bridge/public/index.html
npx impeccable detect http://127.0.0.1:7820/?session=lescout-mobile-smoke
```

## Commands after skill install

```text
/impeccable audit terminal UI
/impeccable polish iPhone session peek
/impeccable distill watch session controls
/impeccable critique rmux bridge mobile rendering
```

## What to ask Impeccable first

Focus on these concrete surfaces:

1. iPhone session detail output card.
2. iPhone quick-send and pane chips.
3. Watch session quick-look controls.
4. rmux bridge mobile terminal page.
5. Machine resource cards and per-process metrics view.

## Design issues to flag explicitly

- terminal text too small / unreadable
- raw TUI boxes shown in small mobile card
- cramped padding in output card
- unclear button labels/icons
- generic blue/white SwiftUI defaults where hierarchy matters
- missing empty/loading/error states
- small touch targets
- no clear separation between browse and input mode
- no semantic summary above raw output

## Important caution

Impeccable should guide visual quality; it should not expand scope into redesigning the architecture. The next agent should keep changes surgical and test on simulator/device.
