# Glaze System Instructions — Extracted Bundle

> Snapshot of every system prompt, guide, skill, and rule that powers the
> Glaze macOS app builder. Extracted verbatim from the running Glaze install.

## Layout

- `prompts/` — the 8 agent system prompts (orchestrator + 7 sub-agents)
- `guides/` — global context (`CLAUDE.md`) and the developer reference (`GLAZE-APP-GUIDE.md`)
- `skills/` — every reusable skill the orchestrator can invoke
- `rules/` — short rule files automatically appended to context
- `ALL-SYSTEM-INSTRUCTIONS.md` — single-file concatenation of everything above

## How Glaze uses these at runtime

1. The user's request enters the **Main Orchestrator** (`prompts/01-main-orchestrator.md`).
2. The orchestrator may invoke the **Context Gatherer** to read project memory + guides.
3. For implementation work it delegates to **Frontend Architect** and/or **Backend Architect**.
4. After every sub-agent finishes, the **Compliance Checker** validates the work against skill checklists.
5. On runtime errors, the **Error Investigator** reads logs and patches the bug.
6. SDK upgrades flow through the **Upgrade** agent.
7. The orchestrator + every sub-agent has the contents of `guides/CLAUDE.md` injected into context.
8. Skills are loaded **just-in-time** — only when the orchestrator hits work that needs them.

## Index

### Agent Prompts

| Agent | File | Role |
| --- | --- | --- |
| Main Orchestrator | [`prompts/01-main-orchestrator.md`](prompts/01-main-orchestrator.md) | The primary Glaze agent. Routes work, gathers context, plans, delegates to sub-agents, runs compliance checks, and validates builds. |
| Frontend Architect | [`prompts/02-frontend-architect.md`](prompts/02-frontend-architect.md) | Sub-agent that builds React/Tailwind UIs that look indistinguishable from native macOS apps. Owns renderer/ code. |
| Backend Architect | [`prompts/03-backend-architect.md`](prompts/03-backend-architect.md) | Sub-agent for Node.js services and JSON-RPC 2.0 IPC handlers in main/. |
| Compliance Checker | [`prompts/04-compliance-checker.md`](prompts/04-compliance-checker.md) | Validates sub-agent output against skill checklists and IPC contracts. |
| Error Investigator | [`prompts/05-error-investigator.md`](prompts/05-error-investigator.md) | Reads system logs, finds root causes, applies fixes for crashes/runtime errors. |
| Context Gatherer | [`prompts/06-context-gatherer.md`](prompts/06-context-gatherer.md) | Reads project memory, guides, and existing code before any implementation begins. |
| SDK Upgrade Agent | [`prompts/07-upgrade.md`](prompts/07-upgrade.md) | Runs Glaze SDK version migrations end-to-end. |
| Issue Report Agent | [`prompts/08-issue-report.md`](prompts/08-issue-report.md) | Compiles bug reports for developers from session context. |

### Guides

| File | Path | Purpose |
| --- | --- | --- |
| CLAUDE.md | [`guides/CLAUDE.md`](guides/CLAUDE.md) | Master context guide for orchestrator + sub-agents. |
| GLAZE-APP-GUIDE.md | [`guides/GLAZE-APP-GUIDE.md`](guides/GLAZE-APP-GUIDE.md) | Architecture/API reference for Glaze app development. |

### Skills

