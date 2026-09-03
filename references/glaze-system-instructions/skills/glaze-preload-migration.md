---
name: glaze-preload-migration
description: One-time migration from HTML-based preload (modulepreload/script tag) to runtime-injected preload via webPreferences.preload.
---

# Glaze Preload Migration

This is a **one-time migration** for apps created before preload injection was moved to the native runtime. The native layer now injects the preload script into an isolated `WKContentWorld` via `webPreferences.preload`, providing stronger security than the old HTML-based approach.

## When to Run

Run this skill when **any** of these are true:

- `main/index.ts` creates a `BrowserWindow` without `webPreferences.preload`
- No file in `main/` calls `getPreloadPath()`
- HTML files contain `<script>` or `<link rel="modulepreload">` tags referencing `renderer/preload`
- You see this runtime warning in logs: `webPreferences.preload not set — using conventional fallback`

If all `BrowserWindow` creations already pass `webPreferences.preload`, the migration is done — skip this skill.

## What Changed

The preload script used to be loaded via the HTML import chain (Vite bundled `@glaze/core/preload` as a module dependency of the main entry). This ran in the **page world**, meaning page scripts could access preload internals.

The new model:

1. The preload is built as a self-contained **IIFE** (not ES module) by `glaze build`
2. The native runtime reads the path from `webPreferences.preload` and injects it via `WKUserScript` into an **isolated `WKContentWorld`**
3. Page scripts cannot access preload internals — `WKContentWorld` provides fully separate JavaScript environments (own prototypes, own globals)
4. The `contextBridge` sends a shape descriptor to the native layer, which generates a frozen proxy in the page world

## Migration Steps

### 1. Ensure `main/windows/window-paths.ts` exports `getPreloadPath()`

Check if the file exists and has this function. If not, add it:

```typescript
import * as path from "path";

const BUILD_ROOT = path.resolve(import.meta.dirname, "..", "..", "build");

export function getPreloadPath(): string {
  return path.join(BUILD_ROOT, "assets", "preload.js");
}
```

If `window-paths.ts` already has `getWindowUrl()` or similar helpers, add `getPreloadPath()` alongside them.

### 2. Pass `webPreferences.preload` in every `BrowserWindow` creation

Find all places where `new BrowserWindow(...)` is called and add the preload path:

```typescript
import { getPreloadPath } from "./windows/window-paths.js";

const win = new BrowserWindow({
  // ... existing options ...
  webPreferences: {
    preload: getPreloadPath(),
  },
});
```

Do this for **every** window — main window, settings window, and any other windows the app creates.

### 3. Remove preload references from HTML files

Check all `*-window.html` files for:

- `<script type="module" src="./renderer/preload.ts"></script>` — **remove**
- `<link rel="modulepreload" href="...preload...">` — **remove**

The HTML should only have the main entry script:

```html
<body>
  <div id="root"></div>
  <!-- Preload is injected by the native layer via webPreferences.preload -->
  <script type="module" src="./renderer/main/index.tsx"></script>
</body>
```

### 4. Verify `renderer/preload.ts` exists

The preload file should already exist. Verify it:

- Imports from `@glaze/core/preload` (e.g., `ipcRenderer`, `contextBridge`)
- Calls `contextBridge.exposeInMainWorld("glazeAPI", { ... })`
- Does NOT use dynamic `import()` or top-level `await` (IIFE constraints)

### 5. Build and verify

```bash
npm run build
```

After building, verify:

- `build/assets/preload.js` exists and is a self-contained IIFE
- No runtime warning about `webPreferences.preload not set` in logs
- IPC communication works (renderer can call backend handlers)
- All windows load correctly

## Reference

See `packages/glaze-app-template/main/index.ts` and `main/windows/window-paths.ts` for the canonical pattern.
