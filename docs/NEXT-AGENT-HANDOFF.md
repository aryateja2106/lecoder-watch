# Next agent handoff — LeSearch Mesh / LeScout

## Prime directive

Do not assume the current mobile terminal UI is usable. Arya tested it and said it is not. The data path works; the human workflow does not yet work.

## Current repository

```text
/Users/aryateja/Projects/lecoder-watch
```

Related bridge repo:

```text
/Users/aryateja/Projects/terax-ai-agentfirst/packages/rmux-bridge
```

## Current uncommitted changes

At handoff time, this repo had modified:

```text
Watch/WatchViews.swift
iOS/TerminalView.swift
```

Related bridge repo had modified:

```text
packages/rmux-bridge/public/index.html
```

Those changes were an initial attempt at read-first session peeking and explicit Type/Browse mode. They build, but Arya's final feedback says the result is still not usable enough.

## Verified builds

These passed after the current modifications:

```bash
cd /Users/aryateja/Projects/lecoder-watch
xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build
xcodebuild -project MeshWatch.xcodeproj -scheme 'MeshWatch Watch App' -destination 'generic/platform=watchOS Simulator' -derivedDataPath build/DerivedData build
```

## Running services / sessions observed

Local rmux session started for smoke testing:

```text
lescout-mobile-smoke
```

Local rmux bridge:

```text
http://127.0.0.1:7820/?session=lescout-mobile-smoke
```

Dataflow bridge:

```text
http://100.80.10.95:7820/?session=dataflow-spine
```

## Arya's latest feedback, compressed

- The terminal view is visually bad and not usable.
- Basic commands like `ls` are hard to run/view.
- Opening the terminal ruins the experience even if the list/status screen looks okay.
- He wants a clean minimal UI before adding persistence/connectivity/security layers.
- He wants process/resource metrics by project/session like the Superset screenshot.
- He wants quick-send options to be editable.
- He wants active pane count and pane visibility.
- He wants stale experimental processes cleaned later, but not as this handoff task.
- He wants to install/use Impeccable for design-quality feedback.
- He is blocked on running the app on a physical Apple Watch due to Xcode/developer-mode issues.

## Important context docs now available

Read these first:

```text
docs/PRODUCT-CONTEXT-2026-06-05.md
docs/XCODE-WATCH-DEVICE-RUNBOOK.md
docs/IMPECCABLE-SETUP.md
HANDOFF.md
```

Prior scout docs live outside this repo:

```text
/Users/aryateja/Personal-Software-Factory/docs/overnight-agents/watch-minimal-ui-scout.md
/Users/aryateja/Personal-Software-Factory/docs/overnight-agents/iphone-terminal-ui-scout.md
/Users/aryateja/Personal-Software-Factory/docs/overnight-agents/session-peek-backend-scout.md
```

## Recommended next task

Do not start with more backend. Start with design clarification and small UI correction:

1. Install or run Impeccable detector.
2. Audit `iOS/TerminalView.swift` and `Watch/WatchViews.swift`.
3. Replace raw TUI terminal preview with a semantic summary card.
4. Keep raw terminal behind explicit Open Terminal.
5. Add editable quick-send presets.
6. Add pane count and pane list clarity.
7. Add process/project resource breakdown as a new read-only section.
8. Verify on simulator screenshots and, when Xcode device issue is solved, physical watch.

## Product shape to preserve

Phone:

- primary control surface
- machine list
- resource drilldown
- session list
- session summary
- editable quick commands
- full terminal only by explicit action

Watch:

- quick glance
- notification/approval
- small command presets
- reply/dictation only on explicit tap
- no full terminal emulator ambition

## Do not do

- Do not add new LaunchAgents.
- Do not expand MCP broker work.
- Do not add Capsem/forkd/model-training features.
- Do not claim “usable” without Arya testing it.
- Do not depend on Xcode Cloud remote repo setup for local device testing.
- Do not regenerate Xcode project without preserving signing settings.

## Physical watch blocker

See `docs/XCODE-WATCH-DEVICE-RUNBOOK.md`. Likely issues:

- pending watchOS update / beta mismatch
- Xcode device support mismatch
- Developer Mode trust loop
- XcodeGen resetting signing because `DEVELOPMENT_TEAM` is empty in `project.yml`

## Impeccable task

See `docs/IMPECCABLE-SETUP.md`. Recommended first command later:

```bash
cd /Users/aryateja/Projects/lecoder-watch
npx impeccable detect iOS/ Watch/ Shared/
```

Then use skill commands if installed:

```text
/impeccable audit terminal UI
/impeccable polish iPhone session peek
/impeccable distill watch session controls
```
