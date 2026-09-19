# Product Marketing Context

**Document version:** v1
**Last updated:** 2026-09-19

Drafted from the repo (README.md, web/index.html, ROADMAP.md, CHANGELOG.md,
docs/competitive-position.md, docs/launch-posts.md, AGENTS.md). Nothing here is invented;
anything we do not have on record is marked `[NEEDS: ...]`. Sources are listed at the end.

## Product Overview
**One-liner:** Use your Mac from your wrist. Your agents stop and ask; you answer from your
wrist.
**What it does:** A small daemon (`meshd`, Bun + TypeScript, about 3,000 lines, no
dependencies) runs on each Mac or Linux machine you own. The iPhone and Apple Watch app
talk to it directly over your own network. When a coding agent (Claude Code, Codex, or
anything that can post one curl) blocks on a question, a hook fires, your wrist buzzes with
the actual question, and one tap sends the answer into the real terminal session. The same
app gives you a real terminal on the watch, a trackpad, keyboard and live screen for the
Mac, and CPU, memory and disk for every paired machine.
**Product category:** Remote control for your own machines that understands AI coding
agents. It sits between two existing categories: agent-aware phone terminals (Moshi, Happy
Coder, Omnara) and zero-config remote desktops (Jump Desktop, Screens). Nobody else spans
both. `[NEEDS: keyword research on how people search for this; candidates: "answer Claude
Code from my phone", "tmux on Apple Watch", "control Mac from iPhone without VNC"]`
**Product type:** Native iOS + watchOS app (TestFlight beta), a Mac menu-bar app, and an
open-source daemon and CLI (`mesh`), all MIT.
**Business model:** Free while in beta. No pricing decided. The category pattern is
freemium plus annual plus lifetime (docs/competitive-position.md, August 2026): Moshi
$7.99/mo, $69.99/yr, $199 to $249 lifetime, with a discounted Founder tier at $3.99/mo or
$19.99/yr for early users. The suggested play is a permanently discounted early-supporter
SKU that converts the beta list. `[NEEDS: pricing decision]`

## Target Audience
**Target companies:** Individuals, not companies. One person, their own Mac (or a few
machines), an iPhone and an Apple Watch. Small teams later.
**Decision-makers:** The same person who installs it.
**Primary use case:** Answer a blocked coding agent without walking back to the machine.
**Jobs to be done:**
- Let me leave the room (or the house) while the agent works, and keep it moving when it
  stops to ask.
- Show me what my agents are doing across every machine I own, on my wrist, all day.
- When the agent cannot do the GUI part, let me take the Mac's screen and pointer from my
  phone and finish it myself.
**Use cases:**
- Leave the house while the machine boots; phone and watch pick it up with no ritual.
- Gym or outside: open the watch, find the session, read what the agent asked, answer it.
- One-handed approval while eating: tap Continue, or the red button that names the verb.
- Read a build streaming into the terminal on the phone; scroll it with the crown on the
  watch.
- Dictate a reply and have it typed into the real session.
- Trackpad, sticky modifiers (so ⌘⇧4 works) and a live screen view when a question is
  not enough.
- `mesh status` from any terminal: what version every box runs and whether anything is
  broken.
**Requirements (who can use it today):** iPhone on iOS 26 or later; Apple Watch on
watchOS 10 or later for the good part; at least one Mac (macOS 14+) or Linux box; a
private network the phone and machine share (the same LAN, or a VPN like Tailscale); a
multiplexer (tmux, rmux, herdr or zellij) and bun, which the installer fetches.

## Personas
| Persona | Cares about | Challenge | Value we promise |
|---------|-------------|-----------|------------------|
| Non-technical AI enthusiast (the person the product is designed for) | Using agents every day without learning networking | Every other tool wants SSH keys, port forwarding, or a VPN they do not have | Paste one command, scan a code, done; one command removes it |
| Developer who runs agents all day | Dead time while agents wait; keeping several machines busy | Walking back to the laptop; agents idle overnight | Blocked, buzz, one tap, it carries on; the whole fleet on the wrist |
| Self-hoster and privacy-minded tinkerer | Where the terminal output and source code go | Comparable tools relay sessions through their cloud | No relay, no account, a daemon short enough to read in a sitting, MIT |

