# ADR 2026-09-22 — an on-device brain on the phone and the watch

**Status:** proposed (slice not started). **Decision owner:** Arya.

## What is being asked

Use the phone's and the watch's own compute for the small, frequent questions: "how much
Claude do I have left", "is anything waiting on me", "what did the Jetson finish", "start Claude
on the Pi in ~/x" — answered by a local model that calls the app's own functions, offline, in
well under a second, with privacy by construction. Later: meeting audio (Telugu/Hindi/English)
→ tasks, on the device.

## What is measured (see `adr-2026-09-22-local-brains-and-streaming-moe.md` and `intent/`)

- **Needle 2** (14 MB) on the Mac: 26/28 wrist phrases → the right daemon call with the right
  arguments in ~0.7 s, 34 MB RSS; 224 tok/s on the Pi. It ships `libneedle.a` for
  `ios-arm64`, `ios-sim-arm64`, `watchos-arm64`, `macos-arm64`, `linux-arm64`.
- **llama.cpp on watchOS is possible** (Apple-Watch-Edge-AI): `arm64_32` + `-D_DARWIN_C_SOURCE`,
  Metal off, subprocess off; a quantized 0.5–1B model streams on a Series 6. Slow, hot, and a
  generative model — the wrong tool for "call this function with these arguments".
- **Jev** is an evaluation model on the AI Gateway (cloud, 70–500 ms, needs a card): classify,
  score, yes/no. Not a generator, not on-device.
- The app already has the functions: `MeshStore` knows usage (`/usage`), sessions and status
  (`/agents`), events (`/events`), machines, and can start sessions (`/agents/new`), send keys,
  and fire power actions — the same routes `intent/mesh-tools.json` describes.

## Decision

1. **Needle is the on-device brain**, on both the iPhone and the Watch: tool calls over a clean,
   typed tool set that maps 1:1 onto `MeshStore` functions (list_sessions, usage, waiting,
   events_since, new_session, send_text/keys, power, screenshot_to_clipboard). No generative
   model on the wrist. The text answer is composed by code from the tool result ("Claude 75 %
   left, resets in 2 h 44 m") — Needle picks and fills, code speaks.
2. **Speech in stays Apple's** (`SFSpeechRecognizer` on the phone; watch dictation) until a
   Desert Ant Voz-class model is proven on-device for Telugu; Needle takes the transcript.
3. **Jev is for the daemon**, online only: event triage (actionable / noise), command risk, and
   the meeting-transcript → task extraction, gated on `AI_GATEWAY_API_KEY` and a card on file.
4. **llama.cpp on the watch is a spike, not a plan**: keep the build recipe in
   `references/reference-projects.md`; revisit when a task needs free text on the wrist.

## The first slice (what "done" looks like)

- `Shared/Brain/` : a Swift wrapper over `libneedle.a` (ios-arm64 + sim + watchos-arm64 as an
  xcframework), `tools.json` generated from one Swift catalogue (so the daemon's
  `intent/mesh-tools.json` and the app's never drift), and a `Brain.ask(_ text:) async ->
  Answer` that runs the picked tool against `MeshStore` and formats the result.
- Phone: a search-style bar on the Machines tab ("ask") and the mic; Watch: a "Ask" row on the
  root screen using dictation. Every answer shows which tool ran (no hidden actions); anything
  that changes state (new session, power) confirms first, like today's power list.
- Check: `scripts/check-brain-tools.sh` proves the two tool catalogues are identical and that
  `intent/cases.jsonl` still scores ≥ 24/28 through the app's catalogue; `check-intent.sh`
  stays the floor. A sim run asks the three questions above and reads the tool that ran.
- Size budget: +15 MB app, < 60 MB RSS during a query, < 1 s on an iPhone 15, < 2 s on a
  Series 9 — measured before merge, refused otherwise.

## Consequences

- Needle's ceiling is argument extraction (2/28 misses were arguments); a fine-tune on our
  phrases is the follow-up, not a redesign.
- The watch gets a brain without a network hop only for questions the phone's snapshot can
  answer; a fresh `/usage` still needs a machine in reach.
- None of this ships before the Oct 1 launch unless the first slice lands green in a day;
  the honest order is approvals → terminal → apps → brain.
