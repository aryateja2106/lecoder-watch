# Factory run plan — 0.6 "Real-time"

Written 2026-08-29, from the owner's brief: *"real-time connectivity, keyboard-and-laptop
experience from the phone and watch — otherwise it's not natural"*, terminal legibility in
a zoomed view, voice/text input with a human-in-the-loop correction step, one-finger watch
targets, and an app polished enough to pitch as a **multi-agent, multi-machine control
plane** (see `docs/PRODUCT-SPEC-V1.md` §2.1 for why "control plane", not "orchestration
platform", until #114 ships routing).

This file is the plan a human reviews once; the *queue* is GitHub issues carrying
`factory:*` labels (`docs/factory/GITHUB.md`). Every item below respects
`docs/factory/CHARTER.md` — items in load-bearing paths are marked NEEDS-SPEC and carry
their spec here, so a run can claim them without inventing intent.

## Why these items and not others

The 0.5.x line proved the plumbing: pairing, tombstones, chords, QR, herdr enumeration,
release gates. What separates us from "natural" is **latency and feedback** — measured,
not vibed: session creation spends 943ms of its 989ms in a hardcoded `setTimeout(900)`
(issue #117), terminal output arrives on a 2s poll, and a sent keystroke waits 350ms
before the screen moves. Every item below attacks lag, legibility, or input fidelity.
Voice (#110), desktop (#111), shared memory (#112), isolation (#113) and the agent layer
(#114) stay parked — they are new surface, and 0.6 is the release that makes the existing
surface feel real-time.

## The queue, in claim order

Legend: **A** = automatable under the charter as-is. **S** = NEEDS-SPEC (spec below is
that spec; the run still forces `deep` gates and a human read via the load-bearing rule).
**H** = human-gated (device proof or release).

**Progress note, 2026-08-29 afternoon:** items 2, 4, 5, 6 and 8 landed in the
interactive session ahead of the factory (commits `d6cf928`, and the dedupe/polish
commits following it) — do not re-claim them; item 3 was examined and deliberately
deferred (the 500ms interactive cadence covers most of the perceived gap, and a pending
echo layer is speculative until a device test says otherwise). Items 1, 7, 9, 10 remain.

| # | Item | Class | Gate | Spec / acceptance |
|---|------|-------|------|-------------------|
| 1 | **#117: replace `setTimeout(900)` in `/agents/new`** with readiness polling | S | deep | Poll the new pane for a live prompt (or first output byte) every 50ms, cap 1200ms, then send `initialText`. Acceptance: a `time curl /agents/new` with initialText lands under 250ms against a warm shell; the existing behavior is the fallback at cap. New `scripts/check-agent-new-latency.sh` asserts no literal `setTimeout(900` remains. |
| 2 | **Adaptive terminal poll**: 500ms while a peek screen is frontmost and the user interacted in the last 10s, 2s otherwise, pause when backgrounded | S | deep | iOS `SessionPeekScreen` + watch terminal. No daemon change. Acceptance: keystroke→screen echo under 700ms on the sim against a local daemon; battery guard: the fast cadence dies 10s after the last touch. |
| 3 | **Optimistic key echo**: a sent key renders immediately in a pending style, reconciled by the next poll | S | full | Client-only. Acceptance: Enter/arrows feel instant on the sim; a refused key (the daemon's `error` string) replaces the optimistic echo with the refusal, which `check-herdr-sessions.sh` already proves reaches the client. |
| 4 | **Duplicate-machine merge**: two Machines rows answering with the same `/health` `mac` address are one machine | S | deep | Seen live 2026-08-29: "arya-macbook-pro" and "mac", same daemon, same sessions, two rows. Merge at snapshot-build time keyed on the health payload's `mac` field; keep the row whose entry the user paired most recently, fold the other's bridge/VNC config in. New check: `scripts/check-machine-dedupe.swift` with two fixture hosts sharing a mac. |
| 5 | **Peek-screen polish**: left-edge clipping of the "updated" timestamp; the cryptic `0.0 2.1.250` pane chip becomes labeled stats | A | full | Single-file `iOS/TerminalView.swift` view work, no model change. Sim screenshots are the evidence. |
| 6 | **Watch terminal zoom pass**: reader-mode line height, largest-text chip audit, every tap target ≥ `WatchTouch.min*` | A | full | Single-file `Watch/WatchViews.swift`. Proof: watch-sim screenshots at both extremes of text size; no target under the minimum. |
| 7 | **Dictation correction loop**: text arriving via the watch Reply flow or iOS dictation shows in the compose field for one confirming tap; nothing dictated ever sends itself | S | full | The compose sheets already exist — the change is removing any auto-send on dictation end. Acceptance: dictated text with a recognition error can be edited before send, on sim, with the software keyboard standing in for the mic. |
| 8 | **iOS 18.4 deprecation**: `NSURLErrorFailingURLStringErrorKey` → `NSURLErrorFailingURLErrorKey` (`iOS/PairMachineView.swift:247`) | A | fast | Warning count drops by two; behavior identical. |
| 9 | **Live Activity end-to-end proof** on the physical iPhone | H | — | After the 0.5.4 daemon deploy: trigger a `needs-input` event with the app killed; the card must start AND update (`/push` must show `laUpdateTokens ≥ 1` after one foreground). This is the verification of the 2026-08-29 token fix; only Arya's device can prove it. |
| 10 | **0.5.4 fleet deploy + mesh-install publish** | H | — | `sh scripts/release-mesh-install.sh --publish` after this branch merges. NEVER automated (charter). |

## Trigger runbook (three harnesses, one queue)

Each harness runs the same loop: claim one issue by its `factory:ready` label, branch
deterministically, implement, run `./.claude/scripts/gates.sh <level>`, hand to
`factory-verifier`, open a **draft** PR, stop. Labels come from
`docs/factory/bootstrap-github.sh --apply` (owner, once).

Inside a herdr pane on the Mac (`herdr session attach factory`):

- **Claude Code** — `claude` in the repo root; the `.claude/skills/factory-*` skills load
  on demand. Long unattended runs: the owner has approved `--yolo`-class flags this
  session; the charter's STOP_IF still rules.
- **Codex** — `codex --sandbox workspace-write` (never
  `--dangerously-bypass-approvals-and-sandbox` outside an already-sandboxed worktree);
  reads the same `AGENTS.md`.
- **cursor-agent** — `cursor-agent -f` for approved long tasks; `.cursor/skills/factory-*`
  point at the canonical Claude skills.

One item per run, two items max awaiting review (`STOP_IF`), and the merge click is
always Arya's.

## Standing constraints the runs must not relearn

- Verify by running (AGENTS.md rule 1) — a green build proved nothing three times.
- `Shared/**` and `install/payload/meshd/**` are one wire: serialize to a single agent.
- The gate suite's word is final; quote `FACTORY_GATES:` verbatim.
- Workflow-tool worktree isolation forks from the PRIMARY checkout's branch — currently
  `main`, which predates the factory. Point it at the working branch first or stay in
  the session worktree.
