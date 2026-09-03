# Glaze App - Structure Guide

<ai_reading_guide>

## 🤖 AI Agent Reading Guide

### Always Read First (Essential)

- **Critical Rules** - Protected paths, security model
- **Decision Trees** - Where code should go, which API to use
- **Quick Reference** - Import paths, common patterns

### Read When Needed (Task-Specific)

| If your task involves...  | Read this section                    |
| ------------------------- | ------------------------------------ |
| Creating/managing windows | Window Management                    |
| Backend IPC handlers      | Backend, Adding New Backend Handlers |
| Keyboard shortcuts        | Global Shortcuts                     |
| System notifications      | System Notifications                 |
| Menu bar                  | System Tray                          |
| Images, icons, fonts      | Static Assets                        |

**Search tip:** Use Ctrl+F with keywords: `BrowserWindow`, `ipcMain.handle`, `window.glazeAPI`, `NEVER` </ai_reading_guide>

<table_of_contents>

## Table of Contents

| Section                                                        | Priority       | Description                   |
| -------------------------------------------------------------- | -------------- | ----------------------------- |
| [Critical Rules](#️-critical-rules)                             | 🔴 Always      | Protected paths, security     |
| [Decision Trees](#decision-trees)                              | 🔴 Always      | Where code goes, which API    |
| [Quick Reference](#-quick-reference)                           | 🔴 Always      | Import paths, patterns        |
| [Overview](#overview)                                          | 🟡 Often       | Architecture diagram          |
| [Backend](#-backend-main)                                      | 🟡 Often       | Node.js handlers, services    |
| [Frontend](#-frontend-renderer)                                | 🟡 Often       | React components, routing     |
| [Window Management](#window-management-browserwindow)          | 🟢 When needed | BrowserWindow API             |
| [Global Shortcuts](#global-shortcuts-system-wide-hotkeys)      | 🟢 When needed | System-wide hotkeys           |
| [System Notifications](#system-notifications-notification-api) | 🟢 When needed | Native notifications API      |
| [System Tray](#system-tray-menu-bar)                           | 🟢 When needed | Menu bar integration          |
| [Configuration](#️-configuration)                               | ⚪ Rarely      | package.json, glaze.config    |
| [Bundling & Publishing](#-bundling--publishing)                | 🟢 When needed | Native modules, build output  |
| [Static Assets](#️-static-assets-images-media-fonts)            | 🟢 When needed | Images, fonts, media files    |
| [File Modification Guide](#️-file-modification-guide)           | ⚪ Rarely      | What to modify                |
| [SDK Updates](#-sdk-updates)                                   | ⚪ Rarely      | Version upgrades via /upgrade |

</table_of_contents>

<critical_warnings>

## ⚠️ Critical Rules

**NEVER modify these paths:**

- `../.glaze/build/**` - Auto-generated build output
- `@glaze/core` package - Framework code (auto-updated when Glaze runs)

**To customize shared components:** Create wrappers in `renderer/components/`

**Security:** Renderer code must use `window.glazeAPI`, never import `ipcRenderer` directly.

**Forbidden imports — NEVER use these, and NEVER add `eslint-disable` to bypass the lint rule:**

- `backendNativeBridge` — This is a framework internal. It is not a public API. Importing it (from `@glaze/core/backend` or `@glaze/core/backend/internal`) will break your app because it creates a duplicate singleton that is not wired to the IPC server. Use the public APIs instead: `dialog`, `shell`, `clipboard`, `systemPreferences`, `globalShortcut`, `nativeTheme`, `screen`, `safeStorage`, `Notification`, `Menu`, `Tray`.
- `@glaze/core/backend/internal` — This entire entrypoint is reserved for the Glaze host app. The build will fail if you import from it.
- `GlazeIPCServer`, `GlazeLifecycle`, `registerNativeApiHandlers`, `wireProtocolHandlers` — These are handled automatically by the runtime. Do not import or call them.

If a feature (e.g. `powerMonitor`) has no public API in `@glaze/core/backend`, it means the API is **not yet implemented** in the framework. Tell the user it is not available yet. Do not attempt workarounds via `backendNativeBridge`. </critical_warnings>

<decision_trees>

## Decision Trees

### Where Should This Code Go?

```
Does it need file system access, native OS features, or system APIs?
├─ Yes → Backend (main/handlers/ + main/services/)
└─ No → Does it need to persist data?
    ├─ Yes → What kind of data?
    │   ├─ UI state (panel sizes, tabs, filters) → localStorage (frontend)
    │   └─ App data (settings, user content) → JSON files in Application Support (backend)
    └─ No → Frontend only (renderer/)
```

**⚠️ Data storage location:** App data must go in `~/Library/Application Support/<BUNDLE_ID>/` via `app.getPath("userData")`. NEVER store in the repository or use `process.cwd()`.

### Which IPC API Should I Use?

```
Is it a native macOS feature (dialog, clipboard, shell, notifications)?
├─ Yes → Use window.glazeAPI in frontend
│   └─ Is it sensitive (clipboard, openExternal, openPath)?
│       ├─ Yes → Enable in preload.ts first
│       └─ No → Use directly (dialog.*, shell.beep)
└─ No → Is it custom business logic?
    ├─ Yes → Create backend handler with ipcMain.handle()
    └─ No → Keep in frontend (React state, UI logic)
```

</decision_trees>

---

## Overview

Desktop app with a Node.js backend and React frontend communicating via IPC.

```
glaze-app/
├── main/                # 🖥️ BACKEND - Node.js process
│   ├── index.ts         # App initialization & window creation (modify this)
│   ├── handlers/        # IPC request handlers
│   └── windows/         # Window creation helpers & path resolution
├── renderer/            # 🎨 FRONTEND - React in WebView
│   ├── main/            # Main window React app
│   ├── settings/        # Settings window React app
│   ├── preload.ts       # Context bridge (exposes window.glazeAPI)
│   └── styles.css       # Tailwind styles & @source directives
├── main-window.html     # Main window HTML entry point
├── settings-window.html # Settings window HTML entry point
├── glaze.ts             # CLI resolver (npm script wrapper)
├── package.json         # App configuration & dependencies
└── glaze.config.ts      # Optional build customization (create when needed)
```

---

## 🖥️ BACKEND (main/)

**Purpose**: Node.js process handling business logic, file operations, and IPC communication.

### Directory Structure

```
main/
├── index.ts           # App initialization & window creation (modify this)
├── handlers/          # IPC request handlers
│   ├── index.ts       # Handler registration (modify this)
│   └── app.ts         # Handler implementations (modify this)
└── windows/           # Window creation helpers
    ├── window-paths.ts    # URL/path resolution for dev & production
    └── settings-window.ts # Settings window creation & focus logic
```

### Window Management (BrowserWindow)

Use `BrowserWindow` for creating and managing windows:

```typescript
// main/index.ts
import { app, BrowserWindow, logger } from "@glaze/core/backend";
import { getPreloadPath, getWindowUrl } from "./windows/window-paths.js";

let mainWindow: BrowserWindow | null = null;

async function createMainWindow() {
  if (mainWindow && !mainWindow.isDestroyed()) return;

  mainWindow = new BrowserWindow({
    windowKey: "main",
    width: 1000,
    height: 700,
    minWidth: 400,
    minHeight: 300,
    title: "My App",
    show: false,
    webPreferences: {
      preload: getPreloadPath(),
    },
  });

  mainWindow.once("ready-to-show", () => {
    mainWindow?.show();
  });

  const url = await getWindowUrl("main-window.html");
  await mainWindow.loadURL(url);
}

// Handle app lifecycle
app.on("activate", (hasVisibleWindows) => {
  if (!hasVisibleWindows) {
    createMainWindow();
  }
});

app.whenReady().then(() => {
  createMainWindow();
});
```

**BrowserWindow API** common methods:

- `show()`, `showInactive()`, `hide()`, `close()`, `minimize()`, `maximize()`, `focus()`
- `setSize()`, `getSize()`, `setPosition()`, `getPosition()`, `center()`
- `setTitle()`, `setFullScreen()`, `setAlwaysOnTop()`, `setAnimationBehavior()`, `setVibrancy()`

Use `setVibrancy()` for macOS-native NSVisualEffectView materials like `"sidebar"` or `"hud"`.

**Events:** `'ready-to-show'`, `'show'`, `'hide'`, `'close'`, `'focus'`, `'blur'`, `'minimize'`, `'restore'`

### Creating Additional Windows

The template’s build layout introduces a couple of easy-to-miss path quirks. Follow this checklist whenever you add another window:

1. **HTML entry files live at the repo root.** Place `settings-window.html`, `about-window.html`, etc. next to `main-window.html`. These files compile directly into `build/`, so keeping them at the root avoids path juggling.
2. **Renderer entry points go in `renderer/<window>/`.** Create a dedicated folder (e.g., `renderer/settings/index.tsx`) and always import the local stylesheet:
   ```typescript
   import "../styles.css";
   ```
   SDK component styles are injected at runtime by the native shell. For Tailwind token generation, keep `@import "@glaze/core/components.tailwind.css"` in `renderer/styles.css` and do not import `@glaze/core/components.css` directly.
3. **Resolve HTML paths with `main/windows/window-paths.ts`.** Backend modules transpile into `build/main/**`, so `path.join(__dirname, "..", "..", ...)` differs per folder depth. Use the helper’s `getWindowUrl('settings-window.html')` (for a ready-to-load URL) or `resolveWindowHtml('settings-window.html')` (for just the path) instead of hand-crafted `..` sequences.
4. **Vite must know about each `*-window.html`.** The template now auto-discovers them, but if you customize the build make sure every HTML file is listed in `rollupOptions.input`.
5. **Register a backend helper and optional IPC.** Add your own handler (e.g., `ipcMain.handle('window:openSettings')`) that calls `openSettingsWindow()` and pair it with a renderer entry under `renderer/settings/`. This keeps creation/focus logic in one place.

> 📌 **Example recipe (add these yourself)**
>
> ```typescript
> // main/windows/settings-window.ts
> import { BrowserWindow } from "@glaze/core/backend";
> import { getWindowUrl } from "./window-paths.js";
>
> let win: BrowserWindow | null = null;
> export async function openSettingsWindow() {
>   if (win && !win.isDestroyed()) {
>     win.show();
>     return;
>   }
>   win = new BrowserWindow({
>     windowKey: "settings",
>     width: 520,
>     height: 520,
>     show: false,
>   });
>   await win.loadURL(await getWindowUrl("settings-window.html"));
>   win.show();
> }
> ```
>
> Pair the handler with a button (or menu item) that calls `ipcRenderer.invoke('window:openSettings')`, and create a matching `settings-window.html` + `renderer/settings/index.tsx`.
>
> For renderer-initiated closes, call `win.close()` from the backend or route through IPC / `BrowserWindow.close(...)`. Do not rely on DOM `window.close()` for BrowserWindow content; WKWebView keeps browser-style restrictions there.

Menubar-only apps that temporarily show a dock icon for Settings should toggle the dock from the backend, not the renderer:

```typescript
import { app } from "@glaze/core/backend";

async function openSettingsWindow() {
  await app.dock.show();
  const win = ensureSettingsWindow();
  win.once("closed", async () => {
    await app.dock.hide();
  });
  win.show();
}
```

That keeps dock activation policy changes and native window close handling on the same side of the boundary, so `Cmd+W` continues to close the settings window normally.

Following this checklist ensures every new window works in both dev-server and packaged builds without manual tweaks.

### Key Files

**`main/index.ts`** - Entry point with app.whenReady() (modify to customize windows, menus, lifecycle)

- Creates main window using BrowserWindow API
- Sets up application menu (Settings, etc.)
- Configures app lifecycle handlers (activate, before-quit, window-all-closed)
- Registers IPC handlers

**`main/handlers/index.ts`** - Register IPC handlers (modify often)

```typescript
import { ipcMain } from "@glaze/core/backend";

export function registerHandlers(): void {
  ipcMain.handle("app:getInfo", async (_event) => {
    return await appHandlers.getInfo();
  });

  ipcMain.handle("file:read", async (_event, params) => {
    return await fileHandlers.read(params);
  });
}
```

**`main/handlers/app.ts`** - Handler implementations (modify often)

```typescript
export const appHandlers = {
  getInfo: async () => {
    return {
      name: "My Glaze App",
      version: "1.0.0",
    };
  },
};
```

### Adding New Backend Handlers

**Step 1**: Create handler implementation

```typescript
// main/handlers/files.ts
export const fileHandlers = {
  read: async ({ path }: { path: string }) => {
    const content = await fs.promises.readFile(path, "utf8");
    return { content, path };
  },
};
```

**Step 2**: Register in `main/handlers/index.ts`

```typescript
ipcMain.handle("file:read", async (_event, params) => {
  return await fileHandlers.read(params);
});
```

**Channel naming**: `category:method` (e.g., `app:getInfo`, `file:read`, `data:fetch`)

### Backend Performance Rules

1. **child_process `maxBuffer`** — always set `maxBuffer: 10 * 1024 * 1024` when CLI output may exceed 1 MB (image processing, base64 encoding, large JSON). Always set `timeout`.
2. **Polling cleanup** — every `setInterval` must have a corresponding `clearInterval` in `app.on("before-quit")`. Prefer event-driven approaches when available.
3. **IPC payload separation** — never include base64-encoded images, file contents, or binary data in polling or broadcast responses. Send lightweight identifiers; let the frontend fetch heavy data on demand via a separate IPC channel.
4. **macOS app icons** — when extracting app icons, use `NSWorkspace.iconForFile()` via JXA (`osascript -l JavaScript`), not `CFBundleIconFile` alone (fails for asset catalog apps). More generally, prefer JXA for Cocoa API access over shell tools.
5. **Bounded caches** — all in-memory caches must have a max entry count and TTL. Clean up caches on `before-quit`.

See `glaze-backend-performance` skill for detailed patterns and code examples.

### Global Shortcuts (System-Wide Hotkeys)

Register keyboard shortcuts that work even when your app isn't focused:

```typescript
// main/index.ts or any backend file
import { globalShortcut } from "@glaze/core/backend";

// Register a global shortcut
const success = await globalShortcut.register("CommandOrControl+Shift+P", () => {
  console.log("Shortcut triggered!");
  mainWindow.show(); // Example: show app window
});

if (!success) {
  console.log("Shortcut registration failed - may be in use by another app");
}

// Check if registered
const isReg = await globalShortcut.isRegistered("CommandOrControl+Shift+P");

// Unregister when done
await globalShortcut.unregister("CommandOrControl+Shift+P");

// Or unregister all shortcuts (e.g., on app quit)
app.on("will-quit", async () => {
  await globalShortcut.unregisterAll();
});
```

**Accelerator Format:**

- Modifiers: `Command`, `Cmd`, `Control`, `Ctrl`, `CommandOrControl`, `CmdOrCtrl`, `Alt`, `Option`, `Shift`
- Keys: `A-Z`, `0-9`, `F1-F20`, `Space`, `Tab`, `Enter`, `Escape`, `Up`, `Down`, `Left`, `Right`, etc.
- Examples: `CommandOrControl+Shift+P`, `Alt+Space`, `F12`, `CommandOrControl+Alt+I`

**Note:** `CommandOrControl` uses ⌘ on macOS and Ctrl on Windows/Linux.

### System Notifications (Notification API)

Show native notifications from backend code with `Notification`:

```typescript
import { Notification } from "@glaze/core/backend";

const notification = new Notification({
  title: "Build complete",
  body: "Your app is ready",
  actions: [{ text: "Open App" }],
});

notification.on("click", () => {
  mainWindow.show();
});

notification.on("action", (details) => {
  console.log("Action index:", details.actionIndex);
});

notification.on("reply", (details) => {
  console.log("Reply:", details.reply);
});

notification.on("failed", (_event, error) => {
  console.error("Notification failed:", error);
});

notification.show();
```

`Notification` is a public `@glaze/core/backend` API. Do not use `backendNativeBridge` for notifications.

### System Tray (Menu Bar)

Add your app to the macOS menu bar with click events and context menus:

```typescript
// main/index.ts or any backend file
import { Tray, Menu } from "@glaze/core/backend";

// Create tray with SF Symbol icon (or file path)
const tray = new Tray("star.fill");
// Or: new Tray("/path/to/icon.png")

tray.setToolTip("My App"); // Hover text
tray.setTitle("Status"); // Text shown next to icon

// Set context menu (appears on click)
tray.setContextMenu(
  Menu.buildFromTemplate([
    // Icons use SF Symbol names (macOS) or file paths
    { label: "Show Window", icon: "macwindow", click: () => mainWindow.show() },
    { label: "New Document", icon: "doc.badge.plus", accelerator: "Command+N" },
    { type: "separator" },
    // Sublabels show secondary text below the label (macOS 14.4+)
    {
      label: "Sync Status",
      icon: "arrow.triangle.2.circlepath",
      sublabel: "Last synced 2 min ago",
    },
    { type: "separator" },
    // Checkbox items
    {
      label: "Enable Notifications",
      type: "checkbox",
      checked: true,
      icon: "bell.fill",
    },
    { type: "separator" },
    // Submenus
    {
      label: "Recent",
      icon: "clock",
      submenu: [
        { label: "Project A", icon: "folder.fill" },
        { label: "Project B", icon: "folder.fill" },
      ],
    },
    { type: "separator" },
    // Disabled items
    { label: "Upgrade to Pro", icon: "star.fill", enabled: false },
    { type: "separator" },
    { label: "Preferences...", icon: "gearshape", accelerator: "Command+," },
    { label: "Quit", role: "quit", icon: "power" },
  ]),
);

// Handle click events
tray.on("click", (event, bounds) => {
  console.log("Tray clicked at", bounds);
  mainWindow.show();
});

tray.on("right-click", (event, bounds) => {
  console.log("Right-clicked at", bounds);
});

// Get tray position (useful for positioning popover windows)
const bounds = await tray.getBounds(); // { x, y, width, height }

// Change icon dynamically
tray.setImage("bell.fill"); // SF Symbol
tray.setImage("/path/to/new-icon.png"); // File path

// Clean up when app quits
app.on("will-quit", () => {
  tray.destroy();
});
```

**Available Events:** `click`, `right-click`, `double-click`, `mouse-enter`, `mouse-leave`, `mouse-move`, `mouse-down`, `mouse-up`

**Tray Icon Options:**

- SF Symbols: `"star.fill"`, `"bell.fill"`, `"gear"`, etc. (macOS)
- File paths: PNG files (16x16 or 18x18 for retina recommended)
- Template images: Icons automatically adapt to light/dark menu bar

**Menu Item Options:** | Property | Type | Description | |----------|------|-------------| | `label` | string | Menu item text | | `icon` | string | SF Symbol name or file path | | `sublabel` | string | Secondary text below label (macOS 14.4+) | | `accelerator` | string | Keyboard shortcut (e.g., `"Command+N"`) | | `enabled` | boolean | Whether item is clickable (default: true) | | `type` | string | `"normal"`, `"separator"`, `"checkbox"`, `"radio"` | | `checked` | boolean | For checkbox/radio items | | `submenu` | array | Nested menu items | | `role` | string | Predefined action (`"quit"`, `"copy"`, etc.) | | `click` | function | Click handler |

---

## 🎨 FRONTEND (renderer/)

**Purpose**: React application running in native macOS WebView.

### Directory Structure

```
renderer/
├── main/                    # Application code
│   ├── index.tsx           # React entry point
│   ├── router.tsx          # Route definitions
│   ├── root-view.tsx       # Root layout with Cmd+K palette
│   └── home-view.tsx       # Main view (modify this often)
│
├── settings/                # Settings window React app
│   ├── index.tsx           # Settings entry point (rarely modify)
│   └── settings-view.tsx   # Settings UI (modify to add settings)
│
├── components/              # App-specific components
│   └── status-bar.tsx
│
├── preload.ts               # Context bridge (exposes window.glazeAPI)
└── styles.css               # Tailwind styles & @source directives
```

### Key Files

**`renderer/main/index.tsx`** - React entry point (rarely modify)

- Sets up React root
- Configures TanStack Router and Query
- Mounts to `#root` element

**`renderer/main/router.tsx`** - Route configuration (modify to add routes)

```typescript
import { createRoute, createRouter } from "@tanstack/react-router";
import { HomeView } from "./home-view";

const homeRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/",
  component: HomeView,
  staticData: { title: "Home" }  // Shows in Cmd+K command palette
});

const routeTree = rootRoute.addChildren([homeRoute]);
const router = createRouter({ routeTree, ... });
```

**`renderer/main/root-view.tsx`** - Root layout (sometimes modify)

- Renders `<Outlet />` for route content
- Provides Cmd+K command palette
- Shows connection status indicators
- Handles theme detection

**`renderer/main/home-view.tsx`** - Main UI (modify this often)

- `ToolbarTitle` is optional: use it only when users need context (active tab/file/section). For simple single-view apps, omit it. Avoid app-name titles unless explicitly requested.

---

## ⚙️ Configuration

### package.json - App Configuration

```json
{
  "name": "my-app",
  "appConfig": {
    "displayName": "My Awesome App"
  }
}
```

### glaze.config.ts - Build Customization (Optional)

Override default Vite and esbuild options if needed:

```typescript
import { defineConfig } from "@glaze/core/build";

export default defineConfig({
  // Vite overrides (dev server port, aliases, plugins)
  // Build overrides (esbuild options)
});
```

Most apps don't need this file — the `@glaze/core` CLI provides sensible defaults.

---

## 📦 Bundling & Publishing

### How Glaze Apps Are Built

Glaze apps use **esbuild** to bundle all backend code and npm dependencies into a single `build/main/index.js` file. This is critical to understand:

```
.glaze-sources/             ← Development (where you edit code)
├── main/                  ← Backend source
├── renderer/              ← Frontend source
├── node_modules/          ← NPM packages (NOT shipped)
└── package.json

.glaze/build/               ← Runtime (what actually runs)
├── main/
│   └── index.js           ← ALL backend code bundled here
└── renderer/
    └── index.html         ← Frontend assets
```

**Key insight:** After building, `node_modules/` is NOT used at runtime. Everything is bundled into the single `index.js` file.

**CRITICAL: Never modify `.glaze/` directly.** The `.glaze/` directory is the build output and must be fully produced by the build process. Never add symlinks, copy files, create `node_modules/`, or apply any manual fixes to `.glaze/` — if something is missing at runtime, fix the build configuration (via `glaze.config.ts` or `@glaze/core` build module) so the output is self-contained.

### What Gets Bundled

esbuild bundles:

- All your `main/` TypeScript code
- All npm packages imported by your code
- Transitive dependencies (dependencies of dependencies)

esbuild does NOT bundle:

- Node.js built-ins (`fs`, `path`, `crypto`, etc.) - available at runtime
- Native `.node` modules - require special handling (see below)
- Files loaded via `fs.readFile()` at runtime - not static imports

### Packages That Can't Be Bundled

Most npm packages bundle fine into a single ESM file. However, some packages need special handling because they include files that esbuild can't inline into the bundle.

**IMPORTANT — Prefer bundleable alternatives first.** Before using either plugin below, check if a lighter, pure-JS alternative exists that bundles cleanly with no extra setup:

| Instead of | Consider | Why |
| --- | --- | --- |
| `better-sqlite3` (native) | `node:sqlite` (built-in, no install needed) | Glaze ships Node.js 24+, which includes a built-in SQLite module |
| `jsdom` (heavy, needs externalization) | `node-html-parser` (pure JS, bundles fine) | If you only need HTML parsing/querying, not full DOM emulation |
| `sharp` (native) | Use `sharp` with `copyNativeBindings` plugin | No good pure-JS alternative — `jimp` is far slower and lacks many features. Use the plugin. |

If no alternative exists, use the appropriate plugin below. There are two plugins, in order of preference:

#### 1. `copyNativeBindings` — for native `.node` binaries (preferred)

Use this when a package's JS code bundles fine but it ships a native `.node` addon that esbuild can't inline. The plugin just copies the single binary file to the build output. The JS gets bundled normally.

**Use for:** `better-sqlite3-multiple-ciphers`, and similar packages with a single native addon.

```typescript
// glaze.config.ts
import { defineConfig, copyNativeBindings } from "@glaze/core/build";

export default defineConfig({
  build: {
    plugins: [copyNativeBindings("better-sqlite3-multiple-ciphers", "better_sqlite3.node")],
  },
});
```

#### 2. `externalizePackage` — for packages that need their full directory structure (last resort)

Use this when a package can't be bundled at all — e.g. it loads files from disk at runtime using paths relative to its own source, or it expects helper executables/assets to exist next to the package at runtime. This plugin externalizes the entire package from the bundle and copies it along with all its transitive dependencies to the build output's `node_modules/`. This is heavier than `copyNativeBindings` because it copies the full package tree.

**Use for:** `jsdom` (loads CSS stylesheets via `__dirname`), `node-pty` (loads `spawn-helper` from `prebuilds/` at runtime), or any package where `copyNativeBindings` isn't sufficient (e.g. the package loads non-binary assets from its directory at runtime).

**How to tell which plugin to use:** If the package crashes at runtime with `__dirname`-related errors, missing asset/helper files after bundling, or it expects sibling executables under its package directory, it needs `externalizePackage`. If it only fails to load a `.node` binary, `copyNativeBindings` is sufficient.

```typescript
// glaze.config.ts
import { defineConfig, externalizePackage } from "@glaze/core/build";

const jsdom = externalizePackage("jsdom");

export default defineConfig({
  build: {
    external: [...jsdom.externals],
    plugins: [jsdom.plugin],
  },
});
```

The plugin reads the package's `package.json`, recursively walks `dependencies` and `optionalDependencies`, and returns:

- `externals` — array of package names to add to esbuild's `external` config
- `plugin` — esbuild plugin that copies the package and all its transitive deps to `build/main/node_modules/`

### Common Bundling Pitfalls

**1. Dynamic imports that esbuild can't analyze:**

```typescript
// Bad: esbuild can't trace this
const moduleName = "some-module";
const mod = require(moduleName);

// Good: static import (esbuild bundles it)
import mod from "some-module";
```

**2. Forgetting native modules:**

```typescript
// This will FAIL after publish if you don't use copyNativeBindings
import Database from "better-sqlite3";
// Error: Cannot find module 'better_sqlite3.node'
```

**3. Relying on files in node_modules:**

```typescript
// Bad: node_modules doesn't exist after publish
const templatePath = path.join(__dirname, "..", "node_modules", "some-pkg", "template.json");

// Good: bundle it as a string or copy it to build/
import template from "some-pkg/template.json";
```

**4. Using local CLI tools:**

```typescript
// Bad: npx/npm scripts won't work after publish
exec("npx some-tool");

// Good: bundle the tool or use a Node.js library instead
import { someTool } from "some-tool-lib";
```

**5. Runtime `node_modules` symlink hacks:**

```bash
# Bad: masks bundling bugs and breaks after publish
ln -s ../.glaze-sources/node_modules ../.glaze/node_modules
```

Never patch `.glaze/` like this. The build must produce a self-contained output — whatever ends up in `.glaze/` after a build is what runs in production. If something is missing at runtime, fix the build configuration (via `glaze.config.ts`), not the output directory.

---

## 🖼️ Static Assets (Images, Media, Fonts)

### Importing in React (Recommended)

**Best for:** Images, icons, and media used in React components.

```typescript
import logo from './assets/logo.png';
import heroImage from '../assets/hero.jpg';

<img src={logo} alt="Logo" />
```

**How it works:**

- Vite processes imports → hashed filenames (e.g., `logo-2d8efhg.png`)
- Small images (< 4KB) inlined as base64
- Output to `build/assets/` automatically

**Where to put files:** `renderer/main/assets/` for component-specific, `renderer/assets/` for shared.

### Public Directory (Unprocessed Files)

**Best for:** Files that must keep exact filenames, or referenced by URL string.

Create `public/` at template root → files copied as-is to `build/` root.

```
glaze-app/
├── public/           ← Create this folder
│   ├── favicon.ico
│   └── images/
│       └── og-image.png
```

```typescript
// ⚠️ Use RELATIVE paths (file:// protocol requirement)
<img src="./images/logo.png" />   // ✅ Correct
<img src="/images/logo.png" />    // ❌ Won't work!

// In CSS (relative to build/assets/)
background-image: url('../images/bg.svg');
```

### Backend Assets

**Import JSON directly** (gets bundled):

```typescript
import data from "./data.json";
```

**For larger files**, use the `glaze build` output directory and a post-build copy step, or include them via esbuild's `loader` option in `glaze.config.ts`.

### Dynamic Image Paths

```typescript
function getAssetUrl(name: string) {
  return new URL(`./assets/${name}`, import.meta.url).href;
}
<img src={getAssetUrl('icon-home.png')} />
```

### What NOT to Do

```typescript
// ❌ Don't use require() for images
const logo = require('./logo.png');

// ❌ Don't construct paths to node_modules (won't exist after publish)
const icon = path.join(__dirname, 'node_modules', 'pkg', 'icon.png');

// ❌ Don't use absolute filesystem paths
<img src="/Users/me/project/logo.png" />

// ❌ Don't use root-absolute paths for public assets (file:// won't resolve)
<img src="/images/logo.png" />  // Wrong!
<img src="./images/logo.png" /> // Correct!
```

---

### Testing Before Publishing

**Your app must work from `.glaze/build/` without `node_modules/`.** The development structure ensures this:

```
.glaze/                  ← Runtime (same as installed apps)
└── build/              ← No node_modules fallback!

.glaze-sources/          ← Development only (sibling folder)
└── node_modules/       ← NOT in Node's module resolution path
```

This means if something isn't properly bundled, you'll catch it during local development - not after publishing.

**Test checklist before publish:**

- [ ] App runs and all features work
- [ ] No console errors about missing modules
- [ ] Native modules (if any) load correctly
- [ ] External files load from correct paths

### Publishing Flow

When you publish:

1. `build/` directory is zipped → uploaded to store
2. Users install → `build/` is extracted to their `.glaze/`
3. App runs from `build/main/index.js` - no `node_modules/`

If your app works locally, it will work after install (same directory structure).

---

**Goal**: Create a file reader with native file picker

### 1. Backend Handler

**Create `main/handlers/files.ts`:**

```typescript
import * as fs from "fs/promises";

export const fileHandlers = {
  read: async ({ path }: { path: string }) => {
    const content = await fs.readFile(path, "utf8");
    return { content, path };
  },
  write: async ({ path, content }: { path: string; content: string }) => {
    await fs.writeFile(path, content, "utf8");
    return { path };
  },
};
```

**Register in `main/handlers/index.ts`:**

```typescript
import { ipcMain } from "@glaze/core/backend";
import { fileHandlers } from "./files.js";

export function registerHandlers(): void {
  ipcMain.handle("file:read", async (_event, params) => {
    return await fileHandlers.read(params);
  });
  ipcMain.handle("file:write", async (_event, params) => {
    return await fileHandlers.write(params);
  });
}
```

### 2. Frontend UI

**Update `renderer/main/home-view.tsx`:**

```typescript
import { useState } from 'react';
import { Button } from '@glaze/core/components';

export function HomeView() {
  const [content, setContent] = useState('');

  const handleOpenFile = async () => {
    // Use window.glazeAPI - NEVER import ipcRenderer directly
    const result = await window.glazeAPI.dialog.showOpenDialog({
      title: 'Open Text File',
      filters: [
        { name: 'Text Files', extensions: ['txt'] },
        { name: 'All Files', extensions: ['*'] }
      ],
      properties: ['openFile']
    });

    if (!result.canceled && result.filePaths.length > 0) {
      // Read file via backend handler
      const fileData = await window.glazeAPI.glaze.ipc.invoke('file:read', { path: result.filePaths[0] });
      setContent(fileData.content);
    }
  };

  const handleSaveFile = async () => {
    const result = await window.glazeAPI.dialog.showSaveDialog({
      title: 'Save Text File',
      defaultPath: '~/untitled.txt',
      filters: [
        { name: 'Text Files', extensions: ['txt'] },
        { name: 'All Files', extensions: ['*'] }
      ]
    });

    if (!result.canceled && result.filePath) {
      await window.glazeAPI.glaze.ipc.invoke('file:write', { path: result.filePath, content });
    }
  };

  return (
    <div className="p-4">
      <div className="flex gap-2">
        <Button onClick={handleOpenFile}>Open File</Button>
        <Button onClick={handleSaveFile}>Save File</Button>
      </div>
      {content && (
        <pre className="mt-4 text-gray-11">{content}</pre>
      )}
    </div>
  );
}
```

### 3. Backend Dialog API

You can also use dialogs directly from the backend:

**In `main/index.ts` or any backend file:**

```typescript
import { dialog } from "@glaze/core/backend";
import * as fs from "fs/promises";

async function openAndProcessFile() {
  const result = await dialog.showOpenDialog({
    title: "Select a file to process",
    filters: [
      { name: "JSON Files", extensions: ["json"] },
      { name: "All Files", extensions: ["*"] },
    ],
    properties: ["openFile"],
  });

  if (!result.canceled && result.filePaths.length > 0) {
    const content = await fs.readFile(result.filePaths[0], "utf8");
    // Process the file...
    return JSON.parse(content);
  }
}

async function saveProcessedData(data: any) {
  const result = await dialog.showSaveDialog({
    title: "Save results",
    defaultPath: "~/results.json",
    filters: [{ name: "JSON Files", extensions: ["json"] }],
  });

  if (!result.canceled && result.filePath) {
    await fs.writeFile(result.filePath, JSON.stringify(data, null, 2), "utf8");
  }
}
```

---

## 🔄 SDK Updates

### Upgrading Your App

To upgrade your app to the latest SDK version, use the `/upgrade` command in the AI agent chat.

The agent will:

1. Update your `package.json` with the new SDK version
2. Copy the latest `@glaze/core` package
3. Copy the latest `.claude/skills`
4. Run `npm install --include=dev` and `glaze build`
5. Repackage your app bundle with the latest native shell

After migration, renderer entrypoints should import local styles:

```typescript
import "../styles.css";
```

Do not switch entrypoints to `@glaze/core/components.css`; SDK component styles are injected at runtime by the native shell. Use `@import "@glaze/core/components.tailwind.css"` in `renderer/styles.css` for Tailwind theme token definitions.

Your app's SDK version is tracked in `package.json` under the `glaze` section:

```json
{
  "glaze": {
    "sdkVersion": "1.0.0",
    "createdAt": "2025-11-18T19:18:04Z",
    "lastUpgrade": "2025-11-19T10:30:00Z"
  }
}
```

### Customizing Shared Components

To customize shared components, create wrappers in `renderer/components/`:

```typescript
// renderer/components/custom-button.tsx
import { Button } from '@glaze/core/components';

export function CustomButton({ children, ...props }) {
  return (
    <Button className="my-custom-styles" {...props}>
      {children}
    </Button>
  );
}
```

This preserves your customizations during SDK updates.

---

## 📋 Quick Reference

### Import Paths

```typescript
// Backend - Window Management
import { app, BrowserWindow } from "@glaze/core/backend";

// Backend - IPC, Logging & System
import { ipcMain, logger, globalShortcut, Notification, Tray, Menu } from "@glaze/core/backend";

// Preload ONLY - IPC and contextBridge (DO NOT use in renderer code!)
import { ipcRenderer, contextBridge } from "@glaze/core/preload";

// Frontend - Types only (safe to import anywhere)
import type { OpenDialogOptions, SaveDialogOptions } from "@glaze/core/ipc";

// Frontend - Router
import { createRoute } from "@tanstack/react-router";

// Frontend - Components
import { Button } from "@glaze/core/components";

// Frontend - Hooks
import { useConnection } from "@glaze/core/hooks";
```

> **SECURITY**: `@glaze/core/preload` should ONLY be imported in `renderer/preload.ts`. Renderer code should use `window.glazeAPI` instead.

### Preload Script Constraints

The preload script is built as a **self-contained IIFE** (not an ES module) because WKWebView injects it via `WKUserScript`, which only supports classic scripts. The build system handles this transparently — write normal TypeScript with imports and esbuild bundles everything.

**What this means for you:**

| Constraint                           | Reason                                                       |
| ------------------------------------ | ------------------------------------------------------------ |
| No dynamic `import()`                | All dependencies resolved at build time                      |
| No top-level `await`                 | Classic scripts don't support it (wrap in async function)    |
| No Node.js APIs (`fs`, `path`, etc.) | WKWebView is a browser environment — use IPC to call backend |
| Keep the preload thin                | Everything is inlined; large deps slow down injection        |

**What works fine:**

- Static `import` of any npm package (bundled by esbuild)
- Async functions (just can't use top-level await)
- All browser/DOM APIs
- `ipcRenderer` and `contextBridge` from `@glaze/core/preload`

**Context isolation note:** Glaze uses `WKContentWorld`, which provides fully separate JavaScript environments with their own prototypes and globals. Prototype pollution in the page world cannot affect the preload world.

### Common Patterns

**Create Window:**

```typescript
import { app, BrowserWindow } from "@glaze/core/backend";
import { getPreloadPath, getWindowUrl } from "./windows/window-paths.js";

app.whenReady().then(async () => {
  const win = new BrowserWindow({
    windowKey: "main",
    width: 800,
    height: 600,
    show: false,
    webPreferences: { preload: getPreloadPath() },
  });
  win.once("ready-to-show", () => win.show());
  await win.loadURL(await getWindowUrl("main-window.html"));
});
```

**Add Backend Method:**

1. Create handler in `main/handlers/your-handler.ts`
2. Register with `ipcMain.handle()` in `main/handlers/index.ts`

**Add Frontend View:**

1. Create component in `renderer/main/your-view.tsx`
2. Add route in `renderer/main/router.tsx`

**Call Backend from Frontend:**

```typescript
// Use window.glazeAPI.glaze.ipc.invoke for custom handlers
const result = await window.glazeAPI.glaze.ipc.invoke("channel:method", params);
```

**Use Native macOS Feature (safe by default):**

```typescript
// File dialog - SAFE (requires user interaction)
const result = await window.glazeAPI.dialog.showOpenDialog(options);

// System sound - SAFE
await window.glazeAPI.shell.beep();

// ⚠️ SENSITIVE - Enable in preload.ts first:
// await window.glazeAPI.shell.openExternal("https://example.com");
// await window.glazeAPI.clipboard.writeText("hello");
```

**Register Global Shortcut (backend only):**

```typescript
import { globalShortcut } from "@glaze/core/backend";

await globalShortcut.register("CommandOrControl+Shift+Space", () => {
  mainWindow.show();
});
```

---

## 🗂️ File Modification Guide

### Modify Often

- `main/handlers/*.ts` - Backend IPC handlers and business logic
- `renderer/main/home-view.tsx` - Main UI
- `renderer/main/router.tsx` - Add routes
- `renderer/components/*.tsx` - App-specific components
- `package.json` - Dependencies and app config

### Modify Sometimes

- `main/index.ts` - Window creation, app menu, lifecycle events
- `main/windows/*.ts` - Window creation helpers for additional windows
- `renderer/main/root-view.tsx` - Global layout
- `renderer/preload.ts` - Add new APIs to expose to renderer
- `renderer/styles.css` - Add Tailwind `@source` directives for new directories
- `renderer/types/` - TypeScript types for custom APIs

### Rarely Modify

- `renderer/main/index.tsx` - React entry point setup (providers, root render)
- `renderer/settings/index.tsx` - Settings window React entry point
- `glaze.config.ts` - Build customization (create when needed for native modules)

### Never Modify

See **Critical Rules** at the top of this document for the full list of protected paths.
