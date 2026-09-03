---
name: glaze-backend-performance
description: Use when building apps that poll system state, execute shell commands, or transfer binary/large data over IPC. Covers child_process safety, polling patterns, IPC payload optimization, in-memory caching, and macOS system integration.
---

# Glaze Backend Performance

## child_process Safety

1. **Always set `maxBuffer`** when output may exceed 1 MB (default). Use `10 * 1024 * 1024` for binary/base64 output (images, large JSON, media processing).
2. **Always set `timeout`** to prevent hung processes (e.g., `timeout: 30_000`).
3. **Prefer `execFile` over `exec`** — `execFile` passes arguments as an array (no shell interpolation, no injection risk).
4. **Use `spawn` with streaming** for unbounded output instead of buffering everything in memory.

```typescript
import { execFile } from "child_process";
import { promisify } from "util";
const execFileAsync = promisify(execFile);

// WRONG: default 1 MB maxBuffer, no timeout
const { stdout } = await execFileAsync("/usr/bin/some-cli", ["--output", "json"], {});

// CORRECT: explicit limits
const { stdout } = await execFileAsync("/usr/bin/some-cli", ["--output", "json"], {
  maxBuffer: 10 * 1024 * 1024, // 10 MB — needed for base64, image, or large JSON output
  timeout: 30_000, // 30s — prevents hung processes
});
```

Common tools that produce large output: `osascript` (JXA image data), `sips` (image conversion), `ffmpeg` (media processing), `mdls` (file metadata as JSON).

---

## Polling Patterns

1. **Prefer event-driven approaches** when the OS provides notifications (e.g., `NSWorkspace.didActivateApplicationNotification`, `FSEvents` for file changes) instead of polling.
2. **Keep poll responses lightweight** — metadata only (names, IDs, status). Never include binary data (images, thumbnails, file contents) in polled responses.
3. **Store interval IDs and clear on `before-quit`** — leaked intervals cause resource exhaustion.
4. **Choose appropriate intervals** — 1s is aggressive for most use cases; 2-5s is usually sufficient.

Copy `examples/polling-with-cleanup.ts` for a complete polling setup with lifecycle cleanup.

---

## IPC Payload Optimization

Never include binary data (base64 images, file contents) in polling or broadcast responses. Every poll cycle re-serializes and transfers the full payload — large payloads accumulate to GB-level memory usage within minutes.

**Decision tree:**

```
Is the data < 10 KB per response?
├── Yes → Include in IPC response
└── No → Is it binary/image data?
    ├── Yes → Is it < 100 KB and fetched once (not polled)?
    │   ├── Yes → Use IPC with frontend caching
    │   └── No → Use protocol handler (see glaze-protocol-large-files)
    └── No → Is it polled repeatedly?
        ├── Yes → Split: lightweight metadata in poll, heavy data on demand
        └── No → Include in IPC response
```

**Split IPC pattern:**

```typescript
// WRONG: heavy data in every poll response (N items × large payload each)
ipcMain.handle("items:list", async () => {
  return items.map((item) => ({
    name: item.name,
    thumbnail: await getBase64Image(item.path), // heavy!
  }));
});

// CORRECT: lightweight poll + one-time heavy fetch
ipcMain.handle("items:list", async () => {
  return items.map((item) => ({ id: item.id, name: item.name, status: item.status }));
});

ipcMain.handle("items:getDetail", async (_event, { id }) => {
  return { thumbnail: await getCachedThumbnail(id) }; // fetched once, cached
});
```

This applies to any list+detail pattern: app icons, file thumbnails, preview images, processed data, etc.

---

## In-Memory Caching

1. **All caches must be bounded** — set a max entry count and/or max byte size.
2. **Add TTL** (time-to-live) for entries that become stale.
3. **Clean up on `before-quit`** to release memory before shutdown.
4. **Handle failed fetches** — don't permanently cache empty/error results; add a retry mechanism or short TTL for failures.

Copy `examples/bounded-cache.ts` for a reusable `BoundedCache<T>` class.

---

## macOS System Integration

