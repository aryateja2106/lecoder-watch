---
name: glaze-browser-window-recipes
description: Recipes for specialized BrowserWindow setups in Glaze apps, including transparent windows, frameless custom chrome, parent and modal windows, draggable headers, hidden or repositioned window buttons, floating utility windows, click-through overlays, and document-style windows. Use this when a user asks to customize native window appearance or behavior beyond a default titled window.
---

# Glaze BrowserWindow Recipes

Use this skill when a Glaze app needs a non-default window configuration.

Create and manage windows from the backend with `BrowserWindow` from `@glaze/core/backend`. Use `windowKey` for stable windows. Keep renderer work focused on HTML/CSS and drag-region markup.

**Every recipe assumes these imports:**

```ts
import { BrowserWindow } from "@glaze/core/backend";
import { getPreloadPath, getWindowUrl } from "./windows/window-paths.js";
```

## Quick Picks

- **Transparent overlay or HUD**: `transparent: true`, `backgroundColor: "#00000000"`, transparent renderer backgrounds, usually `hasShadow: false`
- **Native macOS vibrancy window**: `setVibrancy("sidebar" | "hud" | "popover" | ...)`, transparent renderer backgrounds, usually `frame: true` unless you need custom chrome
- **Frameless custom chrome**: `frame: false` (automatically sets `toolbarStyle: "none"`), add a `.drag-region` header and `.no-drag` controls
- **Floating utility window**: `alwaysOnTop: true`, often `hiddenInMissionControl: true`, sometimes `visibleOnAllWorkspaces: true`
- **Click-through overlay**: transparent window plus `setIgnoreMouseEvents(true, { forward: true })`
- **Document-style window**: `setRepresentedFilename(...)`, `setDocumentEdited(...)`, optional `accessibleTitle`
- **Parent / modal window**: pass `parent`, optionally `modal: true`, then load and show the child after the parent is ready
- **Custom titlebar buttons**: `setWindowButtonVisibility(...)` and `setWindowButtonPosition(...)`

## Core Rules

1. Always set `webPreferences: { preload: getPreloadPath() }` — without it, `window.glazeAPI` is unavailable in the new window.
2. Always load URLs via `getWindowUrl()` — it resolves to the dev server in development and a `file://` URL in production.
3. Use `show: false` + `ready-to-show` event to prevent a white flash while content loads.
4. `frame: false` automatically sets `toolbarStyle: "none"` — specifying both is redundant.
5. `toolbarStyle: "none"` removes the toolbar area but does not hide the traffic lights. Use `setWindowButtonVisibility(false)` to hide them.
6. Transparent windows still need renderer CSS to be transparent.
7. Interactive elements inside draggable regions must use `.no-drag`, or live inside a component that already applies it.
8. Prefer Glaze primitives when they already encode window behavior. `<Toolbar>` already renders a drag region.
9. `toolbarStyle` accepts `"none"`, `"unified"` (default), or `"unifiedCompact"`.
10. Use `parent` for attached child windows. Add `modal: true` when the child should appear as a native sheet on macOS.
11. `setVibrancy()` is the macOS-native translucency API for translucent materials like `"sidebar"`, `"hud"`, and `"popover"`.
12. `screen.getPrimaryDisplay()` and the other `screen` getters are async in Glaze. Always `await` them.
13. When positioning relative to a display `workArea`, include both the size and the origin: use `workArea.x + ...` and `workArea.y + ...`, not just `workArea.width` or `workArea.height`.

## Recipe: Native macOS Vibrancy Window

Use this when you want a native translucent material like a sidebar, HUD, or popover.

```ts
const win = new BrowserWindow({
  windowKey: "vibrant-window",
  width: 520,
  height: 360,
  frame: true,
  toolbarStyle: "none",
  backgroundColor: "#00000000",
  vibrancy: "sidebar",
  show: false,
  webPreferences: { preload: getPreloadPath() },
});

win.once("ready-to-show", () => win.showInactive());
await win.loadURL(await getWindowUrl("vibrant-window.html"));
```

Renderer CSS:

```css
html,
body,
#root {
  background: transparent;
}
```

Notes:

- Use `setVibrancy()` or the constructor `vibrancy` option for macOS-native materials.
- Deprecated AppKit materials like `"light"` or `"dark"` are intentionally unsupported.

## Recipe: Transparent Overlay