## Problems & Pain Points
**Core problem:** Coding agents run for hours and then freeze on one question ("can I
force-push?", "overwrite this file?") and sit there until you walk back to the machine.
Not failing. Waiting.
**Why alternatives fall short:**
- SSH-based tools (Moshi, Blink, Termius, Prompt 3, Secure ShellFish, Teletype,
  ShadowTerm) need all four of: a reachable machine (public IP, port-forward or VPN),
  SSH keys, macOS Remote Login switched on, and knowing the machine's address. Moshi's own
  setup guide warns "skip one, and the whole setup breaks down".
- Zero-config remote desktops (Jump, Screens, RealVNC, TeamViewer) need an account and
  route access through the vendor's cloud, and none knows what an agent is.
- Existing watch apps are approval or status surfaces. Moshi's documentation says its
  watch app cannot attach to a shell or tmux, cannot show scrollback, and cannot dictate.
**What it costs them:** Twenty minutes gone per interruption; an agent that did nothing
since you left; the machine idle overnight.
**Emotional tension:** The low-grade "is it stuck?" that pulls you back to the desk, and
distrust of piping a script into your shell or sending your terminal through someone
else's server.

## Competitive Landscape
As of August 2026 (docs/competitive-position.md). State differences as facts; never call a
competitor broken.
**Direct:** Moshi (the leader: 4.7 stars, 482 ratings; iPhone, iPad, Mac, Vision, Watch;
agent inbox, Live Activities, diff viewer, on-device voice). Its watch app is an approval
and status surface, and its hook holds a WebSocket to Moshi's backend. Happy Coder (4.9,
991 ratings, MIT; QR pairing with end-to-end encryption; needs an npm install first).
Omnara ($9/mo; went cloud plus voice SaaS with accounts). Tactic Remote, ShadowTerm.
**Secondary:** Jump Desktop, Screens 5, RealVNC, TeamViewer. They connect from anywhere
with no setup, but require an account, route access control through their cloud, and have no
terminal-session or agent concept.
**Indirect:** Blink, Termius, Prompt 3, Teletype, Secure ShellFish (deep SSH clients; all
four non-developer blockers apply), and simply walking back to the laptop.
**Benchmarks worth studying:** Secure ShellFish's Files provider and Shortcuts actions;
Happy Coder's QR pairing.

## Differentiation
**Key differentiators:**
- A real terminal on the Apple Watch: crown to scroll, auto-follow at the tail, a key bar,
  full VoiceOver. No competitor has shipped this.
- Agent feed, terminal, and live Mac screen and pointer control in one session.
- One command in, one command out, no account anywhere. `mesh uninstall` shows what it
  will delete, then deletes exactly that.
- Local-first: the phone talks straight to your machine. No relay, no server of ours in
  the path.
- "Continue" is a yes, not an acknowledgement. The app reads the question and, for a
  force-push, `rm -rf`, hard reset, `DROP TABLE`, `| sh` or `sudo`, turns the button red
  and makes it name the verb.
- All of it is open source and MIT: daemon, CLI, installer, and the apps.
**How we do it differently:** Our own daemon with a minted per-machine token, pairing
that hands back every host it already knows (a fleet of four takes one code), and hooks
that post to the daemon's `/events` endpoint, so any agent or script can raise the wrist.
**Why that's better:** Nothing to configure that requires understanding networking; nothing
of yours leaves your machines; the part that runs on your machine can be read before it is
run.
**Why customers choose us:** `[NEEDS: reasons from beta testers, verbatim]`

## Objections
| Objection | Response |
|-----------|----------|
| "Does it work when I am away from home?" | Where your phone can reach the machine: the same LAN, or a VPN you already use (built against Tailscale). No relay, no hole-punching. Reaching a machine from any network is on the roadmap as a deliberate design decision, not something to fake. |
| "I am not piping a script into my shell." | The installer is one shell script and the daemon is about 3,000 lines of dependency-free TypeScript, MIT, meant to be read first. `mesh uninstall` shows exactly what it will remove and removes only that, keeping a backup of every file it edits. |
| "Where does my terminal output go?" | From the phone to your machine, directly. No relay, no account. The daemon sends one anonymized daily heartbeat (version, platform, uptime, coarse counters); `MESHD_TELEMETRY=off` silences it. The apps send nothing. |
| "How finished is this?" | A beta the author uses daily, on TestFlight. CHANGELOG.md and ROADMAP.md say exactly where it stands. |
| "Moshi's phone terminal is better." | It is, today. We do not race there. The wrist terminal and the Mac screen control are what nobody else has. |

**Anti-persona:** Someone who needs to reach their machine from any network with no VPN
today; Android or Windows phone users; anyone whose first requirement is the best phone
terminal; teams that need shared accounts and admin controls.

## Switching Dynamics
**Push:** Setup walls (SSH keys, port forwarding, Remote Login); sessions relayed through a
vendor's cloud; mandatory accounts; watch apps that only mirror notifications.
**Pull:** Buzz, tap, it carries on. One command in and out. Nothing of yours leaves your
machines, and you can read every line that runs there.
**Habit:** Walking back to the laptop. An SSH client already installed. "I will just wait."
**Anxiety:** Beta rough edges; push delivery to a cold device not yet proven end to end;
piping a script into a shell; "what if the project disappears?" (the daemon keeps running,
the source stays public, and it is a plain HTTP API you can curl).

## Customer Language
**How they describe the problem:**
- `[NEEDS: verbatim quotes from beta testers; none on record yet]`
- The author's own words (docs/launch-posts.md): "Not failing. Just... waiting." and "I'd
  come back twenty minutes later to a terminal that had done nothing since I left."
