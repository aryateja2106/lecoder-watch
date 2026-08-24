# Where we actually stand

Researched August 2026. Read this before deciding what to build next; it changes what is
worth doing.

## The category has split into three camps, and the gap between them is the opening

**Agent-aware phone terminals** — Moshi (the leader), Happy Coder, Omnara, Tactic Remote,
ShadowTerm. They know what an AI agent is. None of them can show you your Mac's screen.

**Zero-config remote desktops** — Jump Desktop, Screens, RealVNC, TeamViewer. They solved
"connect from anywhere with no setup". None of them knows what an agent is, and none has a
terminal-session concept.

**Multi-protocol SSH clients** — Blink, Termius, Prompt, Teletype, Secure ShellFish. Deep,
mature, and all four of the non-developer blockers below apply to every one of them.

Nobody spans two camps. That is the whole opportunity.

## What we can genuinely own

**1. A real terminal on the Apple Watch.** This is the one to lead with, and it is more
defensible than it looked.

Moshi's own documentation states its watch app **cannot** attach to a shell, cannot attach to
tmux, cannot show scrollback, and cannot dictate — it is "a lightweight approval and
status-checking surface". Secure ShellFish's watch app is "quick terminal access" with no
detailed claims. ShadowTerm's watch does glances, approvals and a Siri phrase. Omnara's shows
session status.

**Nobody has shipped crown-scrollable, auto-following, VoiceOver-accessible terminal output
on the wrist. We already have it.** It should be the hero shot of the App Store listing and
the landing page, not a footnote.

**2. Agent feed, terminal, and live screen control in one session.** The screen camp has zero
agent awareness. The agent camp has no screen control — Moshi's nearest equivalent is an
in-app browser preview tunneled over SSH, which shows a localhost web server, not the Mac.
Teletype bundles SSH, RDP and VNC but has no agent layer at all.

Nobody lets you get a push that an agent is stuck, read its terminal, and then take the Mac's
screen to fix the GUI thing it cannot do. That end-to-end story is unclaimed.

**3. One command in, one command out, no account.** Jump achieves zero-config but requires a
Jump account and routes access control through Jump's cloud. RealVNC requires a RealVNC
account. Moshi requires an SSH-reachable host plus a pairing token, and its hook still holds
a WebSocket to Moshi's backend. Happy requires an npm install before the QR scan.

Nobody offers: paste one curl, scan a QR, done — with no account created anywhere and APNs as
the only third party. And **nobody at all advertises a one-command uninstall**, which is a
real trust lever when you are asking a non-technical person to pipe a script into their shell.
`mesh uninstall` now exists; say so loudly.

## The four blockers that stop every non-developer

Every SSH-based competitor — Moshi, Blink, Termius, Prompt 3, Secure ShellFish, Teletype,
ShadowTerm — requires all four of these:

1. **Reachability.** A public IP, a port-forward, or a VPN mesh. CGNAT on consumer and mobile
   ISPs makes port-forwarding structurally impossible, which is why Screens Connect's
   UPnP/NAT-PMP path fails silently and Edovia now recommends Tailscale instead.
2. **SSH keys.** Generate a keypair, install the public half into `authorized_keys`, and know
   about agent forwarding and jump hosts.
3. **Enabling sshd.** macOS Remote Login is off by default. Moshi lists "missing Remote Login"
   among its top connection-failure causes.
4. **Addressing.** Knowing the machine's IP or MagicDNS name — and knowing not to use the LAN
   IP over a tailnet.

We already solve 2, 3 and 4 outright: our own daemon, a minted token, and pairing that hands
back every host it knows. **Reachability is the one we have not solved**, and it is the
subject of `openspec/changes/reach-my-mac-from-anywhere/`.

Solve all four with one pasted command and the category is ours.

Worth reading in full, because it is the clearest statement of the problem we exist to
remove: Moshi's own setup guide asks the user to install Tailscale, run
`sudo tailscale up --ssh`, install mosh and tmux via Homebrew, find the tailnet IP with
`tailscale ip`, and enable macOS Remote Login — then warns *"Skip one, and the whole setup
breaks down."*

## Where we are behind, honestly

Moshi is a mature product: 4.7 stars across 482 ratings, iPhone, iPad, Mac, Vision and Watch,
with an agent inbox, Live Activities, Dynamic Island, an in-app diff viewer, a git-aware file
browser, tmux/Zellij/**herdr** pickers, on-device voice via Parakeet and Whisper, image
paste, OSC 52 clipboard, CJK input and session reattach after app kill.

**On the phone terminal specifically, we are behind and should not race them there.** The
phone should be good enough to be useful; the wrist and the screen control are where to spend
effort.

Also notable: Secure ShellFish (4.8 / 1.5K ratings) acts as a **Files provider** so server
directories mount natively, and ships deep **Shortcuts** actions. Happy Coder (4.9 / 991
ratings, MIT) pairs by **QR scan** with TweetNaCl end-to-end encryption. Those are the two UX
benchmarks worth studying.

## Pricing

The observed pattern is freemium plus annual plus lifetime:

| Product | Monthly | Yearly | Lifetime |
|---|---|---|---|
| Moshi | $7.99 | $69.99 | $199–249 |
| Secure ShellFish | $2.99 | $14.99 | $29.99 |
| Screens 5 | $3.99 | $29.99 | $179.99 |
| Teletype | $4.99 | $49.99 | $149.99 |
| Omnara | $9.00 | — | — |
| Jump Desktop | — | — | $14.99 once |

Moshi also runs discounted **Founder** ($3.99/mo, $19.99/yr) and **Pioneer** tiers for early
users. With 10–15 people already waiting, that is the exact play: a permanently discounted
early-supporter SKU that converts the beta list and seeds the first reviews.

## What this means for the next decisions

- Lead every piece of marketing with the watch terminal. It is the one thing no competitor
  has, and it is already built.
- Do not spend the next month on phone terminal parity. That race is lost and it is not where
  the differentiation is.
- Reachability is the single remaining blocker between us and the category. It outranks
  feature work.
- Ship the one-command uninstall as a *stated promise*, not an implementation detail.
