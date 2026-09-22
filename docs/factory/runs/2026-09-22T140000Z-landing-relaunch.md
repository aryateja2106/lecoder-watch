---
run_id: 2026-09-22T140000Z-landing-relaunch
stage: implement
started_at: 2026-09-22T14:00:00Z
finished_at: 2026-09-22T16:00:00Z
status: succeeded
issue: none (Arya's launch-polish brief, in-session)
pull_request: https://github.com/aryateja2106/lecoder-watch/pull/133
gate_level: fast
gate_status: quoted below
verifier: the page was read end to end in a browser at desktop and phone width; every asset fetched 200 from the deployed origin
human_required: true — the TestFlight upload still gates what a visitor can install (BLOCKED.md)
---

# Landing relaunch — the real 0.8 UI, watch first, 432 words

Arya's brief: capture the new UI, keep it dark, show the watch driving a machine's
screen ("currently our key selling point"), cut the text, and make the page sell.

## What the page is now

One hero and four sections, each a single idea with a single real capture:

| Section | Claim | Media |
|---|---|---|
| Hero | See your machine on your watch. And drive it. | `video/wrist.mp4` — the watch's Control screen, a Pi's desktop live on it |
| On your wrist | The screen of any machine you own | `shots/watch-control.png` |
| Agent menus | It asks. You tap. It keeps going. | `shots/iphone-choose.png` — a real trust prompt + Choose card |
| New in 0.8 | The real pane, on the phone | `shots/iphone-terminal.png` |
| Mac and Linux | The whole desktop, from the phone | `video/pi-desktop.mp4` |

432 words, down from 3,363. Page weight 2.9 MB including both clips.

## How the copy was written

A four-angle panel, run as a workflow: four marketers wrote a full deck each from a
different spine (the dead time, reach, wrist-first, operator trust); three judges scored
every deck on credibility, clarity and differentiation; an editor built the final deck on
the winner and grafted the lines the panel named. Watch-first won 9/10 on two lenses.

Two claims the panel killed stay killed, and they are worth remembering:

- **"Nothing else in this category reaches the wrist"** — unverifiable superlative about
  unnamed competitors. A reader can disprove it in one search; then nothing else on the
  page is trusted either.
- **"No cloud in between"** — false as written, because the wrist buzz is an Apple push.
  The true and cheaper line is *no server of ours in between*.

The cut list is in the workflow result and in the commit: the three-panel narration of a
loop the first screenshot already shows, the six-card watch grid, the local-first
comparison table, a changelog pasted mid-page, the argument with an absent competitor,
the second printing of the install command, and every repeat of "no signup / no account"
after the first.

## How the media was captured

All of it is the current build against the live fleet, in dark mode, on the paired
iOS27-repro + Watch27-test simulators (the pair matters: the watch only has machines
because its paired phone does).

1. `xcrun simctl ui <phone> appearance dark`; install the build; open
   `$(mesh pair --json | jq -r .url)` and tap Pair — the fleet (mac, pi, jetson) is
   adopted in one step, which is itself the `iphone-paired.png` shot.
2. Machines → the Pi's live thumbnail → Screen & control; Terminal → `pi-claude` → Chat,
   then the Terminal segment for the native terminal.
3. A real approval: `mesh new demo-approve --cmd claude` on the Mac, then a prompt that
   makes Claude Code ask. The trust prompt fires no hook, so it appears as a Choose card
   read off the pane — which is exactly the claim the section makes.
4. The watch: relaunch, scroll to Control pi, zoom in. `simctl io recordVideo` while
   driving, then `ffmpeg` to trim, crop and compress (the Pi clip is cropped to the
   screen region because a landscape desktop inside a portrait phone is mostly black).

`scripts/product-shots.sh` regenerates the still set; the two clips are hand-driven and
recorded, and the commands are in the commit message.

## Traps

- A capture run leaves the simulator **paired**, and a paired, polling app never reaches
  XCUITest's "wait for idle" — `check-ios-smoke`'s first test hung ten minutes after one.
  `product-shots.sh` now uninstalls the app when it finishes.
- A clip trimmed from the wrong second is black: start each one on a frame with content
  and check with `ffmpeg -ss … -frames:v 1` before shipping it.
- Give every `<video>` an explicit `aspect-ratio` or the page reflows as each one loads.
- The preview pane's screenshots do not always composite a playing video; check
  `readyState`/`paused` in the console rather than believing a black rectangle.

## Gate

```
FACTORY_GATES: level=fast status=GREEN passed=2 failed=0 failing=none skipped=none misconfigured=none
```

`check-brand`, `check-links` and `check-web-docs` all green; deployed to the
`lesearch-website` Vercel project and verified on https://lesearch.ai (page, both clips
and every still answer 200).
