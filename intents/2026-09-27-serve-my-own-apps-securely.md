---
status: draft
owner: Arya
source: conversation
date: 2026-09-27
---

# Intent: An agent builds me a web app, my own machine serves it, and nobody I did not choose can change or delete anything

## Problem

In my words: securely build certain apps or web apps, run them on our computer and serve them
securely: "we don't want anyone to just access it and delete or edit stuff."

Part of this exists. An agent can build a small web app, and the daemon on my Mac serves it at
a private link that contains a secret key (`install/payload/meshd/apps.ts`); the phone's Apps
tab lists every machine's apps. Those apps keep their data in each visitor's own browser (the
shipped app-building skill, `install/payload/share/skills/pwa-local-app-builder/SKILL.md`), so
today a visitor cannot change anything on my Mac. What blocks the rest:

One concrete example: the secret in each app link is only 8 characters (32 bits), minted in
`install/payload/bin/mesh` at the `randomHex(4)` calls, and nothing limits how many guesses
someone can make. The 2026-09-17 review rates this SEC-06 and says it is too short to share
outside my own devices (`docs/review-2026-09-17.md`). The same link also answers in plain HTTP
on my home Wi-Fi, because the daemon listens on every network interface (SEC-01).

Two more gaps:

- An app page is served from the daemon's own address. Opened at `localhost` on the Mac itself,
  such a page can very likely tell the daemon to run any command without the token. Found by
  reading the code on 2026-09-27; **not** proven by running it yet.
- There is no support at all for an app that has its own small server, such as a shared to-do
  list with a database. Nothing forwards requests to one (`docs/sdlc/references/nethera.md`,
  "What it is" and "Our side"). That is exactly the kind of app where "edit and delete" matter.

Nethera, one of the inspiration projects, solves this by routing every visitor through its own
cloud and gating access with its own account logins (`docs/sdlc/references/nethera.md`). Both are
things my roadmap rules out.

## Proposed outcome

- I can ask an agent to build a web app, run it on my Mac or the Jetson, and open it from my
  phone, in one flow.
- By default only my own devices can reach it. Nothing is public unless I explicitly decide so,
  app by app.
- Every app link says in plain words who can open it (for example "your devices only" or "your
  devices and this Wi-Fi").
- People I share an app with can look at it, but cannot change or delete anything unless I gave
  them a named key that I can see, and revoke at any time.
- A page an agent built can never act as me against the daemon, however it is opened.
- Every change made through an app to my machine shows up in the security logbook (see the
  security intent of the same date).
- Links already saved on a phone's Home Screen keep working, or I am told clearly which ones
  need re-sharing.

## Affected users and systems

The daemon (`meshd`) on the Mac and the Jetson (and any Linux box), the `mesh` command line
(`mesh apps …`), the iPhone app's Apps tab, the app-building skill agents follow, and whoever I
share an app with (family, a client, a friend testing it).

## Constraints

- No cloud relay and no server of ours or anyone's in the data path by default; no account
  system (`ROADMAP.md`, "Non-goals"; `docs/product/PRODUCT.md` §10).
- Local-first: an app's data and its secrets (API keys) stay on the machine that serves it,
  never inside the folder that is served to visitors.
- Tailscale Funnel, which would make a link public, carries visitors through Tailscale's
  servers: a third party in the path. Only if I decide so, and only after the link keys are long.
- Three existing self-checks assert the short 8-character key (`scripts/check-mesh-apps.sh`,
  `scripts/check-apps-ota.sh`). Changing them needs my explicit OK in the session; an
  unattended agent may not edit existing checks.
- Heavy tooling (Docker Compose as the app format) is out: agent-built apps are small.
- Closing the "app page acts as me" hole comes before any app gets its own server.

## Open questions

1. Who should be able to open an app: only my own devices on Tailscale (as today), or anyone I
   send the link to (which means Funnel and a third party in the path)? Is that acceptable under
   "local-first, forever"?
2. Do agent-built apps need their own server at all, or is "a page whose data lives on each
   device" enough for now? Name one real app you want that needs a server.
3. For apps with a server, who may edit: only me, or also people I hand a named, revocable key?
4. Would "edits allowed only when it is me on my own Tailscale network" be a better rule than
   keys?
5. May the fix for the short keys edit the three assertions in the two existing checks?
6. Should old short-key links be replaced automatically (they break on phones that saved them),
   or only flagged?
7. Should the daemon stop answering on plain Wi-Fi by default? That also closes the plain-HTTP
   app link, but changes pairing on a machine without Tailscale.
8. Does serving apps from the Jetson work today (Tailscale installed, secure name on)? Unverified.
