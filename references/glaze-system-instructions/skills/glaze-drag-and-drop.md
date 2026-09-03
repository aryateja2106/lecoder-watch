---
name: glaze-drag-and-drop
description: Implement drag-and-drop workflows in Glaze apps, including dropping files from Finder into the app, dragging exported files from the app to Finder, and in-app drag/reorder interactions. Use this when building drop zones, drag handles, file import/export UX, or any DnD behavior.
---

# Glaze Drag and Drop

This skill guides you in implementing drag-and-drop behavior in Glaze apps.

## Choose the Right Pattern

1. **Finder -> App (import)**: User drops files into your UI.
2. **App -> Finder (export)**: User drags generated/exported files out of your app.
3. **App -> App (internal reorder/move)**: User drags items within your own UI.

Use the smallest pattern that satisfies the feature.

---

## Pattern 1: Finder -> App (Import)

Use standard HTML5 drop handlers in the renderer.

**Important:** Use `window.glazeAPI.webUtils.getPathForFile(file)` to read a filesystem path for dropped files when available.

On current Glaze builds, this helper is executed in the **page world** so it can read the original dropped `File` without trying to serialize it across the preload bridge. Call it directly from the renderer drop handler; do not wrap dropped `File` objects in your own custom bridge/proxy layer.

```tsx
import { useCallback } from "react";

const handleDrop = useCallback((e: React.DragEvent) => {
  e.preventDefault();
  const file = e.dataTransfer.files[0];
  if (!file) return;
  const filePath = window.glazeAPI.webUtils.getPathForFile(file);

  const reader = new FileReader();
  reader.onload = (event) => {
    const content = event.target?.result as string;
    console.log("Dropped file:", file.name, filePath, content.length);
    // Update state with file.name + filePath + content
  };
  reader.readAsText(file);
}, []);
```

Path caveats:

- `window.glazeAPI.webUtils.getPathForFile(file)` returns a path for native file drops when the OS provides one.
- It returns `""` for non-file drops, non-Finder sources, or browser-only contexts.
- Path mapping depends on the host drop-path bridge plus app preload code. If either side is outdated, Finder drops may still return `""`.
- Keep file associations (`app.on("open-file")`) or native open dialog (`window.glazeAPI.dialog.showOpenDialog`) as fallback path-based flows.

Nested drop zones:

- If a child drop zone sits inside a parent drop zone and the child should own the drop, call `e.stopPropagation()` in the child `dragenter`, `dragleave`, `dragover`, and `drop` handlers.
- Without that, a single Finder drop can trigger both handlers and cause duplicate imports or accidental section creation.

---

## Pattern 2: App -> Finder (Export Files)

For true file drag-out to Finder, start drag from backend via `webContents.startDrag`. In Glaze apps, prefer direct `WebContents("main")` for the main window.

### Backend handler

```ts
import { ipcMain, WebContents, nativeImage, app } from "@glaze/core/backend";
import * as fs from "fs/promises";
import * as path from "path";

ipcMain.handle(
  "drag:startFileExport",
  async (_event, params: { fileName: string; content: string; iconPath?: string }) => {
    const webContents = new WebContents("main");

    // Create export file first (required before startDrag)
    const tempDir = await app.getPath("temp");
    const filePath = path.join(tempDir, params.fileName);
    await fs.writeFile(filePath, params.content, "utf-8");

    // Icon strategies:
    // 1) explicit icon path (if provided and exists)
    // 2) thumbnail from exported file
    // 3) empty icon (native host can provide default file icon)
    let icon;
    if (params.iconPath) {
      icon = await nativeImage.createFromPath(params.iconPath);
    } else {
      try {
        icon = await nativeImage.createThumbnailFromPath(filePath, {
          width: 64,
          height: 64,
        });
      } catch {
        icon = nativeImage.createEmpty();
      }
    }

    webContents.startDrag({
      file: filePath,
      icon,
    });
  },
);
```

### Renderer trigger

```tsx
const handleExportDrag = async (item: { name: string; content: string }) => {
  await window.glazeAPI.glaze.ipc.invoke("drag:startFileExport", {
    fileName: item.name,
    content: item.content,
  });
};

<div onMouseDown={() => handleExportDrag(item)} className="cursor-grab select-none">
  Drag to export
</div>;
```

Notes:

- For export drag, prefer `onMouseDown` (or `onPointerDown`) so backend prep starts before browser drag behavior.
- `startDrag` requires a real file path that already exists on disk.
- If you use `createFromPath`, ensure the icon file exists. Alternatives:
- `nativeImage.createThumbnailFromPath(filePath, { width: 64, height: 64 })`
- `nativeImage.createEmpty()`

---

## Pattern 3: App -> App (Internal DnD)

Use plain HTML5 DnD for reorder/move interactions.

```tsx
const onDragStart = (e: React.DragEvent, id: string) => {
  e.dataTransfer.setData("text/plain", id);
};

const onDrop = (e: React.DragEvent, targetId: string) => {
  e.preventDefault();
  const sourceId = e.dataTransfer.getData("text/plain");
  // Reorder state from sourceId -> targetId
};
```

Always call `e.preventDefault()` in `onDragOver` to allow drop.

---

## Troubleshooting

**Dropped file has no path**

- Ensure the drop came from Finder and not from an in-page drag source.
- Ensure the app was rebuilt/upgraded after SDK/runtime updates.
- Older generated apps may still have a stale `renderer/preload.ts` / built `assets/preload.js`. `/upgrade` does not automatically rewrite customized preload files.
- In migrated apps, verify `renderer/preload.ts` imports `createWebUtilsAPI` from `@glaze/core/preload`, creates `const webUtils = createWebUtilsAPI()`, and exposes `webUtils` on `window.glazeAPI`.
- Do not re-expose dropped `File` objects through another preload/native bridge. Resolve the path in the renderer with `window.glazeAPI.webUtils.getPathForFile(file)` at drop time.
- Fully restart the app process after upgrading so new preload/native code is active.
- Add fallback handling via `window.glazeAPI.dialog.showOpenDialog` or file associations.

**Drop never fires**

- Ensure `onDragOver` calls `e.preventDefault()`.

**Drag-out to Finder does nothing**

- Ensure the exported file exists on disk.
- Ensure backend handler uses `new WebContents("main")` for main window flows.
- Ensure icon creation succeeds (`createFromPath` requires an existing file).

**"No active window" error**

- Do not rely on `BrowserWindow.getAllWindows()` for the main Glaze window.
- Use `new WebContents("main")` instead.

**Need both Open With and drag/drop**

- Use this skill for DnD behavior.
- Use `glaze-file-associations` for macOS file registration and `open-file` lifecycle.

---

## Quick Checklist

- [ ] Correct pattern selected (import, export, internal)
- [ ] Renderer handles `dragover`/`drop` correctly
- [ ] No reliance on `file.path` in dropped `File`
- [ ] App/runtime snapshot is up to date (preload exposes `webUtils` via `createWebUtilsAPI`)
- [ ] Backend `startDrag` used for file export to Finder
- [ ] Path-based access goes through backend or file association flow
