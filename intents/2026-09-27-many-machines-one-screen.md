---
status: draft
owner: Arya
source: conversation
date: 2026-09-27
---

# Intent: I run agents on all my machines and steer every one of them from one screen

## Problem

In my words: "that's our core use — connect multiple devices that I run agents on, run
sessions across them."

A lot of this already works. One daemon runs on each machine; the phone's Terminal tab lists
every machine's sessions, one section per machine (`iOS/TerminalView.swift`); every surface
reads one answer to "what needs me" (`sessionsNeedingAttention` in `Shared/Models.swift`); past
conversations on every machine can be searched and resumed (`install/payload/meshd/sessions.ts`,
`install/payload/meshd/chats.ts`); and a conversation can be handed from one agent to another
(`install/payload/meshd/handoff.ts`). What hurts is the step from "I can see them" to "I can
comfortably run many at once":

One concrete example: if I start three agents on the same project from the phone, they all work
in the same folder and can overwrite each other's files. The daemon has no option to give each
agent its own copy of the project (`docs/sdlc/references/orca.md`, "Mapping to ours"). Orca, the
open-source project I admire for shipping the core things I need, makes a separate copy (a git
worktree) per agent the centre of its design. Claude Code (`claude -w`) and Codex
(`codex --worktree`) can already do this themselves on this Mac, but nothing in our app offers
it, and whether it works when started from the phone is unverified.

Other gaps:

- The machine list shows one word per machine: "online", "last seen 5m ago", "offline", or the
  token error's own text (`Shared/Models.swift`, `statusLabel`). It never says what to do next:
  wake it, pair it again, or check Tailscale (`docs/sdlc/references/orca.md`, "What to borrow").
- There is a marker for "an agent is waiting on you", but none for "an agent finished and you
  have not looked yet", so finished work gets lost among many sessions.
- With many machines and sessions, I get overwhelmed on what to show where (see the design intent
  of the same date).

## Proposed outcome

- From the phone (and in a smaller form the watch, and one terminal on any machine) I can see
  every agent on every machine, and at a glance which ones need me, which ones finished and I
  have not looked at, and which machines are unreachable versus refusing me.
- I can start several agents on the same project, on one machine or across machines, without
  them overwriting each other's work, and without knowing git commands.
- I can pick which machine an agent runs on, based on what each machine is good for, from the
  same screen.
- I can move a conversation between machines or between agents and carry on.
- Merging what the agents did stays my decision; I can at least see what each one changed.
- A client watching the demo understands "one person, many machines, many agents" in under a
  minute.

## Affected users and systems

The iPhone app (Terminal tab, New Session sheet, Machines list), the Apple Watch app, the daemon
(`meshd`) on every machine, the `mesh` command line, and every machine in the fleet (Mac, Pi,
Jetson, Linux boxes). Me first; later CloudAGI clients who run agents on several machines.

## Constraints

- No cloud relay, no SSH setup, no account system (`ROADMAP.md`, "Non-goals"). Orca reaches the
  phone through its own cloud relay and an Orca account; we take its ideas, not that model.
  "No SSH" is our wedge against competitors.
- One answer to "what needs me": no second function that computes it differently
  (`docs/product/PRODUCT.md` §10).
- Merging agent work is always a human decision; nothing merges automatically.
- A plain session in a folder that is not a git project must keep working exactly as today.
- Gate new features on what the daemon advertises, never on version numbers, and tell the user
  in plain words what they cannot do on an older daemon (`docs/product/PRODUCT.md` §11).
- Some shared files may only be changed by one agent at a time (`AGENTS.md`, parallel-work
  rules), so this arrives in small slices.
- The watch has hard limits (no Tailscale, small screen); it shows less, not everything.

## Open questions

1. When you start an agent from the phone on a project that already has an agent running, should
   it get its own copy automatically, or only when you tick a box?
2. Do you keep the same projects on several machines (for example Mac and Jetson both have this
   repo)? If not, running "the same task on two machines" also needs a way to get the project
   onto the second machine.
3. Where should agent copies live: next to the project folder, or in one place per machine?
4. Is "finished, not looked at" the marker you want, or something else (for example "needs
   review")?
5. Should the phone ever show what an agent changed (a diff), or is that always a job for the Mac?
6. Is one Claude Code or Codex copy per agent (their own worktree option) good enough, or do you
   want our daemon to manage the copies for every agent CLI the same way?
7. One token per paired phone, so a lost phone can be cut off without re-pairing every machine:
   worth about a week now, given the revenue-first focus?
8. On home Wi-Fi without Tailscale, phone-to-machine traffic is not encrypted. Accept that and
   say "use Tailscale", or change pairing to add encryption?
9. Orca's phone app is free and in the App Store. Do we position against it publicly (watch, Mac
   control, no account, no SSH) or ignore it?
