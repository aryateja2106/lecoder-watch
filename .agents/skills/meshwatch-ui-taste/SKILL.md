---
name: meshwatch-ui-taste
description: Native Apple product-UI taste guard for MeshWatch. Use when the user asks to design, redesign, critique, polish, simplify, make premium, make native, or remove AI-generated blandness from MeshWatch watchOS, iOS, widget, terminal, monitoring, or agent-session screens.
---

# MeshWatch UI Taste

## Overview

Use this before changing MeshWatch UI. It compresses the useful parts of Taste Skill, Impeccable, and the linked watch resources into native SwiftUI guidance for this specific app.

Sources: https://github.com/Leonxlnx/taste-skill, https://github.com/pbakaus/impeccable, https://github.com/738/awesome-apple-watch, https://github.com/mysk-research/loupe, https://github.com/cemheren/akifkeyboard.

## Design Read

Before edits, state one line:

`Reading this as: <surface> for <user/job>, with a <design language>, leaning toward <implementation>.`

Default read for this repo: native Apple command surface for local machines and AI-agent sessions, dense but calm, terminal-literate, safety-forward.

If the read is genuinely ambiguous, ask one question. Otherwise proceed.

## Dials

Use these as defaults, not ceremony:

- Watch session UI: variance 4, motion 2, density 8.
- iPhone terminal peek: variance 4, motion 3, density 7.
- Settings/installer surfaces: variance 2, motion 1, density 7.
- Empty/onboarding states: variance 5, motion 3, density 4.

## Principles

- The watch is not a laptop. It is for glance, decide, and send a tiny intervention.
- The iPhone is the full terminal fallback. Keep the existing rmux bridge as the heavy terminal surface.
- Prefer command decks over typing: Continue, Enter, Stop, Git status, Check mesh, New pane, Reply, Voice command.
- Tier risky actions: Monitor/read-only, Send/keystroke, Danger/stop/kill.
- Use native SwiftUI controls, SF Symbols, system typography, materials, haptics, and accessibility behavior before custom drawing.
- Keep status color semantic: green working/ok, orange needs input/auth, red destructive/error, secondary idle/offline. Add at most one non-status accent.
- Do not use AI-default visuals: purple-blue glow, generic glass everywhere, nested cards, huge marketing hero type, decorative blobs, random serif emphasis, or gratuitous animation.
- Do not port custom iOS keyboards to watch. Use dictation, Scribble, presets, and a tiny key pad only when the task needs command editing.

## Screen Checklist

- Can the user tell which machine/session needs attention in one glance?
- Are destructive controls separated from everyday controls?
- Does every async surface have loading, empty, error, disabled, and stale states?
- Does text fit on small watch sizes without hiding the next action?
- Are touch targets large enough for watch use and recognizable by symbol plus short label where needed?
- Does motion explain state change rather than decorate it?
- Did the patch avoid data transport, auth, bridge, and installer code unless the user asked for behavior changes?

## Verification

For watch-only UI:

```sh
xcodebuild -project MeshWatch.xcodeproj -scheme "MeshWatch Watch App" -destination 'generic/platform=watchOS Simulator' build
```

For iPhone UI:

```sh
xcodebuild -project MeshWatch.xcodeproj -scheme "MeshWatch" -destination 'generic/platform=iOS Simulator' build
```

## Skip

Skip Lottie, ProgressiveBlurHeader, Supertonic, Impeccable hooks, and Taste web/GSAP/Tailwind rules by default. Borrow judgement, not machinery.
