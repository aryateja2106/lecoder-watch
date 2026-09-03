---
name: glaze-protocol-large-files
description: Use when building Glaze apps that need to load large files (MB+) in the renderer or stream file content without IPC bloat. Covers the Glaze protocol API (registerSchemesAsPrivileged/handle), strict registration timing, safe path handling, and renderer fetch patterns.
---

# Glaze Protocol Large Files

## Overview

Use Glaze’s Electron‑style `protocol` API to serve large files via a custom scheme and fetch them directly in the renderer. This avoids huge IPC payloads and matches Electron’s behavior for large content.

## Quick Start (Backend)

**CRITICAL timing:** register the scheme **after** IPC starts and **before** any `BrowserWindow` is created. This requires a full app restart (hot reload won’t register new schemes).

```ts
// main/index.ts
import { protocol, app, BrowserWindow } from "@glaze/core/backend";

async start() {
  await this.ipcServer.start();

  await protocol.registerSchemesAsPrivileged([{
    scheme: "glaze-file",
    privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true },
  }]);

  protocol.handle("glaze-file", (request) => {
    const url = new URL(request.url);
    const filePath = url.searchParams.get("file");
    if (!filePath) {
      return { statusCode: 400, data: "Missing file", headers: { "Content-Type": "text/plain" } };
    }
    // Return { path } for large files; Swift serves directly.
    return {
      path: path.normalize(filePath),
      headers: { "Content-Type": "text/plain; charset=utf-8" },
      statusCode: 200,
    };
  });

  app.whenReady().then(() => new BrowserWindow({ /* ... */ }));
}
```

## Renderer Usage

```ts
const url = `glaze-file://file?file=${encodeURIComponent(absPath)}`;
const text = await fetch(url).then((r) => r.text());
```

For binary data, use `response.arrayBuffer()` or `response.blob()`.

## Handler Return Types

- `{ path: string }` → **Best for large files**; Swift streams directly from disk.
- `{ data: string | Uint8Array }` → Body is sent from backend (avoid for large files).
- Full response object `{ statusCode, headers, body, bodyEncoding }`.

## Best Practices

- **Validate paths**: allowlist roots and normalize to prevent traversal.
- **Lowercase schemes** (e.g. `glaze-file`) and avoid dots/spaces.
- **Keep old content visible** until new content is ready to avoid flicker.
- **Virtualize rendering** for 1000+ lines (render only visible lines).

## Common Failures + Fixes

| Symptom | Cause | Fix |
| --- | --- | --- |
| `{"code":500}` from `registerSchemesAsPrivileged` | Scheme registered after WebView created, or host app not updated | Move registration before window creation; rebuild/relaunch host |
| `TypeError: Load failed` on fetch | Scheme not registered with WebKit | Full restart required; verify scheme is privileged |
| `glaze:protocol:handleRequest` never called | Scheme not registered natively | Confirm host includes new protocol methods |

## Debug Checklist

- Register scheme **before** any window creation.
- Quit app fully and relaunch after adding a new scheme.
- Log the error message from `registerSchemesAsPrivileged`.
- Verify handler returns `{ path }` for large files.
