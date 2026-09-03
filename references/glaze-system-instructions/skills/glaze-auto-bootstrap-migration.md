---
name: glaze-auto-bootstrap-migration
description: One-time migration from manual framework wiring (GlazeIPCServer, GlazeLifecycle, backendNativeBridge) to automatic bootstrap with Glaze backend APIs.
---

# Glaze Auto-Bootstrap Migration

This is a **one-time migration** for apps created before the auto-bootstrap feature. The glaze CLI now automatically wires all framework internals (IPC server, native bridge, lifecycle, signal handlers) before the app's `main/index.ts` runs. App code no longer needs to import or wire these — only the public Glaze backend APIs are needed.

## When to Run

Run this skill when `main/index.ts` imports **any** of these symbols from `@glaze/core/backend`:

- `GlazeIPCServer`
- `GlazeLifecycle`
- `backendNativeBridge`
- `registerNativeApiHandlers`
- `wireProtocolHandlers`
- `childProcessTracker`

If none of these imports exist, the migration is already done — skip this skill.

## What Changed

The glaze CLI now injects `--import @glaze/core/backend/runtime` before running `main/index.ts`. This module:

1. Creates and starts the `GlazeIPCServer`
2. Wires `ipcMain` to the server
3. Wires `backendNativeBridge` to the server
4. Registers protocol handlers and native API handlers
5. Sets up signal handlers and parent process monitoring
6. Sets up lifecycle shutdown callbacks

**App code no longer needs to do any of this.** The `app.whenReady()` promise resolves after all wiring is complete — app code just uses `app`, `ipcMain`, `BrowserWindow`, etc. directly.

## Migration Steps

### 1. Identify framework wiring code in `main/index.ts`

Look for these patterns — they must all be **removed**:

```typescript
// These imports must be removed:
import { GlazeIPCServer, GlazeLifecycle, backendNativeBridge,
         registerNativeApiHandlers, wireProtocolHandlers } from "@glaze/core/backend";

// This wiring code must be removed:
const ipcServer = new GlazeIPCServer();
ipcMain._wireToServer(ipcServer);
backendNativeBridge.wireToServer(ipcServer);
wireProtocolHandlers(ipcServer);
registerNativeApiHandlers();
GlazeLifecycle.setupSignalHandlers();
GlazeLifecycle.setCallbacks({ onShutdown: ... });
await ipcServer.start();
GlazeLifecycle.startParentMonitoring();
```

### 2. Identify custom app logic to PRESERVE

Before removing anything, identify what the app actually does beyond framework wiring. Common custom logic that **must be kept**:

- Custom IPC handler registrations (e.g., `registerHandlers()`, `ipcMain.handle(...)`)
- Window creation logic (BrowserWindow setup, loadURL, ready-to-show)
- Application menu setup (Menu.buildFromTemplate, Menu.setApplicationMenu)
- Lifecycle event handlers (app.on("activate"), app.on("window-all-closed"), app.on("before-quit"))
- Any app-specific imports and logic (database init, file watchers, etc.)

### 3. Rewrite `main/index.ts`

Transform the entry point from manual wiring to the Glaze backend pattern. The structure should be:

```typescript
// 1. Standard library imports (fs, path, etc.) — KEEP as-is
import * as fs from "fs";
import * as path from "path";

// 2. Glaze imports — ONLY public Glaze backend APIs + logger
//    Remove: GlazeIPCServer, GlazeLifecycle, backendNativeBridge,
//            registerNativeApiHandlers, wireProtocolHandlers, childProcessTracker
import { app, BrowserWindow, ipcMain, Menu, logger } from "@glaze/core/backend";

// 3. App-specific imports — KEEP all of these
import { registerHandlers } from "./handlers/index.js";

// 4. Register IPC handlers — at module top level (server is already wired)
registerHandlers();

// 5. Window creation — KEEP existing logic as a standalone function
async function createMainWindow() {
  // ... existing window creation code, converted from class method to function ...
}

// 6. Menu setup — KEEP as-is
function setupApplicationMenu() {
  // ... existing menu code ...
}

// 7. Lifecycle events — KEEP as-is but at module level, not in a class
app.on("window-all-closed", () => {
  /* ... */
});
app.on("activate", (hasVisibleWindows) => {
  /* ... */
});
app.on("before-quit", () => {
  /* ... */
});

// 8. App ready — this replaces the entire start() method and manual IPC wiring
app.whenReady().then(() => {
  setupApplicationMenu();
  createMainWindow();
});
```

**Key transformation rules:**

- If the app uses a **class** (e.g., `class GlazeApp`), flatten it: extract methods as standalone functions, replace `this.` references with local variables.
- If the app uses a **functional/procedural** style with manual wiring, just remove the wiring code and wrap the initialization in `app.whenReady().then(...)`.
- `ipcMain.handle(...)` calls can stay at the top level — `ipcMain` is wired before `main/index.ts` runs.
- `app.on("before-quit", ...)` replaces `GlazeLifecycle.setCallbacks({ onShutdown: ... })` for app-level cleanup. Do **not** add IPC server stop logic — the runtime handles that.
- Remove the `ipcServer` variable entirely — app code never touches it directly.
- Remove any `export default glazeApp` or similar class instance export.

### 4. Check `main/handlers/` for framework imports

Search all files in `main/handlers/` for imports of framework internals:

```
GlazeIPCServer, GlazeLifecycle, childProcessTracker,
backendNativeBridge, registerNativeApiHandlers, wireProtocolHandlers
```

If any handler file imports `GlazeIPCServer` as a **type** (e.g., for a function parameter), that usage pattern needs to be reworked:

- Handler functions should **not** accept an IPC server instance. Use `ipcMain.handle(...)` directly.
- For broadcasting events to renderers, use `ipcMain.broadcast(channel, data)` instead of `ipcServer.broadcast(...)`.
- For streaming handlers, use `ipcMain.handleStream(channel, handler)` instead of `ipcServer.handleStream(...)`.
- Remove any `setXxxIPCServer(server)` setter functions — they're no longer needed since `ipcMain` is a globally available singleton.

### 5. Remove stale `glaze.config.ts`

If the app has a `glaze.config.ts` that is empty or only contains obsolete flags, delete it. The CLI handles all bootstrap configuration automatically. Keep `glaze.config.ts` only if it has other config (build options, vite overrides).

### 6. Build and verify

```bash
glaze build
```

Fix any errors and rebuild until clean. Then run the app and verify:

- IPC communication works (handlers respond)
- Windows open correctly
- Menu items function
- App lifecycle events fire (activate, before-quit)

## Important Rules

- Do **not** import `GlazeIPCServer`, `GlazeLifecycle`, `backendNativeBridge`, `registerNativeApiHandlers`, `wireProtocolHandlers`, or `childProcessTracker` from any import path. These are framework internals handled by the runtime.
- Do **not** add `@glaze/core/backend/internal` imports. That entrypoint is for the main Glaze host app only, not for generated apps.
- Do **not** manually create or start an IPC server. The runtime does this automatically.
- Do **not** call `GlazeLifecycle.setupSignalHandlers()` or `GlazeLifecycle.startParentMonitoring()`. The runtime handles this.
- `app.whenReady()` resolves after all framework wiring is complete. Any code that depends on the IPC server being ready should go inside the `.then(...)` callback or after an `await app.whenReady()`.