These patterns apply when interacting with macOS system APIs via `osascript`, `lsappinfo`, `mdls`, `sips`, etc. The same principles (maxBuffer, timeout, caching) apply to any CLI-based system integration.

### App Icon Extraction

**Always use `NSWorkspace.shared.icon(forFile:)` via JXA** (`osascript -l JavaScript`). This works for all icon formats:

- `.icns` files (`CFBundleIconFile`)
- Asset catalog icons (`CFBundleIconName`) — Calendar, Maps, etc.
- Apps with no explicit icon config

**Never rely on `CFBundleIconFile` alone** — it fails silently for asset catalog apps. `defaults read .../Info CFBundleIconFile` returns an error for Calendar, Maps, and other system apps.

Copy `examples/macos-app-icon.ts` for a complete icon extraction function with proper maxBuffer, timeout, and error handling.

**Caveat: `setSize` vs true downsampling.** `icon.setSize({width: 64, height: 64})` only sets the _logical_ size — the underlying bitmap representations may still be high-DPI and large. If icons are still too large in bytes, draw into a new `NSBitmapImageRep` at exact pixel dimensions to force true downsampling. For very large icons, consider writing to disk and serving via protocol handler (see `glaze-protocol-large-files`) instead of base64 over IPC.

### Running / Active Apps

- **`lsappinfo list` ASN-based sorting reflects launch order, not activation order.** Sorting by ASN only changes when a new app is launched, not when an existing app comes to the foreground.
- To track activation order, use `lsappinfo front` (lightweight poll) or `NSWorkspace.didActivateApplicationNotification` (event-driven).
- To bring an app to the foreground: `open -b <bundleId>`.

### General macOS Tips

- **Verify CLI output assumptions** — system tools like `defaults read`, `mdls`, `lsappinfo` may return errors or unexpected formats for certain apps or files. Always handle missing/malformed output gracefully.
- **Prefer JXA (`osascript -l JavaScript`) for Cocoa APIs** — more capable than shell tools for accessing `NSWorkspace`, `NSImage`, `NSFileManager`, etc.

---

## Gotchas

| Mistake | Consequence | Fix |
| --- | --- | --- |
| Default `maxBuffer` with large CLI output | `ERR_CHILD_PROCESS_STDIO_MAXBUFFER` crash | Set `maxBuffer: 10 * 1024 * 1024` |
| No `timeout` on child_process calls | Hung process consumes resources indefinitely | Set `timeout: 30_000` |
| Heavy data (images, files) in polling responses | GB-level memory growth within minutes | Split: lightweight metadata poll + on-demand detail fetch |
| `CFBundleIconFile` for macOS app icons | Fails for asset catalog apps (Calendar, Maps) | Use `NSWorkspace.iconForFile()` via JXA |
| Assuming CLI output format is stable | Silent failures for some inputs (e.g., `defaults read` missing keys) | Validate output, handle errors gracefully |
| Unbounded in-memory cache (no max size, no TTL) | Memory grows without limit over app lifetime | Use bounded cache with max entries + TTL |

---

## Quick Checklist

- [ ] child_process calls have explicit `maxBuffer` (>1 MB if output is binary/base64)
- [ ] child_process calls have explicit `timeout`
- [ ] Using `execFile` instead of `exec` where possible
- [ ] All `setInterval` calls have corresponding cleanup in `before-quit`
- [ ] Poll responses contain only lightweight metadata (no binary data)
- [ ] Heavy data (images, files, processed output) fetched on-demand via separate IPC channel
- [ ] Binary data > 100 KB uses protocol handler instead of IPC
- [ ] In-memory caches are bounded (max entries + TTL)
- [ ] CLI output is validated (handle missing keys, unexpected formats, errors)
- [ ] If extracting macOS app icons, uses `NSWorkspace.iconForFile()` (not `CFBundleIconFile`)

---

## Related Skills

- `glaze-protocol-large-files` — For binary data > 100 KB, use protocol handlers instead of IPC
- `glaze-cli-dependencies` — For installing and checking external CLI tools
- `glaze-ipc-communication` — For IPC channel setup and security model
- `glaze-app-lifecycle` — For cleanup patterns on `before-quit`
