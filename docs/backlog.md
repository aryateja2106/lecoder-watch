# What exists, what is half-built, and what is only planned

Generated on **2026-08-27** from two passes: a spoken backlog structured into issues and
graded item by item against the code, and an adversarial review of the whole application
whose findings were each re-checked by a second agent instructed to refute them
(21 of 44 survived). Grades cite file:line in the tracked issue; a claim with no citation
was graded `missing` on purpose.

The machine-readable source is [`.github/backlog.json`](../.github/backlog.json), and
`sh scripts/sync-issues.sh` turns it into GitHub issues (idempotent by title, so it is
safe to re-run after adding items).

**Read the grades honestly.** `done` requires all three of: the code exists, a user can
reach it, and a check fails if it breaks. Most of this repo's real capability sits in
`partial` — that is not pessimism, it is the distinction that has been costing days.

| Grade | Count | Means |
|---|---:|---|
| `done` | 0 | shipped, reachable from the UI, and guarded by a check |
| `partial` | 11 | some of it works — usually one platform, or the code without the surface |
| `buried` | 1 | built and working, but nothing in the UI calls it |
| `missing` | 79 | not built (for a defect: not yet fixed) |
| **total** | **91** | |

---

## Confirmed defects

Found by adversarial review on 2026-08-27; each was independently verified by a second agent told to refute it. Six more were found and already fixed.