Use this for HUDs, floating widgets, or overlays with rounded corners.

```ts
const win = new BrowserWindow({
  windowKey: "overlay",
  width: 420,
  height: 240,
  frame: false,
  transparent: true,
  backgroundColor: "#00000000",
  hasShadow: false,
  alwaysOnTop: true,
  show: false,
  webPreferences: { preload: getPreloadPath() },
});

win.once("ready-to-show", () => win.show());
await win.loadURL(await getWindowUrl("overlay-window.html"));
```

Renderer CSS:

```css
html,
body,
#root {
  background: transparent;
}
```

Notes:

- If the window still shows a solid background, check `transparent: true`, `backgroundColor: "#00000000"`, and transparent renderer backgrounds first.
- If you want native macOS translucency rather than a fully transparent overlay, use the vibrancy recipe above instead of this one.
- Use `hasShadow: false` for a clean overlay look. Keep it `true` if you want separation from the desktop.

## Recipe: Frameless Window With Custom Header

Use this when you want your own titlebar and buttons.

```ts
const win = new BrowserWindow({
  windowKey: "custom-chrome",
  width: 960,
  height: 700,
  frame: false,
  title: "Custom Chrome",
  show: false,
  webPreferences: { preload: getPreloadPath() },
});

win.once("ready-to-show", () => win.show());
await win.loadURL(await getWindowUrl("custom-window.html"));
```

Renderer:

```tsx
export function Header() {
  return (
    <div className="drag-region flex h-12 items-center px-3">
      <div className="text-sm font-medium">Custom Chrome</div>
      <button className="no-drag ml-auto">Action</button>
    </div>
  );
}
```

If shared styles are unavailable, write the CSS directly:

```css
.drag-region {
  -webkit-app-region: drag;
  app-region: drag;
}

.no-drag {
  -webkit-app-region: no-drag;
  app-region: no-drag;
}
```

## Recipe: Keep Native Buttons But Reposition Or Hide Them

Use this when you keep a native frame but want a custom top layout.

```ts
const win = new BrowserWindow({
  windowKey: "titled",
  width: 960,
  height: 720,
  frame: true,
  toolbarStyle: "unified",
  windowButtonPosition: { x: 18, y: 18 },
  show: false,
  webPreferences: { preload: getPreloadPath() },
});

win.once("ready-to-show", () => win.show());
await win.loadURL(await getWindowUrl("main-window.html"));
```

Or update after creation:

```ts
win.setWindowButtonPosition({ x: 18, y: 18 });
win.setWindowButtonVisibility(false);
```

Notes:

- Hiding buttons is separate from toolbar style.
- If you hide native buttons, provide your own close/minimize/fullscreen affordances if the design still needs them.

## Recipe: Floating Utility Window

Use this for inspectors, compact tools, and mini-panels.

```ts
const win = new BrowserWindow({
  windowKey: "utility",
  width: 360,
  height: 420,
  frame: true,
  alwaysOnTop: true,
  hiddenInMissionControl: true,
  visibleOnAllWorkspaces: true,
  hasShadow: true,
  show: false,
  webPreferences: { preload: getPreloadPath() },
});

win.once("ready-to-show", () => win.show());
await win.loadURL(await getWindowUrl("utility-window.html"));
```

Common follow-ups:

- `win.setAlwaysOnTop(true, "floating")` for a stronger floating level
- `win.setFocusable(false)` if it should behave like a passive overlay
- `win.setSkipTaskbar(true)` if it should stay out of the Dock/task switcher

## Recipe: Click-Through Overlay

Use this for passive overlays that should not intercept clicks.

```ts
const win = new BrowserWindow({
  windowKey: "pass-through",
  width: 500,
  height: 300,
  frame: false,
  transparent: true,
  backgroundColor: "#00000000",
  alwaysOnTop: true,
  show: false,
  webPreferences: { preload: getPreloadPath() },
});

win.setIgnoreMouseEvents(true, { forward: true });
win.once("ready-to-show", () => win.show());
await win.loadURL(await getWindowUrl("passthrough-window.html"));
```

Notes:

- `forward` is accepted for API compatibility. On macOS it does not map to a separate native mode, so do not rely on it for distinct behavior.
- Turn ignored mouse events off before expecting drag, hover, or button clicks to work again.

## Recipe: Document Window

Use this when the window represents a file and should show document state in native chrome.

