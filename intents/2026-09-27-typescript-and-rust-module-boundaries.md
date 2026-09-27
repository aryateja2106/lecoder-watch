---
status: draft
owner: Arya
source: conversation
date: 2026-09-27
---

# Intent: Clear module boundaries, so TypeScript and Rust pieces can live together without breaking anything

## Problem

In my words: bring TypeScript and Rust features in, and "figure out how to break down the
modules, how to make them compatible."

Today the product is mostly one language on the machine side. The daemon (`meshd`) is
TypeScript run by Bun, one file per capability under `install/payload/meshd/`, and the `mesh`
command line is one Bun script (`install/payload/bin/mesh`). There is no Rust in the repository
at all (`git ls-files '*.rs'` returns nothing). I do not have a written rule for where a new
language may go, how it talks to the rest, or how it gets installed on every machine.

One concrete example of the pattern that already works: moving the Mac's pointer is done by a
separate Swift program, `install/payload/bin/mesh-input.swift`. The daemon starts it as its own
process and sends it one line of text per command (`install/payload/meshd/input.ts`). If that
helper crashes, the daemon keeps running and my phone keeps its connection. The risky
alternative, loading native code inside the daemon itself, would mean one bug takes every
machine offline for every phone at once.

The honest counterweight: nothing in the product has been measured as too slow. The session
history run recorded storing a 139 MB transcript in 1.6 seconds, appending to it in 65 ms, and
the daemon peaking at 105 MB of memory (`docs/factory/runs/2026-09-23T070000Z-session-snapshots.md`). So the question is
less "what should be rewritten in Rust" and more "what is the rule, so that when Rust comes it
fits cleanly."

## Proposed outcome

- There is one short, written rule that says where each language lives, how the pieces talk to
  each other, and how compatibility between them is checked, and every agent follows it.
- Any future Rust piece can be added or removed without the phone, the watch or an existing
  install noticing, other than gaining a feature.
- The product still installs with one command and uninstalls with one command on every machine
  in my fleet, whatever languages are inside.
- There is still one version number for the whole thing, and a mismatch is caught automatically.
- The first Rust piece, if any, is chosen for a reason I named (learning, a customer feature, or
  a measured slowdown), not because Rust is available.
- I understand the boundary well enough to explain it to a client.

## Affected users and systems

The daemon (`meshd`) on every machine, the `mesh` command line, the installer and release
packaging (`scripts/package-mesh-install.sh`, `install/install.sh`), the build and check setup
(CI and the self-checks), and every machine in the fleet (Mac, Pi and Jetson on Linux arm64,
possibly others). The iPhone and watch apps only see new capabilities, never a language.

## Constraints

- "Reviewable in one sitting" (`ROADMAP.md`, section "Stance"): the daemon stays a
  dependency-light Bun + TypeScript program; one capability is one module plus a two-line change
  to the entry file (`docs/product/PRODUCT.md` §11 rule 4).
- There is exactly one shipping copy of the daemon (`AGENTS.md` rule 4); a Rust helper must be a
  different program, not a second daemon.
- The install contract (`docs/product/PRODUCT.md` §3): everything under `~/.mesh`, no `sudo`, no
  global npm, one command removes it.
- The daemon stays the only thing that holds the token and decides who may do what; no helper
  gets its own network door.
- The self-checks must stay green on machines and CI runners that have no Rust toolchain
  installed (whether the Pi, the Jetson and CI have one is unverified).
- Retired names (`lesearch` for the old Rust control plane, `lecoder`) are not reused for new
  programs (`docs/product/PRODUCT.md` §2).
- Revenue first in 2026: every new toolchain and release step is ongoing cost for a solo founder.

## Open questions

1. Why Rust: to learn it, because a specific feature needs it, or because you expect speed
   problems later? If none applies yet, is "the rule is written, no Rust until there is a
   reason" an acceptable outcome?
2. Is there a feature in your plans that you already picture in Rust? Name it.
3. Which machines must run a Rust piece: Mac (Apple silicon), Pi and Jetson (Linux arm64)? Any
   Intel Mac or x86 Linux box?
4. One download with every platform's build inside (simpler, a few MB bigger), or one download
   per platform?
5. Should the rule also cover the Swift apps, and the `mesh-kb` helper that is written in Python?
6. The 2026-09-22 platform ADR (`docs/adr-2026-09-22-platform-shape.md`, section 2) proposes an
   opt-in `mesh vnc enable`, while the roadmap lists VNC as a non-goal. Which one wins? (Found
   while reading for this intent.)
