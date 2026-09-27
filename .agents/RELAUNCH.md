# LeSearch Mesh Relaunch Plan — 2026-06-29

Resuming after ~10 days away. Context: moved to India for good, fewer resources,
pi is offline (left behind), only the Mac + a VPS remain. Goal is to stop
procrastinating and become a **daily user** of the thing, then make it good.

## North star (the only metric that matters)

> Open my watch → see my machines → open a session → tell my agent to do
> something → watch it work. Every day. Privately, over my own tailnet.

Everything below is sequenced toward that. We do NOT build features we aren't
using yet. The procrastination loop breaks the day you use it for real.

## Positioning (vs Omnara)

Omnara archived (Feb 2026) and went **cloud + voice SaaS** (PostgreSQL backend,
accounts, app-store apps). That is the opposite of us. Our moat is the harder
thing they walked away from:
- **Local-first / private**: your own Tailscale mesh, nothing exposed publicly.
- **Multi-machine**: drive many of your own boxes, not one cloud sandbox.
- **Agent isolation**: per-Unix-user agent sandboxes (`--user`, already shipped).
We are behind on exactly one thing: **landing** (on-device + a usable UI + a site).

## Current state (verified 2026-06-29)

- Mesh: **Mac up** (meshd+bridge 200, launchd durable). **pi offline 4d**.
  **dataflow VPS on tailnet but meshd 000** (firewall/service gap, never closed).
- App: **builds green** on branch `fix/merge-widgets` (commit 76be6b5, in worktree
  `../lecoder-watch-fix-merge-widgets`) — widgets/Live-Activity merged. **NOT on
  main, NOT on any device.**
- `main` is dirty: installer work (`--user`, durability) **never committed**, plus
  uncommitted `WatchViews.swift` / `TerminalView.swift`.
- Installer + `--user` sandbox: shipped & verified, public repo LeSearch-AI/mesh-install.

## Phase 0 — Become a daily user (THIS WEEK, do not skip)

The whole point. Small, mostly done, unblocks everything.

- [ ] **P0.1 Consolidate git.** Commit the dangling installer work; merge
      `fix/merge-widgets` → main; one source of truth. (low risk, ~30min)
- [ ] **P0.2 On-device.** Xcode-beta (phone is iOS 27) + Apple-ID signing +
      cabled iPhone → app on phone & watch. THE historical blocker. Interactive.
- [ ] **P0.3 Always-on box.** Revive dataflow meshd (ufw allow on tailscale0 /
      restart user service) so there's a Linux box to drive while the pi is gone.
- [ ] **P0.4 Smoke test from the watch.** Watch → Mac session → run a command →
      see output. Record what's broken. THIS produces the real backlog.

## Phase 1 — Make daily use not painful (next, from real feedback)

Pulled from HANDOFF.md P0/P1 + whatever P0.4 surfaces.

- [ ] **P1.1 Phone terminal usable.** xterm fit/resize, touch scroll, readable.
- [ ] **P1.2 Notifications that work.** Agent waiting-for-input → push to phone/
      watch. (Omnara's killer feature; we have hooks + events plumbing already.)
- [ ] **P1.3 Watch readability.** font/real-estate pass; agent-aware output mode.
- [ ] **P1.4 Reliable sync.** phone↔watch relay promptness + visible sync state.

## Phase 2 — The differentiator (only once daily-usable)

- [ ] **P2.1 Surface `--user` sandboxes in the app** (create/list/enter an
      isolated agent box from the phone). The privacy story, made visible.
- [ ] **P2.2 Resource + token dashboard.** Per-machine mem/CPU (have `/stats`) +
      per-provider agent usage/limits (have `/usage`) → "assign task to the right
      agent" at a glance.
- [ ] **P2.3 Multi-machine session persistence** surfaced + reliable.

## Phase 3 — The "glorious website" (LAST)

- [ ] Landing page on the local-first/private angle. No point marketing a tool
      you don't use daily. Lives in the LeSearch-AI org.

## Tooling / workflow refresh (parallel, light)

- [ ] cmux update available (0.64.17) — update + re-verify socket workflow.
- [ ] MacParakeet update (voice dictation) — install.
- [ ] gjc task loop: keep tasks fully-diagnosed + assignable (this file is the
      backlog). Note gjc composer submits on modifier+Enter, not plain Enter.

## How to assign (stop procrastinating)

Each `[ ]` above is a discrete, assignable unit. Hand ONE at a time to gjc with
the diagnosis already done (like the widget-merge task that succeeded). Don't
batch; don't start Phase N+1 before Phase N is usable.
