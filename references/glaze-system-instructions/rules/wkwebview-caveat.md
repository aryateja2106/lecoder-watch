
# Known WKWebView Rendering Caveat

When animating container `height` inside a glass surface (`bg-glass`), avoid `backdrop-filter` on nested controls (especially `Button` `variant="filled"` which uses `backdrop-blur-xs` by default in `@glaze/core`).

- Symptom: footer controls can appear duplicated/ghosted for a frame during transitions.
- Root cause: WebKit compositor artifact from `backdrop-filter` + clipping + animated height.
- Recommended mitigation:
  - Prefer `backdrop-blur-none` on footer buttons within animated glass composers.
  - Use strong clipping/paint containment on the shell (`overflow-hidden`, `isolate`, `contain: paint`).
  - Keep footer slot stable (fixed/min height) while content height animates.
