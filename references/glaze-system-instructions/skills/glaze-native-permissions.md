---
name: glaze-native-permissions
description: Implement camera, microphone, and location permission flows in Glaze apps using systemPreferences APIs, capability manifests, and native/WebKit-safe UX. Use this when adding native capability checks, permission prompts, diagnostics, or troubleshooting repeated permission dialogs.
---

# Glaze Native Permissions

This skill guides you in implementing and debugging native permission flows in Glaze apps.

## Location Guidance

- Prefer native location API: `window.glazeAPI.location.getCurrentPosition(...)`.
- Glaze native API currently supports single-shot reads only (`getCurrentPosition`).
- If you need continuous tracking (`watchPosition` / `clearWatch`), use `navigator.geolocation`. It is acceptable that this path may show WebKit location permission UI.

## Supported APIs

### Electron-parity APIs (`window.glazeAPI.systemPreferences`)

- `getMediaAccessStatus("camera" | "microphone" | "screen")`
- `askForMediaAccess("camera" | "microphone")`
- `getAuthorizationStatus("contacts" | "calendar" | "reminders" | "location")`

These are intended to match Electron semantics. Use Electron docs as the source of truth:

- https://www.electronjs.org/docs/latest/api/system-preferences

### Glaze-specific APIs

- `window.glazeAPI.systemPreferences.requestScreenCaptureAccess()`
- `window.glazeAPI.location.getCurrentPosition(options?)`
- `window.glazeAPI.permissions.getDiagnostics()`

Location API scope note:

- Glaze native location does **not** provide `watchPosition` / `clearWatch` parity today.
- For those methods, use Web API geolocation (`navigator.geolocation.watchPosition` / `navigator.geolocation.clearWatch`).

---

## Step 1: Declare Capabilities (Required)

Permission APIs are manifest-gated in template apps. Add each used capability in `package.json`:

```json
{
  "glaze": {
    "capabilities": {
      "camera": { "usage": "Capture video" },
      "microphone": { "usage": "Capture audio input" },
      "screen": { "usage": "Request and read screen recording permission state" },
      "location": { "usage": "Read current location" }
    }
  }
}
```

If missing, calls fail with:

- `code = "GLAZE_CAPABILITY_NOT_DECLARED"`

---

## Step 2: Use Correct Prompt Flow

For camera/microphone:

1. Read status first (`getMediaAccessStatus`).
2. If `denied`/`restricted`, do not prompt repeatedly; show settings guidance.
3. If `not-determined`, call `askForMediaAccess`.
4. Only start capture (`getUserMedia`) after permission is granted.

```ts
async function ensureMediaPermission(mediaType: "camera" | "microphone") {
  const status = await window.glazeAPI.systemPreferences.getMediaAccessStatus(mediaType);
  if (status === "denied" || status === "restricted") {
    throw new Error(`${mediaType} access is denied or restricted.`);
  }
  if (status === "not-determined") {
    const granted = await window.glazeAPI.systemPreferences.askForMediaAccess(mediaType);
    if (!granted) throw new Error(`${mediaType} permission was not granted.`);
  }
}
```

For location:

1. Read status with `getAuthorizationStatus("location")`.
2. If denied/restricted, surface settings guidance.
3. Use native location API: `window.glazeAPI.location.getCurrentPosition({ enableHighAccuracy })`.

```ts
const status = await window.glazeAPI.systemPreferences.getAuthorizationStatus("location");
if (status === "denied" || status === "restricted") {
  throw new Error("Location access denied.");
}

const position = await window.glazeAPI.location.getCurrentPosition({
  enableHighAccuracy: true,
});

console.log(position.coords.latitude, position.coords.longitude, position.coords.accuracy);
```

---

## Camera/Microphone Capture Pattern

Use browser media APIs after native permission checks.

### CRITICAL: `getUserMedia` + React StrictMode Race Condition

React StrictMode double-mounts components in development. This causes a specific failure pattern:

1. First mount calls `getUserMedia` and browser starts acquiring camera/microphone.
2. StrictMode unmounts, and cleanup stops the stream or aborts in-flight setup.
3. Second mount calls `getUserMedia` again while the previous native handle is still releasing.
4. Second call fails with `AbortError: The operation was aborted`.

