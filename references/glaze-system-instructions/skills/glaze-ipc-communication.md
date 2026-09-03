---
name: glaze-ipc-communication
description: Patterns and best practices for secure inter-process communication in Glaze apps between frontend and backend.
---

# Glaze IPC Communication

This skill guides you in implementing secure, type-safe IPC communication in Glaze apps.

## Security Model (Electron-style)

Glaze follows Electron's security best practices with **context isolation**:

1. **Preload Script** (`renderer/preload.ts`): The ONLY place that imports `ipcRenderer`
2. **contextBridge**: Exposes a controlled API to the renderer via `window.glazeAPI`
3. **Renderer Code**: Can ONLY access `window.glazeAPI` - never imports ipcRenderer directly

This prevents renderer code from having unrestricted IPC access.

---

## CRITICAL: Secure Defaults - Minimal API Surface

By default, only **SAFE** APIs are exposed to prevent XSS, compromised npm packages, or malicious iframes from accessing sensitive system resources:

**Exposed by Default (SAFE):**

- `dialog.*` - Requires explicit user interaction with native UI
- `shell.beep` - Just plays a system sound
- `glaze.ipc.*` - Your custom backend handlers (you control what's exposed)

**NOT Exposed by Default (SENSITIVE):**

- `clipboard.*` - Data theft risk via XSS
- `shell.openExternal` - Phishing/malware download risk
- `shell.openPath` - Arbitrary file execution risk
- `file.read` - Arbitrary file reading risk
- `screen.*` - Fingerprinting concern

> **Why?** If arbitrary web content loads in your renderer (via XSS vulnerability, compromised npm package, or malicious iframe), it could access any API exposed to `window.glazeAPI`. Minimal defaults protect users even if your app has vulnerabilities.

---

## Enabling Sensitive APIs (When Needed)

If your app needs sensitive APIs, **uncomment them in `renderer/preload.ts`**:

```typescript
// renderer/preload.ts
const glazeAPI = {
  dialog: {
    /* safe - always exposed */
  },
  shell: {
    beep: () => ipcRenderer.invoke("shell:beep"),

    // ⚠️ Uncomment ONLY what your app needs:
    // openExternal: (url: string) => ipcRenderer.invoke("shell:openExternal", url),
    // openPath: (path: string) => ipcRenderer.invoke("shell:openPath", path),
  },

  // ⚠️ Uncomment if your app needs clipboard access:
  // clipboard: {
  //   readText: () => ipcRenderer.invoke("clipboard:readText"),
  //   writeText: (text: string) => ipcRenderer.invoke("clipboard:writeText", text),
  // },

  glaze: {
    ipc: {
      /* always exposed */
    },
  },
};
```

Then extend the GlazeAPI types in `renderer/types.d.ts` for your custom APIs (the base types come from `@glaze/core/global.d.ts`).

---

## Backend → Frontend

**Backend (register handler):**

```typescript
// main/handlers/index.ts
ipcMain.handle("data:fetch", async (event, { id }) => {
  return { id, value: "example" };
});
```

**Frontend (call via window.glazeAPI):**

```typescript
// renderer/main/home-view.tsx
// Use window.glazeAPI - NEVER import ipcRenderer directly in renderer code

const result = await window.glazeAPI.glaze.ipc.invoke("data:fetch", { id: "123" });
```

---

## Native macOS Integration

Use `window.glazeAPI` for native operations. Only safe APIs are available by default:

```typescript
// File dialogs (Electron-compatible API) - SAFE: requires user interaction
// Open files
const openResult = await window.glazeAPI.dialog.showOpenDialog({
  title: "Select files",
  defaultPath: "~/Documents",
  filters: [
    { name: "Images", extensions: ["jpg", "png", "gif"] },
    { name: "All Files", extensions: ["*"] },
  ],
  properties: ["openFile", "multiSelections"],
});
if (!openResult.canceled) {
  console.log("Selected:", openResult.filePaths);
}

// Save file
const saveResult = await window.glazeAPI.dialog.showSaveDialog({
  title: "Save file",
  defaultPath: "~/document.txt",
  filters: [
    { name: "Text Files", extensions: ["txt"] },
    { name: "All Files", extensions: ["*"] },
  ],
});
if (!saveResult.canceled && saveResult.filePath) {
  console.log("Save to:", saveResult.filePath);
}

// System sound - SAFE
await window.glazeAPI.shell.beep();

// ⚠️ SENSITIVE - Must enable in preload.ts first:
// await window.glazeAPI.clipboard.writeText("hello");
// await window.glazeAPI.shell.openExternal("https://example.com");
```

---

## Customizing the Preload Script

To expose additional APIs, edit `renderer/preload.ts`:

```typescript
// renderer/preload.ts
import { ipcRenderer, contextBridge } from "@glaze/core/preload";

const glazeAPI = {
  // ... existing APIs ...

  // Add your custom APIs here
  myFeature: {
    doSomething: (data: string) => ipcRenderer.invoke("myFeature:doSomething", data),
  },
};

contextBridge.exposeInMainWorld("glazeAPI", glazeAPI);
```

Then extend the GlazeAPI types in `renderer/types.d.ts` for your custom APIs.

---

## Payload Size Awareness

IPC messages are serialized as JSON through the native bridge. Large payloads in polled/broadcast responses cause memory pressure and GB-level growth.

1. **Never include base64-encoded binary data in polled or broadcast responses.** Binary data multiplied by poll frequency accumulates rapidly.
2. **Separate metadata from heavy data.** Return lightweight identifiers in list responses; fetch heavy data (icons, thumbnails, file contents) on demand via a separate IPC channel.
3. **For binary data > 100 KB**, use the protocol handler instead of IPC (see `glaze-protocol-large-files` skill).

```typescript
// WRONG: heavy data in every poll (N items × large payload each → MB/s)
ipcMain.handle("items:list", async () =>
  items.map((item) => ({ name: item.name, thumbnail: await getBase64Image(item.path) })),
);

// CORRECT: lightweight metadata poll + one-time heavy fetch
ipcMain.handle("items:list", async () => items.map((item) => ({ id: item.id, name: item.name, status: item.status })));
ipcMain.handle("items:getDetail", async (_e, { id }) => ({
  thumbnail: await getCachedThumbnail(id),
}));
```

See `glaze-backend-performance` skill for complete patterns including caching and cleanup.

---

## IPC Type Safety

**CRITICAL:** Frontend/backend parameter mismatches cause silent failures. Define shared types and validate.

### Common IPC Mismatch Bug

```typescript
// Bug: Frontend sends wrong shape
// Frontend: invoke('settings:set', { posthogApiKey: apiKey })
// Backend expects: { key: string; value: unknown }
// Result: params.key is undefined, silently fails!

// Fix: Match shapes exactly
// Frontend: invoke('settings:set', { key: 'posthogApiKey', value: apiKey })
```

### Type-Safe IPC Pattern

```typescript
// main/types/ipc.ts - Define shared types
export type IPCChannels = {
  'settings:get': { params: { key: string }; result: unknown };
  'settings:set': { params: { key: string; value: unknown }; result: void };
  'notes:create': { params: { title: string; content: string }; result: Note };
};

// Backend handler must match the type exactly
'settings:set': async (params: { key: string; value: unknown }) => {
  // Frontend MUST send { key: 'apiKey', value: 'abc123' }
  // NOT { apiKey: 'abc123' } - this causes silent failures!
  await settingsService.set(params.key, params.value);
}
```

### Debugging IPC Issues

When settings or data aren't saving:

1. **Add logging to handlers** to verify params received:
   ```typescript
   'settings:set': async (params) => {
     console.log('[settings:set] Received params:', params);
     // If params.key is undefined, frontend is sending wrong shape
   }
   ```
2. **Check frontend call** matches backend expectation exactly

**Key rule:** Frontend params must match backend handler types exactly. Add logging to debug mismatches.

**CRITICAL:** Frontend/backend parameter mismatches cause silent failures.

---

## Quick Checklist

Before implementing IPC:

- [ ] Using `window.glazeAPI.glaze.ipc.invoke()` in renderer (never importing ipcRenderer)
- [ ] Handler registered with `ipcMain.handle()` in backend
- [ ] Frontend params match backend handler signature exactly
- [ ] Extended GlazeAPI types in `renderer/types.d.ts` if adding new APIs to preload
- [ ] Sensitive APIs only enabled if actually needed
- [ ] No binary/base64 data in polling or broadcast responses
- [ ] Heavy data (icons, images) fetched via separate on-demand IPC channel
