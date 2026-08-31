---
name: from-recording
description: Watch a product recording or screenshots, name the surface and the problem, then route to the right Mesh skill. Use when the user attaches a video, screen recording, frames, or a path under docs/recordings/.
---

# From a recording

The recording is the brief. Do not start coding before you have watched it
and said what you saw.

## Ingest

Accept, in this order:

1. Files attached to the chat (video or images).
2. A path the user names, usually under `docs/recordings/`.
3. A live window only if they ask you to look at the running simulator
   or desktop app and a computer-use tool is actually available.

If you cannot open the file, say so and stop. Do not reconstruct the UI
from memory of `WatchViews.swift`.

## Watch

Write four lines before any other work:

```
SURFACE: watch | iPhone | desktop menu bar | landing/web | unknown
JOB ON SCREEN: what the user is trying to do
WHAT I SAW: the actual sequence, including errors, empty states, and dead controls
INTENT: review | fix | implement | unclear
```

If `INTENT` is unclear, ask once. If `SURFACE` is unknown, ask once.

## Route

Read `docs/agents/workflows.md` and take the matching row.

- Native app UI review or polish → `meshwatch-ui-taste`
- Native app implement from the recording → taste, then the smallest SwiftUI patch
- Mockup-to-SwiftUI → `claude-design-to-meshwatch-swiftui`
- Landing / `web/` → `impeccable`
- Behaviour that is a factory queue item → `factory-implement` or `factory-triage`
- Behaviour that needs a spec first → `/spec` or `/opsx:propose`

## Prove

AGENTS.md rule 1: verify by running, not by building. A green `xcodebuild`
is not evidence you fixed what the recording showed.

You cannot drive Arya's physical Watch or iPhone. If the proof is "the mic
opens" or "the banner appears on the wrist", say that and hand it back.
