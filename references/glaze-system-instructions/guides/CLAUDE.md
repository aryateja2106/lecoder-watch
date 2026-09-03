# CLAUDE.md

This file provides context about Glaze app architecture for all agents (main orchestrator and sub-agents).

## Working Environment

- Node.js and npm available
- Apps follow macOS Human Interface Guidelines
- **Analysis Exclusions:** `node_modules`, `build/**`, `**/*.map`, `package-lock.json`
- **NEVER use Bash for file search/read.** Use `Grep` (not `grep`/`rg`), `Glob` (not `find`/`ls`), `Read` (not `cat`/`head`/`sed`). Bash `grep` wastes tokens and bypasses tool optimizations.
- **NEVER run broad `find` commands** (e.g., `find /`, `find ~`). Triggers macOS permission popups. Stay within `.glaze-sources/`, log dir, or `<runtime_context>` paths.
- **CRITICAL:** Always use real data from APIs or user input. NEVER ship mock/placeholder data in implementations.
- Glaze SDK mirrors most of Electron's API surface. Use Electron knowledge as a starting point, but verify that each API, option, and behavior is implemented here before using it.
- **Parallel tool calls:** ALWAYS batch independent operations in a single turn. Read multiple files, search multiple patterns, spawn independent sub-agents — all in one turn. Only sequence when one call's output is needed as input for the next.
- **Surgical edits only.** Every modified line must trace to the user's request. Don't clean up surrounding code, add comments to unchanged code, or refactor working systems.

## Directory Structure

<critical>
Source code in `.glaze-sources/` (sibling to `.glaze/`):

```
.glaze/            ← Runtime output ONLY (never edit, never npm install)
.glaze-sources/    ← ALL SOURCE CODE (edit here, npm install here)
├── main/          ← Backend
├── renderer/      ← Frontend
├── package.json   ← Add deps here
└── .glaze_memory/ ← PROJECT-CONTEXT.md
```

**Rules:**

- ALWAYS `npm install --include=dev` from `.glaze-sources/` — NODE_ENV=production may prune devDeps
- NEVER edit/create in `.glaze/` — it's build output. Fix build config (`glaze.config.ts`) instead.
- NEVER run `glaze build` — auto-builds on file changes (hot reload)
- `@glaze/core` resolved via tsconfig paths + ESM hooks — NEVER `npm install` it
- `glaze` CLI on PATH automatically — never install from node_modules
- **Glaze-managed `.npmrc` is OFF-LIMITS.** A supply-chain protection `.npmrc` (enforcing `min-release-age`, `allow-git=none`) lives in Glaze's Application Support directory (`~/Library/Application Support/app.glaze.macos.main*/.npmrc`) and is passed to every `npm install` / `npm ci` via `NPM_CONFIG_USERCONFIG`. NEVER read, edit, delete, move, copy, overwrite, `chmod`, symlink, or otherwise touch that file or its parent directory. NEVER unset, override, or print `NPM_CONFIG_USERCONFIG`. NEVER create a project-level `.npmrc` in `.glaze-sources/` (or anywhere else in the app) that sets any of the forbidden keys below. If an `npm install` fails because a dependency version is too new (blocked by `min-release-age`), pin `package.json` to an older version instead of weakening the policy.
- **Sanitize existing `.npmrc` files.** Before running `npm install` / `npm ci`, check whether a `.npmrc` exists in `.glaze-sources/`. If it contains any of the following forbidden keys, remove those lines (delete the file entirely if nothing remains): `min-release-age`, `before`, `allow-git`, `registry`, `ignore-scripts`. These keys conflict with or weaken the Glaze-managed supply-chain policy. Other keys (e.g. `legacy-peer-deps`, `save-exact`) are fine to keep.

**Forbidden imports (runtime breakage):**

- `backendNativeBridge`, `@glaze/core/backend/internal`, `GlazeIPCServer`, `GlazeLifecycle`, `registerNativeApiHandlers`, `wireProtocolHandlers` — use public `@glaze/core/backend` exports instead (`dialog`, `shell`, `clipboard`, `Notification`, `Menu`, `Tray`, etc.)
- Never `eslint-disable` for `no-restricted-imports`. If API not exported (e.g. `powerMonitor`), tell user it's unavailable. </critical>

## Architecture Overview

```
┌─────────────────┐  Native bridge + IPC  ┌─────────────────┐
│  Frontend       │◄───────────────────►  │  Backend        │
│  (React/Vite)   │     JSON-RPC 2.0      │  (Node.js)      │
│  .glaze-sources/ │                       │  .glaze-sources/ │
│  renderer/      │                       │  main/          │
└─────────────────┘                       └─────────────────┘
        │                                         │
        ▼                                         ▼
   WebView (macOS)                         Swift Host APIs
```

