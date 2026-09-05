# Launch kit — 0.6 "Agents"

Drafts for the Sunday 2026-09-06 release. Every claim below is one the code can back; do not
add a claim without a check script or a screenshot behind it. Links: TestFlight
https://testflight.apple.com/join/pVYPTxc7 · source https://github.com/LeSearch-AI/mesh ·
install `curl -fsSL https://mesh.lesearch.ai/install.sh | sh`.

## The one sentence

Watch and answer Claude Code, Codex or cursor-agent from your wrist, let it build you an app — native if
you have an Apple developer account, a home-screen web app if you don't — and never let a
key it prints leave your Mac.

## TestFlight "What to Test" (paste from CHANGELOG `[Unreleased]`)

1. Open a session that runs Claude Code, Codex or cursor-agent. The peek screen opens in
   **Chat**. You should see your prompt, the agent's reply, its thinking, and each tool call
   with a result — not a terminal dump. Tap **Terminal** to see the live screen beside it.
2. When the agent stops to ask, the watch shows **Decision needed** with Allow / Deny. Tap one.
   The agent continues or stops on the Mac.
3. In a session, run `echo ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghij123456`. The line arrives as
   `ghp_••••••[…]`. Settings → **Exposed secrets** lists it. Mark it rotated.
4. On the Mac: `mesh skills install`, then ask your agent to "build me a habit tracker as a
   home-screen web app". When it prints the URL, open it on the phone and Add to Home Screen.
5. With an Apple developer account and a paired iPhone: ask for a native app instead; tap
   **Install to iPhone** on the card the chat shows when the build is ready.

## X thread (8 posts)

1. Your coding agent stops and asks "can I run this?" at 2am. You are not at the laptop. LeSearch
   Mesh 0.6 puts the agent's conversation on your iPhone and the yes/no on your Apple Watch.
   Free TestFlight, open source, no server of ours in between. Thread.
2. It is a chat now, not a terminal dump. Claude Code, Codex and cursor-agent each write their
   conversation to disk as they go. Mesh reads that file and shows the real thing: your
   prompt, the reply, the thinking, every tool call with its result. The terminal is one tap away.
3. Agents print secrets. `cat .env`. A failing curl with its bearer header. Until now those bytes
   went to the lock screen through Apple's push servers. Every line is now redacted on the Mac
   before it leaves: `ghp_ABCD…` becomes `ghp_••••••[902dd5]`.
4. And you get a count. Each distinct secret the daemon had to hide is one row — what kind,
   its prefix, a fingerprint, how many times, where — never the value. Rotate it at the provider,
   mark it done. `mesh exposures` on the Mac, Settings → Exposed secrets on the phone.
5. Ask the agent for an app. With an Apple developer account it builds a real iOS app on your
   Mac and installs it onto your paired iPhone from a button on the phone. No developer account?
   It builds a home-screen web app your Mac serves on your own network, data in your browser.
6. Agents know how because you tell them once: `mesh skills install` drops three skills
   (Apple native APIs, native app builder, web app builder) into the folders Claude Code,
   Codex and Cursor read. No Team ID hardcoded, no cloud build service, no OTA tunnels.
7. Honest limits: the web apps need HTTPS to work offline, so over your LAN they run while
   the Mac is reachable; the native route needs a paired iPhone and Developer Mode; the live
   terminal now requires your token (it used to require nothing — fixed). It is a beta.
8. Install on the Mac: `curl -fsSL https://mesh.lesearch.ai/install.sh | sh`. Phone + Watch:
   testflight.apple.com/join/pVYPTxc7. Source: github.com/LeSearch-AI/mesh. Tell us what breaks.

## LinkedIn

I build coding agents run for hours and then stop dead on one question. LeSearch Mesh 0.6 is
the release where the phone shows the agent's actual conversation, the watch answers the
question, and nothing the agent prints — API keys included — leaves the Mac unredacted.

Three things shipped:

- Chat, not a terminal dump: the conversation Claude Code, Codex or cursor-agent writes on
  your Mac, structured, on your iPhone; approve or refuse from your Apple Watch.
- Apps your agent builds, on your phone: a real iOS app installed to your paired iPhone if
  you have an Apple developer account, a home-screen web app served from your Mac if you
  don't. The skills that teach the agents how are one command to install.
- Secrets never leave the Mac: every line redacted before push, watch or phone, and a ledger
  of what was exposed so you know exactly what to rotate.

Local-first on purpose: your machines, your network, your subscriptions, no relay of ours.
Free TestFlight beta, MIT source. Links in the first comment.

## Show HN

Title: Show HN: LeSearch Mesh 0.6 – chat with your CLI coding agents from an Apple Watch,
with every secret they print redacted before it leaves the Mac

Text: A small daemon runs on each Mac or Linux box you own; the iPhone and Watch app talk
to it over your own network (Tailscale or LAN), no relay. 0.6 adds: the agent conversation
read from the transcript Claude Code, Codex or cursor-agent already writes (so no PTY
parsing and no change to how the agent runs); Allow/Deny from the wrist; redaction of every
outbound line with a fingerprint ledger of what was exposed; and two routes for "build me an
app" — a native build installed to a paired iPhone via devicectl, or a static web app the
daemon serves for Add to Home Screen. The terminal bridge used to accept attaches with no
auth; that is fixed in this release and is exactly the kind of thing we would like a second
pair of eyes on. Daemon and CLI are ~4k lines of TypeScript on bun; the apps are SwiftUI.

## 20-second demo script (screen recording, phone + watch)

1. Phone: session list → tap a Claude Code session. Chat opens: prompt, thinking, tool cards.
2. Mac (picture-in-picture): the agent asks for permission. Watch: **Decision needed** → tap Allow.
3. Phone: a `cat .env` result shows `ANTHROPIC_API_KEY=sk-ant-••••••[…]`.
4. Phone: Settings → Exposed secrets → one row → mark rotated.
5. Phone: chat card "Habit tracker is ready" → Open → Safari → Add to Home Screen → icon.

## Do not say

- "Works offline" for web apps (only over HTTPS hosting the user owns).
- "Any agent" for chat (Claude Code, Codex, cursor-agent have transcript readers; others show
  their terminal).
- "Encrypted" for the LAN transport (plain HTTP with a bearer token; Tailscale is the
  encryption when used).
