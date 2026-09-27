---
name: app-brief
description: Interview-first app building. Use this whenever the user asks for an app, a tool, a tracker, a dashboard or "build me something" — BEFORE any scaffolding. It asks the few questions that decide the design, remembers the user's preferences across apps, picks native or web deliberately, and only then hands off to native-app-builder or pwa-local-app-builder. Triggers on phrases like "build me an app", "I want an app that", "make a tracker", "plan an app with me".
---

# App brief: ask first, then build once

The user is on a phone or a watch, often speaking rather than typing. They will describe a
wish, not a spec. Your job is to turn that into one clear brief with as few questions as
possible, record what you learned so the next app starts smarter, and then build exactly one
app, the right kind, once.

## 0. Read the memory first

```sh
cat ~/.mesh/app-preferences.md 2>/dev/null
mesh apps list
mesh apps config
```

- `~/.mesh/app-preferences.md` is the user's standing preferences from earlier briefs (style,
  platforms, data, what they disliked). Apply them silently; do not ask again what it already
  answers.
- `mesh apps list` is what they already built. If the request matches an existing app, offer to
  extend it instead of starting over.
- `mesh apps config` tells you whether native is possible (a Team ID and bundle prefix are set).

## 1. Ask, in ONE message, only what the memory does not answer

Keep it to at most six numbered questions, each answerable in a few words. Say they can
answer by voice. Typical set:

1. What is the one thing this app must do every day? (the core loop)
2. Who uses it: just you, or others too?
3. What must it remember, and for how long? (data)
4. Native iPhone app, or a home-screen web app? Recommend one: native when `mesh apps config`
   has a Team ID and the phone is paired; otherwise web. Say why in one line.
5. Any must-haves: widget, Live Activity, notifications, watch, Siri, iPad?
6. Look and feel: something they like, a color, light or dark?

Do not ask about tech choices (SwiftUI vs UIKit, SwiftData vs Core Data). You decide those.
If the user already answered a question in their request, do not ask it again.

Wait for the answer. Do not scaffold anything before it arrives.

## 2. Write the brief and the memory

After the answer, write two things:

- `./BRIEF.md` in the project folder: name, one-sentence purpose, core loop, data, platform
  and route, must-haves, look, and what is explicitly out of scope. Ten lines is enough.
- Append to `~/.mesh/app-preferences.md` (create it if missing) only durable preferences:
  the route they chose and why, visual taste, data-privacy stance, platforms they own,
  anything they said they disliked in an earlier app. Never store secrets. Never store the
  full transcript. Dated bullet per brief.

Confirm the brief in three lines and start building. Do not ask again.

## 3. Build exactly one app, the right kind, once

- Route native → follow `native-app-builder`. Route web → follow `pwa-local-app-builder`.
  **Never build both** unless the user explicitly asked for both.
- Do not spawn background jobs or parallel workers for the build. One session, one build,
  visible in this conversation. The user is watching from a phone and cannot see side jobs.
- Run the test suite once. If it fails, fix and run once more. Never loop tests unattended.
- When the app is installed, stop. Say what was built, where the project is, and what you
  skipped. Then ask what to change — one question at a time.

## 4. Definition of done (both routes)

- An app icon that is not the placeholder (native: `scripts/make-appicon.sh` in the
  native-app-builder skill; web: `apple-touch-icon` 180×180 and manifest icons).
- A name a person would say out loud, and a bundle id / slug derived from it.
- Empty states that say what to do first; no screen that is just blank.
- Every must-have from the brief either built or listed as skipped with a reason.
- The completion signal (`APP_READY` or `PWA_READY`) exactly once, on its own line.
