---
status: draft
owner: Arya
source: conversation
date: 2026-09-27
---

# Intent: Security is paramount, and I can always answer "who did what, on which machine, when"

## Problem

In my words: security as paramount, with clear auditability skills for the application.

The daemon (`meshd`, the small program on each of my machines that the phone and watch talk
to) can run commands, read and write files and control the screen. Its front door is guarded
reasonably well: a long secret token compared in a way that does not leak timing
(`install/payload/meshd/auth.ts`), a check that stops web pages sneaking in, one-time pairing
codes (`install/payload/meshd/pair.ts`), and secrets masked before they leave the machine
(`install/payload/meshd/redact.ts`). What is missing is a logbook, and a habit of looking for
holes.

One concrete example: when I tap Allow on my phone, the app presses Enter in the agent's
terminal and nothing is written down anywhere (`docs/sdlc/references/openmuse.md`, "For Arya").
Nobody can answer "who approved that agent at 2 a.m.?" or "did anything read files on my Mac
last week?". A CloudAGI client who asks me that today gets no answer.

Doors already known to be open, from the 2026-09-17 security review
(`docs/review-2026-09-17.md`, rows SEC-01 to SEC-09) and today's reviews:

- SEC-03 (rated high): any program on the machine can create and claim a pairing code over
  the local connection with no credential, and receive the token.
- SEC-01: on home or office Wi-Fi the token travels in plain HTTP, because the daemon listens on
  every network interface.
- An app page an agent built could, when opened on the Mac itself, act with the daemon's own
  permissions. Found by reading the code on 2026-09-27, **not** reproduced by running it; the
  exact path is deliberately not written here (this repository is public) and goes into the
  check that ships with the fix.
- The installer downloads the program without checking a checksum or signature (a hypothesis
  from `docs/sdlc/references/security-audit-skill.md`, not yet validated).
- Typing in the phone's terminal goes through a live connection that a simple request log would
  never see, so the most common way I approve an agent could stay unlogged.

There is no recurring security scan, no baseline, and no record of which findings were checked
and dismissed and why.

## Proposed outcome

- The known open doors are closed first, cheapest and most serious first, and each one has an
  automatic check that fails if it is ever reopened.
- For every approval, every command started, every file read and every pairing attempt on each
  machine, I (or a client I show it to) can see when it happened, from which device, what was
  done and whether it was allowed, without the log ever containing the secret or the typed text
  itself.
- It is written down honestly which actions are logged and which are not.
- A repeatable security audit runs on a schedule I choose (for example after every daemon
  release). Every finding is either confirmed and fixed, or dismissed with a written reason, and
  coverage adds up from run to run.
- Findings stay private until they are fixed; a fixed class of hole becomes a permanent check.

## Affected users and systems

The daemon on every machine (Mac, Pi, Jetson, Linux boxes), the `mesh` command line, the
installer, the iPhone and Apple Watch apps (they send the approvals), the Mac menu-bar app
(it pairs locally), documentation, and the agents that run audits. Me first; later any client who
needs to see an audit trail.

## Constraints

- Local-first: the logbook and the audit results stay on my machines. No cloud service, no
  account system.
- The repository is public: unfixed findings are never committed. Security intents written here
  describe the outcome only, never how to exploit something.
- Nothing leaves a machine unredacted; no request bodies, typed text or file contents in the log.
- The logbook needs a size or age limit, because the Jetson runs 24/7.
- Changing the "programs on this machine are trusted" default is my decision
  (`docs/product/PRODUCT.md` §5.4), because pairing on a fresh machine and an existing check rely
  on it.
- Existing self-checks may not be edited by an unattended run; adding new ones is fine.
- Adding the audit skill under `.claude/skills/` touches a protected path and needs my OK.
- The first audit can only read code: Docker is installed on this Mac but not running, so there
  is no safe box to run the daemon in yet.
- Pairing and auth are one-agent-at-a-time code; changes there are slow and careful.

## Open questions

1. Should the audit trail be something I sell or show to CloudAGI clients? A file on each
   machine only, a screen on the phone, or both?
2. How long to keep the log: forever, or a cap such as 90 days?
3. Close the known doors (SEC-03, the app-page hole) before building the logbook, or in parallel?
4. Should programs running as me on the Mac keep using the daemon without the token? Should the
   first audit decide this with evidence?
5. Should the daemon stop answering on plain Wi-Fi by default (only Tailscale and the machine
   itself)? That changes how pairing works on a machine without Tailscale.
6. Is logging only "a terminal connection was opened and how many Enters were sent" acceptable
   for terminal-mode approvals, or must every approval carry a full receipt of what I was shown?
7. May the Cloudflare security-audit skill be added under `.claude/skills/`, or kept in a folder
   outside the repo next to its results?
8. Where do findings live until fixed: this Mac only, GitHub private security advisories, or a
   private repository?
9. Cadence and budget: after every daemon release, weekly, monthly, or both? How many agents per
   run?
10. May Docker Desktop be started for a second, running audit, or do we stay read-only?
11. First-run scope: the daemon, installer and terminal bridges only, or the Swift apps too?
12. One token per paired device (so a lost phone can be cut off without re-pairing everything):
    now, later, or never?
13. Is tamper-proofing the log (so even someone with the token cannot quietly edit it) worth
    doing, or only if a client asks?