This is usually not a permission bug. It is a capture lifecycle race. Users often report that manual retry works.

### Required Pattern: Request ID Staleness Guard

Do not rely on a single boolean `cancelledRef` for async invalidation. Use a monotonically increasing request id:

```ts
const streamRef = React.useRef<MediaStream | null>(null);
const requestIdRef = React.useRef(0);

const stopStream = React.useCallback(() => {
  const stream = streamRef.current;
  if (!stream) return;
  for (const track of stream.getTracks()) track.stop();
  streamRef.current = null;
}, []);

const startCamera = React.useCallback(
  async (deviceId?: string, retryAttempt = 0) => {
    const thisRequest = ++requestIdRef.current;
    const isStale = () => requestIdRef.current !== thisRequest;

    stopStream();
    setState({ kind: "requesting" });

    try {
      // ... permission checks, each followed by: if (isStale()) return;
      const constraints: MediaStreamConstraints = {
        video: deviceId ? { deviceId: { exact: deviceId } } : true,
        audio: false,
      };

      const stream = await navigator.mediaDevices.getUserMedia(constraints);
      if (isStale()) {
        for (const track of stream.getTracks()) track.stop();
        return;
      }

      streamRef.current = stream;
      videoRef.current!.srcObject = stream;
      await videoRef.current!.play();
      if (isStale()) {
        stopStream();
        return;
      }

      // Transition to streaming only after playback starts.
      setState({ kind: "streaming" });
    } catch (err) {
      if (isStale()) return;
      const errorName = err instanceof DOMException ? err.name : "";

      if (errorName === "AbortError" && retryAttempt === 0) {
        // Retry once after native handle release.
        const retryRequest = thisRequest;
        setTimeout(() => {
          if (requestIdRef.current === retryRequest) {
            void startCamera(deviceId, 1);
          }
        }, 200);
        return;
      }

      // ... handle other errors
      setState({ kind: "error", message: "Unable to start camera." });
    }
  },
  [stopStream],
);

React.useEffect(() => {
  void startCamera();
  return () => {
    requestIdRef.current++;
    stopStream();
  };
}, [startCamera, stopStream]);
```

Key rules:

1. Store stream in a ref, not React state.
2. Check `isStale()` after each async step (permissions, `getUserMedia`, `video.play`).
3. Set state to `"streaming"` only after `video.play()` succeeds.
4. For `AbortError`, allow at most one delayed retry (200ms) and guard it with the same request id.
5. Cleanup should invalidate in-flight work by incrementing request id.

---

## Repeated Prompt Guidance

If users report repeated camera/microphone popups:

1. Ensure app only calls `askForMediaAccess` when status is `not-determined`.
2. Ensure native WebView media permission delegate is present in:
   - `macOS/sources/macos-app/sources/runtime/webview/WebViewController.swift`
   - `webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:)`
3. Confirm app identity is stable across launches (same bundle id/signing context), or macOS may treat launches as a new app.

Note on location:

- Prefer `window.glazeAPI.location.getCurrentPosition` over `navigator.geolocation` in Glaze apps.
- This keeps location in the native permission/runtime path instead of WebKit geolocation permission behavior.

---

## Diagnostics and Debugging

Read runtime diagnostics:

```ts
const diagnostics = await window.glazeAPI.permissions.getDiagnostics();
console.log(diagnostics);
```

Common cases:

- Missing capability manifest entry -> blocked call + diagnostic with reason.
- Status shows `granted` but capture fails -> check runtime media API errors and device availability.

---

## Quick Checklist

- [ ] `glaze.capabilities` includes all used capabilities
- [ ] `askForMediaAccess` only called for `not-determined`
- [ ] Camera/microphone streams stored in a ref (not React state)
- [ ] Camera/microphone streams are stopped on cleanup
- [ ] Async permission/capture pipeline guarded with request id staleness checks
- [ ] State transitions to `"streaming"` only after `video.play()` succeeds
- [ ] `AbortError` from `getUserMedia` has a single guarded auto-retry (200ms)
- [ ] Denied/restricted states show clear recovery guidance
- [ ] Permission diagnostics endpoint is wired for debugging
- [ ] Location uses `window.glazeAPI.location.getCurrentPosition` (not `navigator.geolocation`)