| Severity | Area | Defect |
|---|---|---|
| `blocker` | ios | An "agent needs attention" event graded at info level raises a banner and then deletes i… |
| `high` | ios | `dragEnded()` goes through the same `inputBlocked` guard as every other input |
| `high` | shared | `fsList` percent-encodes the path with `.urlQueryAllowed` |
| `high` | install | `mesh doctor --fix` reads the flag from the wrong bag (`"fix" in flags`) |
| `high` | ci | `mesh uninstall --yes` removes only the meshd launchd job/systemd unit and leaves the `r… |
| `high` | watch | `pushClipboard` writes "copied to Mac" unconditionally |
| `high` | daemon | agentKillPane guards infra by session *name* but kills by *pane id* |
| `high` | daemon | agentSend validates that the session is addressable but never validates the `pane` target |
| `high` | install | ensure_tmux aborts the whole install whenever tmux is missing |
| `high` | daemon | readTextFile does `readFile(path)` on the whole file and only then slices it to `max` |
| `medium` | daemon | POST /agents/new answers `{ok:true |
| `medium` | install | The cmux-bridge starter hardcodes /opt/homebrew/bin/bun |
| `medium` | daemon | The entire codex-state module from the tip commit is dead code: server.ts never imports it |
| `medium` | shared | `lastError = error` keeps the error from the *last* address tried rather than the most i… |
| `medium` | daemon | agentNewPane returns `{ok:true}` unconditionally: the fallback split at line 526 has its… |
| `low` | shared | The `captureJoin` gap row describes screen-capture throughput |

## Control surface & input

Using the Mac from the wrist: keyboard, trackpad, screen, terminal.

| Grade | Area | Size | Item |
|---|---|---|---|
| `partial` | watch | M | Name the five controls on the watch Control screen |
| `partial` | watch | M | Use the watch's own gestures, with visible state for each |
| `missing` | watch | M | A dictated notification reply must land in an editable draft |
| `missing` | daemon | M | Clear agent events, one by one and all at once |
| `missing` | watch | S | Decide the future of Screen peek: keep, merge into Control, or remove |
| `missing` | watch | M | First-class /commands, bash-mode ! and file-reference @ in the terminal |
| `missing` | watch | M | Give Read mode visible pan buttons on both axes |
| `missing` | watch | S | Give the full-keyboard modifier row the same glyphs, and add fn |
| `missing` | watch | S | Insert the Mac's clipboard into a session, not just the iPhone's |
| `missing` | daemon | XL | Keep a Mac awake, controllable and capturable with the lid closed |
| `missing` | daemon | L | Lock the Mac from the wrist and unlock it by typing the password |
| `missing` | ios | M | One compose surface per session instead of four ways to send text |
| `missing` | watch | S | Snap the terminal back to the newest line after you send anything |
| `missing` | watch | M | Wake a sleeping machine from the wrist |

## Agent integration

Hearing from Claude Code and Codex, and answering them.

| Grade | Area | Size | Item |
|---|---|---|---|
| `partial` | daemon | M | Match blocked agents by their own session id, not by mux name |
| `partial` | watch | M | Wire the watch's notification actions at launch, not on first appear |
| `missing` | watch | M | Give the watch's Needs-you row Decline, Reply and Stop |
| `missing` | agents | M | Install the Codex hook the way the Claude Code hook is installed |
| `missing` | watch | M | Let the watch read /events directly instead of only via the phone |
| `missing` | agents | L | List agent sessions from their transcript stores, not just the mux |
| `missing` | daemon | M | Make mesh doctor prove the agent-alert loop, not just the daemon |
| `missing` | daemon | M | Never offer a terminal key the session cannot accept |
| `missing` | watch | L | Register the watch for its own push notifications |
| `missing` | agents | M | Say what the agent is asking permission for |
| `missing` | daemon | M | Send the control keys a TUI actually needs |
| `missing` | watch | M | Show one list of every working session across every machine |
| `missing` | daemon | M | Show what each session is doing without opening it |
| `missing` | daemon | M | Stop turn-end events from evicting the question you never answered |

## Codex auto-resume

Noticing a session stopped on its usage limit, and restarting it.

| Grade | Area | Size | Item |
|---|---|---|---|
| `partial` | ios | M | Surface the limit-reset resume that already ships but is buried |
| `buried` | agents | M | Expose Codex stopped-at-limit threads over a meshd endpoint |
| `missing` | agents | M | Arm a one-shot Codex resume that survives a daemon restart |
| `missing` | agents | M | Arm and send the same resume for Claude Code |
| `missing` | ios | S | Let the user pick and edit the phrase a resume sends |
| `missing` | agents | L | Read why a Claude Code session stopped and when it resets |
| `missing` | agents | L | Send the resume message into a stopped Codex session |
| `missing` | ios | M | Show armed resumes with a live countdown and a way to cancel |

## Distribution & packaging

How somebody else gets this onto their machine.

| Grade | Area | Size | Item |
|---|---|---|---|
| `partial` | install | S | Ship a sha256 next to every packaged release tarball |
| `partial` | ios | M | Show which option is selected in every mode control |
| `partial` | install | M | Stamp one version across the daemon, CLI and installed tree |
| `missing` | install | L | Add a Homebrew tap and formula for mesh |
| `missing` | ios | L | Add a first-run tutorial that ends in a live setup checklist |
| `missing` | install | M | Cut and publish a versioned mesh-install release in one command |
| `missing` | install | S | Make bunx and bun add -g a supported install path |
| `missing` | install | L | Publish the mesh CLI to npm as an installable package |
| `missing` | docs | M | Rewrite the remote-install doc around a real SSH-only install |
| `missing` | install | L | Sign, notarize and ship the MeshDesktop menu bar app |
| `missing` | install | S | Stop reporting VNC as a setup step anywhere |
| `missing` | watch | M | Warn when two features get mixed up instead of doing nothing |

## Capture hierarchy

Machine to display to window to region — reading a screen you can actually read.

| Grade | Area | Size | Item |
|---|---|---|---|
| `missing` | daemon | L | Add a browse lane that captures a page without the Mac's screen |
| `missing` | capture | L | Capture from a long-lived SCStream, not a process per frame |
| `missing` | ios | M | Consume the frame stream on the phone, with a polling fallback |
| `missing` | capture | M | Follow the frontmost window as it moves and changes |
| `missing` | capture | L | Make the window the default region of interest |
| `missing` | daemon | M | Offer to open the dev server an agent just started |
| `missing` | capture | L | Read text off the screen with Vision OCR |
| `missing` | ios | M | Read x-mesh-rect on iOS instead of guessing the crop from aspect |
| `missing` | capture | M | Report the Mac's windows and their frames over /windows |
| `missing` | capture | M | Send the daemon's served rect through the phone relay |
| `missing` | capture | M | Serve small text regions as PNG instead of JPEG |
| `missing` | capture | L | Stream frames over one connection instead of re-polling |
| `missing` | capture | M | Swipe between screens with a live thumbnail pager |
| `missing` | watch | M | Turn a captured region into readable text on the wrist |

## Process & release

How the project itself runs.

| Grade | Area | Size | Item |
|---|---|---|---|
| `partial` | ci | S | Check one version across app, daemon, changelog and release |
| `partial` | install | M | Make publishing a daemon release one command |
| `partial` | install | L | Ship the Mac menu bar app instead of asking people to build it |
| `missing` | docs | S | Decide what version follows the 1.0 already on TestFlight |
| `missing` | ci | M | Fail CI when a self-check skips instead of running |
| `missing` | agents | M | Make voice-note-to-issues a repeatable command |
| `missing` | docs | M | Move CHANGELOG and ROADMAP when an issue closes, and check it |
| `missing` | ci | S | Point the public repo's default branch at the code that ships |
| `missing` | install | M | Publish 0.5.0 on all three surfaces and prove a friend gets it |
| `missing` | ci | S | Push the shipping branch and get one green CI run on its tip |
| `missing` | install | M | Say from mesh doctor when a newer daemon is available |
| `missing` | docs | M | Turn this backlog into tracked issues with labels and a template |
| `missing` | docs | M | Write down what we have, what is buried, and what is planned |

---

## Sizes

`S` a sitting · `M` a day · `L` several days · `XL` needs a design decision first.

## What is deliberately not here

Support for pi, hermes, openclaw and opencode. The agent work is scoped to Claude Code
and Codex until those two are genuinely good, because every agent added before then
multiplies the same unfinished plumbing.

See [`ROADMAP.md`](../ROADMAP.md) for the order this gets done in, and
[`CHANGELOG.md`](../CHANGELOG.md) for what already shipped.
