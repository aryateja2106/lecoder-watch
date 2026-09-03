---
name: glaze-file-associations
description: Register file type associations so users can open files by double-clicking them, with the app receiving the file path.
---

# Glaze File Associations

This skill guides you in implementing file type associations for Glaze apps, allowing users to open specific file types by double-clicking them in Finder.

## Overview

File associations let your app:

1. Register as a handler for specific file extensions (e.g., `.myapp`, `.project`)
2. Receive the file path when a user double-clicks a file
3. Open and process the file contents

---

## Implementation Steps

### Step 1: Configure File Associations in package.json

Add `fileAssociations` to the `appConfig` section in `.glaze-sources/package.json`:

```json
{
  "appConfig": {
    "displayName": "My App",
    "fileAssociations": [
      {
        "ext": ".myapp",
        "name": "My App Document",
        "role": "Editor"
      },
      {
        "ext": [".proj", ".project"],
        "name": "Project File",
        "contentTypes": ["com.my-company.project-file"],
        "role": "Editor"
      }
    ]
  }
}
```

**FileAssociation Properties:**

| Property | Type | Description |
| --- | --- | --- |
| `ext` | `string \| string[]` | File extension(s) with or without leading dot |
| `name` | `string` | Human-readable name shown in Finder's "Get Info" |
| `contentTypes` | `string \| string[]` | Optional explicit UTIs for `LSItemContentTypes`; use for ambiguous extensions or custom formats |
| `role` | `"Editor" \| "Viewer" \| "None"` | App's relationship to the file type |

Glaze automatically resolves many UTIs from extension at bundle-update time. You only need `contentTypes` when you want exact control.

**Role Values:**

- `Editor` - App can read and write the file type
- `Viewer` - App can only read the file type
- `None` - App doesn't handle the file type directly

---

### Step 2: Handle the `open-file` Event

Listen for the `open-file` event in your backend to receive file paths. **Important:** Handle both scenarios:

1. **App launched with file** - Frontend queries on startup
2. **File opened while app running** - Backend broadcasts to frontend

```typescript
// main/handlers/index.ts (or your handler registration file)
import { app, ipcMain } from "@glaze/core/backend";

let pendingFile: string | null = null;

// Handle files opened via double-click, Open With, or dropping onto app icon
app.on("open-file", (filePath: string) => {
  console.log("File opened:", filePath);

  // Store for frontend startup query
  pendingFile = filePath;

  // IMPORTANT: Also broadcast for when app is already running
  // This handles the race condition where frontend already queried on startup
  ipcMain.broadcast("file:opened", { filePath });
});

// Let frontend query on startup (for files that triggered app launch)
ipcMain.handle("file:getPending", async () => {
  const file = pendingFile;
  pendingFile = null; // Clear after reading
  return { filePath: file };
});
```

**Frontend Usage (handles both scenarios):**

```typescript
// renderer/main/home-view.tsx
import { useEffect } from "react";

function HomeView() {
  const handleFileOpen = (filePath: string) => {
    console.log("Opening file:", filePath);
    // Load and display the file
  };

  useEffect(() => {
    // 1. Check if app was launched with a file (startup query)
    window.glazeAPI.glaze.ipc.invoke("file:getPending").then(({ filePath }) => {
      if (filePath) {
        handleFileOpen(filePath);
      }
    });

    // 2. Listen for files opened while app is running (push notifications)
    // NOTE: For a single broadcast argument, params is that object directly
    const unsubscribe = window.glazeAPI.glaze.ipc.onNotification("file:opened", (params: unknown) => {
      const payload = params as { filePath: string };
      if (payload?.filePath) {
        handleFileOpen(payload.filePath);
      }
    });

    return () => unsubscribe();
  }, []);

  // ... rest of component
}
```

**Why both patterns are needed:**

- **Startup query (`file:getPending`)**: Handles files that triggered the app launch. The file event arrives before React mounts.
- **Push notification (`file:opened`)**: Handles files opened when the app is already running. Without this, the frontend misses events that arrive after the initial query.
- **Drag & drop**: For drag-and-drop behavior, use the dedicated `glaze-drag-and-drop` skill. File associations and drag-and-drop solve different problems.

---

### Step 3: Build and Update the Bundle

After modifying `package.json` and adding the handler:

```bash
# Build the app
glaze build
```

Then call the `mcp__Glaze__UpdateBundle` tool to apply the file associations to the app bundle:

```
Use the mcp__Glaze__UpdateBundle tool to update the bundle's Info.plist with the file associations.
No parameters needed - it automatically detects the current app.
```

The tool will:

1. Read `fileAssociations` from `.glaze-sources/package.json`
2. Close the running app
3. Update the bundle's `Info.plist` with `CFBundleDocumentTypes`
4. Re-sign the bundle
5. Restart the app

---

## Complete Example

**package.json:**

```json
{
  "name": "markdown-editor",
  "appConfig": {
    "displayName": "Markdown Editor",
    "fileAssociations": [
      {
        "ext": ".md",
        "name": "Markdown Document",
        "role": "Editor"
      },
      {
        "ext": [".markdown", ".mdown"],
        "name": "Markdown Document",
        "role": "Editor"
      }
    ]
  }
}
```

**main/handlers/file-handler.ts:**

```typescript
import { app, ipcMain } from "@glaze/core/backend";
import * as fs from "fs";

let pendingFile: string | null = null;

// Called when user opens an associated .md file from Finder
app.on("open-file", (filePath: string) => {
  console.log("[FileHandler] Received file:", filePath);
  pendingFile = filePath;

  // Broadcast for when app is already running
  ipcMain.broadcast("file:opened", { filePath });
});

ipcMain.handle("file:getPending", async () => {
  const file = pendingFile;
  pendingFile = null;
  return { filePath: file };
});

ipcMain.handle("file:load", async (event, { filePath }) => {
  const content = await fs.promises.readFile(filePath, "utf-8");
  return { content, filePath };
});
```

---

## Verification

After using `UpdateBundle`:

1. **Check Info.plist:**

   ```bash
   /usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes" \
     "path/to/App.app/Contents/Info.plist"
   ```

2. **Test file opening:**
   - Create a test file with your registered extension
   - Double-click it in Finder
   - The app should launch and receive the file path

3. **Check Finder association:**
   - Right-click your test file → "Get Info"
   - Under "Open with:", your app should be listed

---

## Troubleshooting

**File association not working:**

- Ensure `glaze build` completed successfully
- Verify `UpdateBundle` tool was called after building
- Check that the app was restarted after bundle update

**App opens but doesn't receive file:**

- Verify `app.on("open-file", ...)` handler is registered early in startup
- Check logs for the file path being received
- Ensure the handler is registered before `app.whenReady()` resolves

**Wrong app opens the file:**

- macOS caches file associations; run: `killall Finder`
- Or re-register: `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /path/to/App.app`

**Uncommon extensions (for example `.log`) don't show in "Open With":**

- Set explicit `contentTypes` in `fileAssociations` (e.g. `["public.log"]` or `["com.apple.log"]`) for ambiguous/custom types
- Re-run `glaze build`, then call `UpdateBundle` again