## Key Paths

All paths below are inside `.glaze-sources/`:

| Location                      | Purpose                 | Modify?   |
| ----------------------------- | ----------------------- | --------- |
| `main/handlers/`              | Backend IPC handlers    | Often     |
| `main/services/`              | Backend business logic  | Often     |
| `renderer/main/home-view.tsx` | Main UI view            | Often     |
| `renderer/main/router.tsx`    | Route definitions       | Sometimes |
| `renderer/components/`        | App-specific components | Often     |
| `@glaze/core`                 | Framework SDK           | **Never** |
| `package.json`                | Dependencies & scripts  | Sometimes |

## Path Aliases

```typescript
import { ... } from "@glaze/core/backend";     // Backend framework
import { ... } from "@glaze/core/components";   // UI components
import { ... } from "@glaze/core/hooks";        // React hooks
import { ... } from "@glaze/core/utils";        // Utilities (cn, etc.)
import { ... } from "@glaze/core/ipc";          // Frontend IPC types
import { ... } from "@main/...";               // Backend modules
```

## Protected Files

<protected_files> **Never modify these paths:**

- `@glaze/core/**` - Framework SDK (auto-updated by host app)
- `../../../sdk/current/@glaze/core/**` - Framework internals (shared SDK)
- `build/**` - Auto-generated

**To customize shared components:** Create wrappers in `renderer/components/` </protected_files>

## Styling (Tailwind CSS v4 ONLY)

- **ALWAYS** use Tailwind utility classes for styling
- **NEVER** write plain CSS files or create separate `.css` files for component styles
- Apply styles directly in JSX via the `className` prop
- Use built-in Tailwind values (spacing, colors, etc.)

## IPC Security Model

<security>
- Only `renderer/preload.ts` imports `ipcRenderer`
- Renderer code uses `window.glazeAPI` (exposed via contextBridge)
- Sensitive APIs (clipboard, shell.openExternal) disabled by default
- Enable in `preload.ts` only when needed
</security>

## Development Environment

| Service  | Port  | Notes                                   |
| -------- | ----- | --------------------------------------- |
| Backend  | stdio | Communicates via stdin/stdout with host |
| Frontend | 7623  | Vite dev server                         |

## Skills

Invoke skills BEFORE writing code when touching: UI components, IPC handlers, data storage, external APIs, native permissions, window management, CLI tools, file handling, or performance-sensitive code. Skip for: documentation, color/spacing tweaks, comment changes, single-line fixes.

## Common Tasks → GLAZE-APP-GUIDE.md Sections

| Task                   | See Section                                             |
| ---------------------- | ------------------------------------------------------- |
| Add IPC handler        | "Adding New Backend Handlers"                           |
| Create window          | "Window Management (BrowserWindow)"                     |
| Add route              | "Key Files" → router.tsx                                |
| Use native dialogs     | "Native macOS Integration"                              |
| Add notifications      | "System Notifications (Notification API)"               |
| Add global shortcut    | "Global Shortcuts"                                      |
| Add system tray        | "System Tray"                                           |
| Customize components   | "renderer/shared/ Components"                           |
| Add setting/preference | Settings window (`renderer/settings/settings-view.tsx`) |

**Settings Convention:** When the user asks to add a "setting" or "preference", always place it in the app's Settings window (`renderer/settings/settings-view.tsx`), not inline in the main UI. The template includes a dedicated Settings window accessible via Cmd+, (Preferences menu item). Only put settings inline in the main view if the user explicitly requests it.

**Cross-window sync:** The Settings window and main window are separate BrowserWindow instances with separate React trees. Saving a setting in the backend does NOT automatically update the main window. You MUST broadcast changes so the main window reacts in real-time:

- **Backend handler:** after saving, call `ipcMain.broadcast("settings:foo-changed", { value })` to push the change to all windows
- **Main window:** listen with `window.glazeAPI.glaze.ipc.onNotification("settings:foo-changed", callback)` and update the React Query cache via `queryClient.setQueryData()`
- Without this, settings only take effect after restarting the app or closing the Settings window.

## Debugging Runtime Errors

**CRITICAL: When the user reports runtime errors, crashes, or mentions "logs", ALWAYS read the system log file first.**

**Log Location:** Use the `Latest Log File` if provided and not marked `(not found yet)` in the runtime context. Otherwise use `Log Directory`.

**Log File Structure:**

- Filename pattern: `glaze-{timestamp}.log` (e.g., `glaze-2025-01-15 14.30.45+0000.log`)
- New file per app launch - most recent file = current session
- Files sorted by modification time

**IMPORTANT: Log files can be large.** Never read the entire file. Instead:

1. **Find errors:** Use Grep tool with pattern `error|exception|failed` on the log file path
2. **Get context:** Use Read tool with `offset` parameter near the error line number

**Tool Priority:** Always use native tools (Read, Grep, Glob) first. Only use bash commands (grep, cat, find) as a last resort.

**Log Prefixes:**

- `[Node]` = Backend logs (Node.js server, IPC handlers, database)
- `[Frontend]` = Frontend logs (React components, UI, browser errors)

**Hot-Reload Messages (IGNORE - NOT errors):**

- `Backend exited with code null (signal SIGKILL)`
- `Exiting with code 1000 to trigger hot reload restart`

**Hot Reload Log File Behavior:**

- Hot reloads usually append to the current log file.
- Do not assume a new log file is created for each hot reload; only app relaunches create a new file.

**Debugging Steps:**

1. Use `Latest Log File` from runtime context when available
2. Otherwise resolve newest file using the Glob tool
3. Search for errors
4. Filter by source if needed
5. Find stack trace with file/line number
6. Fix root cause, not symptoms
7. Explain the fix to the user

## Live Inspection Tools

Treat the live inspection tools as a post-build runtime debugging aid, not as a first-step exploration tool.

- Never use live inspection before a successful build or before the app is already running.
- Always call `LiveAppInspectionStatus` first.
- If status says the app is not built, not current, not running, or not ready, stop and fix that first instead of trying DOM or screenshot tools.
- Prefer `LiveAppSnapshotDOM` and `LiveAppInspectElement` over screenshots.
- Use `LiveAppCapturePreview` mainly for visual investigations or regressions because it is more expensive.
- Do not use live inspection as a substitute for reading logs, checking build output, or verifying compiler/runtime errors.

## Known WKWebView Rendering Caveat

When animating container `height` inside a glass surface (`bg-glass`), avoid `backdrop-filter` on nested controls (especially `Button` `variant="filled"` which uses `backdrop-blur-xs` by default in `@glaze/core`).

- Symptom: footer controls can appear duplicated/ghosted for a frame during transitions.
- Root cause: WebKit compositor artifact from `backdrop-filter` + clipping + animated height.
- Recommended mitigation:
  - Prefer `backdrop-blur-none` on footer buttons within animated glass composers.
  - Use strong clipping/paint containment on the shell (`overflow-hidden`, `isolate`, `contain: paint`).
  - Keep footer slot stable (fixed/min height) while content height animates.

## Packages That Can't Be Bundled (native modules, CJS, runtime assets)

Some npm packages can't be bundled by esbuild — they have native `.node` binaries, use CommonJS `require()` that esbuild can't analyze, or load files from disk at runtime. These need special handling via `glaze.config.ts` build configuration.

### Known packages that need plugins

| Package | Plugin | Notes |
| --- | --- | --- |
| `sharp` | `externalizePackage` | Has platform-specific binaries in scoped `@img/*` deps |
| `jsdom` | `externalizePackage` | Uses `__dirname` to load CSS/HTML assets at runtime |
| `node-pty` | `externalizePackage` | Loads runtime helper files from its package directory |
| `better-sqlite3-multiple-ciphers` | `copyNativeBindings` | Single `.node` file — but prefer `node:sqlite` instead unless you need encryption support |

**General rule:** After `npm install`, if a package ships native `.node` files or non-JS runtime helpers it expects to load from its own directory (executables, assets, templates), it needs a plugin.

### Recognizing bundling errors

| Error message | Cause | Fix |
| --- | --- | --- |
| `Cannot find module '…*.node'` | Native binary not copied to build output | `copyNativeBindings` or `externalizePackage` |
| `Dynamic require of "X" is not supported` | CJS package in ESM bundle | `externalizePackage` |
| `Module did not self-register` | Wrong architecture binary | Reinstall: `npm rebuild <pkg>` |
| Runtime crash with `__dirname` / file-not-found | Package loads assets from disk | `externalizePackage` |

### Which plugin to use

1. Package has a **single `.node` binary** and JS bundles fine → `copyNativeBindings("pkg", "binding.node")`
2. Package loads **files from disk at runtime**, depends on helper executables next to its package files, or has complex deps → `externalizePackage("pkg")`

### Quick reference

```typescript
// glaze.config.ts
import { defineConfig, copyNativeBindings, externalizePackage } from "@glaze/core/build";

const sharp = externalizePackage("sharp");

export default defineConfig({
  build: {
    external: [...sharp.externals],
    plugins: [sharp.plugin, copyNativeBindings("better-sqlite3-multiple-ciphers", "better_sqlite3.node")],
  },
});
```

See GLAZE-APP-GUIDE.md "Packages That Can't Be Bundled" for full code examples.
