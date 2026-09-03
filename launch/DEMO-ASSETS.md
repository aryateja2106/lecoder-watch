# Demo asset inventory

Scope: repository-local evidence only, checked 2026-08-31. These are inputs for a
90–120 second launch/demo cut, not a claim that every pictured flow is currently
shippable.

## Strongest product proof

| Asset | What it can credibly prove | Caveat / redaction |
|---|---|---|
| `/Users/aryateja/Projects/lecoder-watch/docs/screenshots/iphone-69_01-machines.png` | iPhone machine list / multi-machine control surface | 331×720 capture; verify visible host names and status are safe before publishing |
| `/Users/aryateja/Projects/lecoder-watch/docs/screenshots/iphone-69_03-terminal-live.png` | iPhone live terminal/agent output | Read every line; terminal output can expose paths, prompts, repository names, URLs, or secrets |
| `/Users/aryateja/Projects/lecoder-watch/docs/screenshots/iphone-69_07-remote.png` | iPhone remote-control surface | Good value-prop proof; do not imply the pictured action is available on every machine without a live check |
| `/Users/aryateja/Projects/lecoder-watch/docs/screenshots/watch-ultra_02-machines.png` | Apple Watch machine overview | 422×514; use as a quick wrist-context beat, not detailed UI evidence |
| `/Users/aryateja/Projects/lecoder-watch/docs/screenshots/watch-ultra_04-terminal.png` | Apple Watch terminal/agent monitoring | Text legibility is limited at this resolution; pair with narration and a live simulator capture |
| `/Users/aryateja/Projects/lecoder-watch/reference-video/ScreenRecording_08-29-2026 17-15-42_1.MP4` | End-to-end screen recording source, 1180×2556, 133.7s | Already exceeds target duration; trim to 90–120s. It visibly includes a VNC/Linux desktop, browser auth/code material, terminal text, and keyboard/input UI: treat as sensitive until reviewed frame-by-frame |

The same five screenshots are duplicated under
`/Users/aryateja/Projects/lecoder-watch/web/shots/` for landing-page use. Prefer
the `docs/screenshots/` copies as the canonical evidence set; do not create another
copy during demo production.

## Supporting / concept material

`/Users/aryateja/Projects/lecoder-watch/Reference-images/IMG_8638.png` through
`IMG_8649.png` and `VNC-UI.png` through `VNC-UI-4.png` are 1179×2556 reference
screens. They are useful for studying interaction ideas and remote/VNC layouts,
but should not be presented as the current LeSearch product unless each screen is
re-captured from the current build. At least one VNC reference visibly contains a
Google Antigravity authorization page/code, browser content, a Linux desktop, and
terminal/system-monitor output: assume all Reference-images are unpublishable
until manually redacted or replaced.

`/Users/aryateja/Projects/lecoder-watch/static-landing.png` and
`/Users/aryateja/Projects/lecoder-watch/next-landing.png` are landing-page
snapshots/prototypes, not demo proof. They may help compare visual direction.

## Brand assets currently present

- `/Users/aryateja/Projects/lecoder-watch/Lesearch Logo.svg`: black line-art mark,
  square viewBox; usable as a source logo, but needs light/dark and small-size
  export checks.
- `/Users/aryateja/Projects/lecoder-watch/web/logo.svg`: web logo variant used by
  the legacy landing page.
- `/Users/aryateja/Projects/lecoder-watch/Lesearch-Logo-light.png`: 150×150 light
  raster mark.
- `/Users/aryateja/Projects/lecoder-watch/web/appicon.png` and
  `/Users/aryateja/Projects/lecoder-watch/Assets.xcassets/AppIcon.appiconset/icon-1024.png`:
  app-icon inputs.

There is no repository-local finished typography spec, illustration library,
device mockup pack, or coherent brand-token file in this inventory. The current
web page establishes a dark monochrome system with JetBrains Mono and green/red
action accents, but that is an implementation direction, not a locked brand kit.

## Minimum capture gaps for the demo

1. Re-capture one current, sanitized flow: Mac daemon/agent running → iPhone sees
   the machine → agent asks for intervention → user responds → updated output.
2. Capture the same moment on Apple Watch, with readable text and no personal host,
   repository, URL, token, or notification data.
3. Add one clean multi-machine frame (two or more clearly named fictional machines)
   and one long-running-agent/status frame; current assets suggest these but do not
   prove a synchronized live sequence.
4. Replace or crop the 133.7s recording into a 90–120s edit with a visible product
   story, not a generic VNC/desktop tour. Keep the raw file private.
5. Produce only the minimum brand exports needed for the cut: monochrome logo on
   dark/light backgrounds, app icon, and one consistent device-frame treatment.
   Do not block the demo on a full illustration or 3D asset library.

## Suggested 100-second evidence order

`0–10s` problem/context → `10–25s` Mac agent running → `25–45s` iPhone machine
list and live terminal → `45–65s` intervention/approval moment → `65–80s` Watch
response → `80–92s` multi-device/multi-machine recap → `92–100s` beta CTA.

This order is a storyboard, not evidence that the current recording contains all
beats. The missing beats above must be captured against the current build before
the video is described as a product demo.