**How they describe us:**
- `[NEEDS: verbatim]`
**Words to use:** your wrist; buzz; one tap; it carries on; blocked; Needs you; your own
network; no cloud relay; no account; one command in, one command out; read it before you
run it; the honest answer; free beta.
**Words to avoid:** "no telemetry"; "works from anywhere"; "verified end to end";
"secure" as a bare adjective (say what is gated and how); "VNC"; "seamless",
"revolutionary", "game-changing"; any phrase that calls a competitor broken.
**Glossary:**
| Term | Meaning |
|------|---------|
| meshd | The daemon on each machine. Bun + TypeScript, bearer-token HTTP API. |
| mesh | The CLI: setup, pair, doctor, hooks install, upgrade, status, uninstall. |
| Pairing code | Eight characters printed by `mesh pair`, good for ten minutes and one use; also a QR. |
| Hook | What `mesh hooks install` registers so a blocked agent posts to `/events`. |
| Needs you | The watch screen listing every blocked agent across every machine. |
| Complication | The watch-face count of agents waiting on you; says when its reading is stale. |
| Live Activity | The one session that needs you, on the Lock Screen and Dynamic Island. |
| Tailnet | A Tailscale private network; what the product was built against. Not required. |
| Multiplexer | tmux, rmux, herdr or zellij. Sessions persist in it; the user's choice. |
| Risk classifier | Reads the question and names the verb (Force push) in red for destructive actions. |
| mesh doctor | The source of truth for setup problems: token, input, screen, mux, push. |

## Brand Voice
**Tone:** Plain and direct, honest about limits, unhurried. A builder talking, not a
company. Posts use first person singular ("I built the thing that fixes it"). The site's
FAQ is titled "The honest answers"; write to that standard.
**Style:** Short sentences. Concrete nouns and numbers (3,000 lines, about 3 MB, an
eight-character code, ten minutes, one use). Say what it does not do in the same breath as
what it does. Explain the safety choice ("Continue" is a yes) rather than asserting safety.
**Personality:** Honest, specific, a little dry, protective of the user.
**House style for new copy** (v1 assumption from the team's writing rules; existing README
and site copy predate it): no em dashes; no "not just X, but Y"; no puffery; no forced
groups of three; straight quotes; sentence-case headings; active voice; say what it does,
not how it feels.

## Proof Points
**Metrics:** Daemon about 3,000 lines, no dependencies, about 3 MB. Setup about two
minutes. Pairing code: eight characters, ten minutes, one use. A fleet of four takes one
code. Latest release 0.5.2 (2026-08-27). 10 to 15 people on the waiting list (August
2026). Used daily by the author.
**Customers:** None named. `[NEEDS: beta testers willing to be named]`
**Testimonials:**
> `[NEEDS: quotes; none on record]`
**Value themes:**
| Theme | Proof |
|-------|-------|
| Watch-first | Crown-scrollable terminal, complication, Live Activity, dictation, all shipped (web/index.html, CHANGELOG.md) |
| Local-first | No relay; `web/privacy.html`; `install/payload/meshd/telemetry.ts` is the whole telemetry payload |
| Honest setup | One curl in, `mesh uninstall` out; `mesh doctor` tells you what is missing and `--fix` raises the dialogs |
| A safe yes | `Shared/RiskClassifier.swift` turns the button red and names the verb |
| Open | MIT, all of it: daemon, CLI, installer, apps |

## Goals
**Business goal:** Real users on the TestFlight beta and their feedback, then a paid App
Store release (ROADMAP.md "Next"). `[NEEDS: a number and a date]`
**Conversion action:** Join the TestFlight (https://testflight.apple.com/join/pVYPTxc7),
then run `curl -fsSL https://mesh.lesearch.ai/install.sh | sh` and `mesh setup`.
**Current metrics:** `[NEEDS: TestFlight installs, site visits, install-script hits]`
**Gates on any public push** (ROADMAP.md "Now — shipping"): the DNS record for
mesh.lesearch.ai, and submitting the latest build for Beta App Review so external
testers actually receive it.

## Links
- Site: https://mesh.lesearch.ai (privacy: https://mesh.lesearch.ai/privacy)
- TestFlight: https://testflight.apple.com/join/pVYPTxc7
- Source, as the public copy names it: LeSearch-AI/mesh and LeSearch-AI/mesh-install.
  `[NEEDS: confirm the public repo before linking; this development repo is
  aryateja2106/lecoder-watch]`

## Sources in this repo
README.md (positioning, "What is, and is not, true yet", Telemetry, Requirements) ·
web/index.html (hero, setup, FAQ, footer claims) · ROADMAP.md (stance, shipping gates,
non-goals) · CHANGELOG.md (versions) · docs/competitive-position.md (camps, blockers,
pricing table) · docs/launch-posts.md (draft posts and "what NOT to claim") · AGENTS.md
(who it is for).

## Changelog
*Newest first. One line per revision: what changed and why.*
- v1 (2026-09-19) — Initial context, auto-drafted from the repo; every unknown marked
  `[NEEDS: ...]`, house-style rule under Brand Voice is an assumption to confirm.
