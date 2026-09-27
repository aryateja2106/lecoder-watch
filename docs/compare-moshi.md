# LeSearch Mesh vs Moshi — the honest comparison

Read this before writing any landing copy, pricing page or "vs" post. Every Moshi fact below
was read from getmoshi.app on 2026-09-04 (pages: `/`, `/compare`, `/pricing`, `/docs/`,
`/docs/gestures`, `/docs/keyboard`). Every Mesh fact is something the repo can prove with a
check script or a screenshot. Where we do not know, the cell says so.

## Same goal, different path

Moshi, in their own words: *"a terminal built for phones, not shrunken from desktops"* and
*"a mobile terminal for long-running coding agents, shells, and tmux sessions on a machine you
already control."* Their compare page measures itself against Claude Code Remote Control,
Termius, Blink Shell, ShellFish, Happy and Kittylitter — terminal and remote-control apps.

We are not trying to be the best terminal on a phone. We are trying to be the best place to
**watch and answer coding agents, and keep what they build** — from a watch first, a phone
second — with the Mac doing the work and nothing of ours in between.

## The matrix

| Capability | Moshi (their pages) | LeSearch Mesh 0.6 (this repo) | Where we stand |
|---|---|---|---|
| Terminal on the phone | Full gesture layer: swipe to switch window/pane/session, pinch to zoom, D-pad with custom corners, chord notation (`C-b, S-t`), Cmd+K/1-9/O/N/W on hardware keyboards, Option-as-Meta, auto-hiding toolbar | A live PTY stream (rmux-bridge) with Ctrl/Shift/Alt, Esc/Tab/arrows, pane split buttons; no gestures, no chord builder | **Moshi ahead.** This is their product; ours is a view beside Chat. |
| Agent chat view | "Chat View", marked Pro and experimental | Chat reads the transcript Claude Code, Codex or cursor-agent writes: prompt, reply, thinking, tool calls with results. Free. | Even on features; ours is free, theirs is Pro. |
| Approvals from the watch | Listed as an axis on their compare page; we did not fetch their watch doc | Watch shows **Decision needed** with Allow/Deny driven by the session's real status; watch terminal, launchers, dictation | Ours is verified in this repo; theirs unverified here. |
| Secrets in agent output | Nothing found on the pages read (their security doc was not fetched) | Every outbound line redacted on the Mac (GitHub, AWS, Anthropic, OpenAI, Slack, Google, Stripe, HF, npm, JWT, Bearer, URL passwords, private keys, the daemon's own tokens) plus an exposure ledger with fingerprints, never values | **Mesh ahead** on the evidence we have. |
| Apps the agent builds | Not a Moshi feature on any page read | Interview-first brief, then a native iOS app installed to the paired iPhone, or a home-screen web app the Mac serves; skills installed for the user's agents by `mesh skills install` | **Mesh ahead.** Not their category. |
| Local-first | SSH/Mosh straight to your machine | Daemon on your machine, phone talks to it over your network, no relay; alerts still transit Apple's push servers (redacted first) | Same shape. |
| Multiplexers | tmux, Zellij, Herdr, each with its own doc and gesture bindings | rmux on macOS, tmux on Linux, cmux, herdr panes; no Zellij | Moshi broader and better documented. |
| Voice | Free on-device dictation; Pro "voice-to-terminal" | Watch dictation into a draft; phone keyboard mic; hold-to-talk with a correction step in progress | **Moshi ahead** until hold-to-talk ships. |
| Multi-machine | One machine per session (their docs) | Fleet: every paired machine on one screen, wake-on-LAN, cross-machine knowledge base | Mesh ahead. |
| Price | Free tier; Pro $9.99/mo (promo $7.99), $89.99/yr (promo $69.99), $199 lifetime; Pro on up to 3 devices | Free TestFlight beta, MIT source; no paid tier exists yet | Not comparable today. Any Mesh price must be decided, not invented. |

## What people will miss first, and what we do about it

1. **Gestures and chords.** Users who live in tmux will feel the missing swipe-to-pane and
   pinch-to-zoom within a minute. Roadmap 0.7: a gesture layer on the terminal view and a
   chord builder that reuses the daemon's existing key route. Until then the key row exists.
2. **Hold-to-talk.** On-device speech with a correction step, into the chat composer. In
   progress for 0.6.x; the watch already dictates.

## What we never claim

- "Works offline" for web apps (only over HTTPS the user owns).
- "Any agent" in Chat (Claude Code, Codex and cursor-agent have transcript readers; others
  show as terminals).
- "Encrypted" for the LAN transport (plain HTTP with a bearer token; Tailscale is the
  encryption when used).
- A Moshi price other than the one on their pricing page on the day you look.