```ts
const win = new BrowserWindow({
  windowKey: "editor",
  width: 1000,
  height: 720,
  title: "Notes",
  show: false,
  webPreferences: { preload: getPreloadPath() },
});

win.setRepresentedFilename("/Users/me/Documents/notes.md");
win.setDocumentEdited(true);
win.accessibleTitle = "Notes document window";
win.once("ready-to-show", () => win.show());
await win.loadURL(await getWindowUrl("editor-window.html"));
```

Use `accessibleTitle` when the visible title is too short or ambiguous for assistive technologies.

## Recipe: Parent Window With Modal Sheet

Use this when a secondary window should stay attached to a primary window or appear as a sheet.

```ts
const parent = new BrowserWindow({
  windowKey: "editor",
  width: 1000,
  height: 720,
  title: "Editor",
  show: false,
  webPreferences: { preload: getPreloadPath() },
});

const child = new BrowserWindow({
  windowKey: "editor-inspector",
  parent,
  modal: true,
  width: 420,
  height: 320,
  title: "Inspector",
  show: false,
  webPreferences: { preload: getPreloadPath() },
});

parent.once("ready-to-show", () => parent.show());
await parent.loadURL(await getWindowUrl("editor-window.html"));

child.once("ready-to-show", () => child.show());
await child.loadURL(await getWindowUrl("inspector-window.html"));
```

Notes:

- Omit `modal: true` if you want a regular attached child window instead of a sheet.
- Use `child.setParentWindow(null)` to detach a child and let it float independently.
- `child.getParentWindow()`, `parent.getChildWindows()`, and `child.isModal()` reflect the current relationship in JS.

## Dragging Guidance

- Prefer `.drag-region` and `.no-drag` classes from shared styles.
- `<Toolbar>` from `@glaze/core/components` already renders a drag region.
- Buttons, inputs, selects, links, and textareas are already treated as non-draggable by the shared styles.
- For frameless windows, add an intentional top drag strip. Do not rely on random empty padding.

## Troubleshooting

**The window is still opaque**

- Check `transparent: true`
- Check `backgroundColor: "#00000000"`
- Check renderer root backgrounds (`html`, `body`, `#root`)

**The window is not using macOS vibrancy**

- Use `setVibrancy("sidebar" | "hud" | "popover" | ...)` or the constructor `vibrancy` option
- Check renderer root backgrounds (`html`, `body`, `#root`)

**Traffic lights are still visible**

- `toolbarStyle: "none"` is not enough
- Use `win.setWindowButtonVisibility(false)`

**The window does not drag**

- Add a `.drag-region`
- Add `.no-drag` to nested controls
- If using `<Toolbar>`, keep controls inside components that already opt out of drag behavior

**Controls inside the header are not clickable**

- They are probably inheriting drag behavior from a parent
- Add `.no-drag` to the interactive container or control

**The window looks wrong in transparent mode**

- Remove unintended translucency settings
- Remove unintended renderer background colors
- Decide explicitly whether the overlay should keep a shadow

**`window.glazeAPI` is undefined in the new window**

- Check that `webPreferences: { preload: getPreloadPath() }` is set in the constructor options
- The preload script must be a built JS file — run a build if it hasn't been generated yet

## Good Defaults

- Use `windowKey`, not deprecated `id`
- Use `show: false` with `win.once("ready-to-show", () => win.show())` to prevent flicker
- Use `showInactive()` when the window should appear without stealing focus
- Always set `webPreferences: { preload: getPreloadPath() }` so `window.glazeAPI` works
- Always load via `await win.loadURL(await getWindowUrl("your-window.html"))` for dev/prod compatibility
- Keep `frame: true` unless you need custom chrome
- `frame: false` automatically implies `toolbarStyle: "none"` — no need to set both
- Use `toolbarStyle: "unified"` (default) for standard titled windows, `"unifiedCompact"` for shorter toolbars
- Use `setVibrancy()` for macOS-native materials and transparent window configuration for overlays
- `setTrafficLightPosition()` is deprecated — use `setWindowButtonPosition()` instead

## Reference Paths

- `packages/glaze-core/src/backend/browser-window.ts`
- `packages/glaze-core/global.d.ts`
- `packages/glaze-core/src/components/styles.css`
- `packages/glaze-core/src/components/toolbar.tsx`
- `packages/main-app/renderer/main/pages/design-system/examples/browser-window-examples.tsx`