| Skill | File | Summary |
| --- | --- | --- |
| glaze-app-lifecycle | [`skills/glaze-app-lifecycle.md`](skills/glaze-app-lifecycle.md) | Patterns for quitting apps, menubar apps, and graceful shutdown |
| glaze-auto-bootstrap-migration | [`skills/glaze-auto-bootstrap-migration.md`](skills/glaze-auto-bootstrap-migration.md) | One-time migration from manual framework wiring (GlazeIPCServer, GlazeLifecycle, backendNativeBridge) to automatic bootstrap with Glaze backend APIs. |
| glaze-backend-performance | [`skills/glaze-backend-performance.md`](skills/glaze-backend-performance.md) | Use when building apps that poll system state, execute shell commands, or transfer binary/large data over IPC. Covers child_process safety, polling patterns, IPC payload optimiz... |
| glaze-browser-window-recipes | [`skills/glaze-browser-window-recipes.md`](skills/glaze-browser-window-recipes.md) | Recipes for specialized BrowserWindow setups in Glaze apps, including transparent windows, frameless custom chrome, parent and modal windows, draggable headers, hidden or reposi... |
| glaze-cli-dependencies | [`skills/glaze-cli-dependencies.md`](skills/glaze-cli-dependencies.md) | Handling external CLI tools in Glaze apps via Homebrew when npm packages are not sufficient |
| glaze-component-patterns | [`skills/glaze-component-patterns.md`](skills/glaze-component-patterns.md) | Patterns and best practices for building native macOS-style layouts using Glaze's design system components. |
| glaze-context-gather | [`skills/glaze-context-gather.md`](skills/glaze-context-gather.md) | Gather context from project memory, guides, and codebase before implementation. Use when starting new features, complex changes, or when you need to understand existing patterns... |
| glaze-core-imports | [`skills/glaze-core-imports.md`](skills/glaze-core-imports.md) | Update imports to use the @glaze/core entry points (components, hooks, utils). |
| glaze-data-storage | [`skills/glaze-data-storage.md`](skills/glaze-data-storage.md) | Patterns and best practices for persisting data in Glaze apps using the two-tier storage model. |
| glaze-dialog-body-migration | [`skills/glaze-dialog-body-migration.md`](skills/glaze-dialog-body-migration.md) | Migrate Dialog and AlertDialog components to the new padding architecture where DialogBody handles horizontal padding and scrolling instead of DialogContent. |
| glaze-drag-and-drop | [`skills/glaze-drag-and-drop.md`](skills/glaze-drag-and-drop.md) | Implement drag-and-drop workflows in Glaze apps, including dropping files from Finder into the app, dragging exported files from the app to Finder, and in-app drag/reorder inter... |
| glaze-external-api | [`skills/glaze-external-api.md`](skills/glaze-external-api.md) | Patterns and best practices for integrating external APIs in Glaze apps. |
| glaze-file-associations | [`skills/glaze-file-associations.md`](skills/glaze-file-associations.md) | Register file type associations so users can open files by double-clicking them, with the app receiving the file path. |
| glaze-icon-usage | [`skills/glaze-icon-usage.md`](skills/glaze-icon-usage.md) | Guidelines for using icons in Glaze apps. Always use solid fill colors, never semi-transparent alpha colors. |
| glaze-ipc-communication | [`skills/glaze-ipc-communication.md`](skills/glaze-ipc-communication.md) | Patterns and best practices for secure inter-process communication in Glaze apps between frontend and backend. |
| glaze-migrate-to-cli | [`skills/glaze-migrate-to-cli.md`](skills/glaze-migrate-to-cli.md) | One-time migration from legacy template structure (glaze-backend.js, scripts/, vite.config.ts, and local ESLint setup) to the glaze CLI. |
| glaze-native-components-migration | [`skills/glaze-native-components-migration.md`](skills/glaze-native-components-migration.md) | \| |
| glaze-native-permissions | [`skills/glaze-native-permissions.md`](skills/glaze-native-permissions.md) | Implement camera, microphone, and location permission flows in Glaze apps using systemPreferences APIs, capability manifests, and native/WebKit-safe UX. Use this when adding nat... |
| glaze-preload-migration | [`skills/glaze-preload-migration.md`](skills/glaze-preload-migration.md) | One-time migration from HTML-based preload (modulepreload/script tag) to runtime-injected preload via webPreferences.preload. |
| glaze-protocol-large-files | [`skills/glaze-protocol-large-files.md`](skills/glaze-protocol-large-files.md) | Use when building Glaze apps that need to load large files (MB+) in the renderer or stream file content without IPC bloat. Covers the Glaze protocol API (registerSchemesAsPrivil... |
| glaze-sdk-externalize | [`skills/glaze-sdk-externalize.md`](skills/glaze-sdk-externalize.md) | One-time migration from legacy shared components (renderer/shared/) to the externalized @glaze/core SDK. |
| glaze-window-sizing | [`skills/glaze-window-sizing.md`](skills/glaze-window-sizing.md) | Chooses window width, height, and minimum dimensions for a Glaze BrowserWindow based on the app's layout and content. Use when creating a new Glaze app, scaffolding from the tem... |

### Rules

| File | Path | Heading |
| --- | --- | --- |
| bundling.md | [`rules/bundling.md`](rules/bundling.md) | Packages That Can't Be Bundled (native modules, CJS, runtime assets) |
| common-tasks.md | [`rules/common-tasks.md`](rules/common-tasks.md) | Common Tasks → GLAZE-APP-GUIDE.md Sections |
| debugging.md | [`rules/debugging.md`](rules/debugging.md) | Debugging Runtime Errors |
| wkwebview-caveat.md | [`rules/wkwebview-caveat.md`](rules/wkwebview-caveat.md) | Known WKWebView Rendering Caveat |

## Re-extracting after a Glaze SDK upgrade

Re-run the script from inside the project:

```bash
python3 scripts/extract-glaze-system.py
```

It is idempotent — both output trees are wiped and rewritten.

