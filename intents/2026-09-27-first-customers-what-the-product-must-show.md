---
status: draft
owner: Arya
source: conversation
date: 2026-09-27
---

# Intent: A prospect sees the product do its one promise, live, and wants it

## Problem

In my words: "There is solid demand for a product like this right now and we are not even
playing it yet." The design compromises are stopping me from getting new clients (see the design
intent of the same date), and it is not written down what a prospect must see before they say
yes.

The headline promise in the product spec is that an AI agent stops to ask a question, your wrist
buzzes, you answer, and the agent carries on with the laptop closed (`docs/product/PRODUCT.md` §1). One concrete
example of why that promise is not yet demo-ready: the command that installs the agent hooks
still registers only two events, "Notification" and "Stop" (`HOOK_EVENTS` in
`install/payload/bin/mesh`). Without the permission-request event, a notification cannot carry
working Allow and Deny buttons. The 2026-09-17 customer analysis counted 0 of 312 recorded
agent events as answerable from a notification (`docs/icp-and-monetization.md`, "The short
version"). No record exists of a stranger installing and pairing on their own iPhone (same
document, open question 4).

What is in place: version 0.8.0 was published on 2026-09-22 with a clean-device install on
record (`PUBLISHED.md`); the product's real edge, which no competitor gives away, is the watch
terminal, control of the Mac's screen and pointer, and nothing relayed through anyone's cloud
(`docs/icp-and-monetization.md`, "The field"). Meanwhile about 21 unreviewed agent pull requests
went into account features my roadmap forbids, instead of into this loop (see the lifecycle
intent of the same date).

## Proposed outcome

- There is one named first customer profile I chose, and one sentence that tells them why this
  is for them.
- A prospect who fits that profile can go from the landing page to a paired phone and watch in a
  few minutes, without my help.
- In a live demo, a real agent on my Mac stops and asks, my watch buzzes, I tap Allow, and the
  agent carries on. It works every time, and there is a recorded run proving it on real devices.
- The landing page and store text claim only what is on record.
- I have a two-minute demo, on-theme, that I can show a CloudAGI client, and it ends with a clear
  next step (an engagement, a sponsorship, or a purchase: my call).
- Feedback from the first users arrives in one place I actually read.

## Affected users and systems

The Apple Watch app, iPhone app, the daemon (`meshd`) and its agent hooks, the `mesh` command
line and installer, the landing site (`web/`), TestFlight and later the App Store listing, and
the feedback path (in-app "Report a problem"). Prospects, the first cohort of users, and CloudAGI
clients.

## Constraints

- 2026 revenue comes from CloudAGI consulting first; the product supports that, it does not
  replace it.
- The 2026-09-17 analysis argues against a subscription, a license server, a relay or a team tier
  for now (`docs/icp-and-monetization.md`, "Monetization options"). It argues; the pricing decision is
  mine.
- Local-first and no account system: the optional account in Settings exists only so a problem
  report can be answered, never to gate a machine (`docs/product/PRODUCT.md` §10).
- Apple's rules: TestFlight cannot sell in-app purchases; external testers only get a build after
  Beta App Review; controlling a Mac from the phone may draw App Review questions.
- Payouts and tax for an India-based seller (Apple, GitHub Sponsors) are unverified.
- Proof on real devices (a physical watch answering a real prompt) needs my hands; an agent
  cannot do it (`BLOCKED.md` lists what only I can do).
- Security before charging: the review says a paying, privacy-minded customer will expect the
  plain-Wi-Fi token issue fixed first (`docs/review-2026-09-17.md`, SEC-01).

## Open questions

1. Which first customer: the solo developer running Claude Code or Codex on a Mac with an Apple
   Watch (the analysis recommends this), the non-technical AI enthusiast (the vision in
   `AGENTS.md`), the privacy-minded contractor, or the multi-machine CloudAGI client?
2. Is the first cohort Claude Code users only, or must Codex work on day one?
3. What is the one thing a prospect must see in the first minute: the wrist answer, the agent
   chat, the Mac screen on the phone, or many machines on one screen?
4. Is there a live CloudAGI engagement that could use this product as the deliverable? Who?
5. How do people pay, if at all, this year: GitHub Sponsors "Founding Supporter", a one-time
   in-app purchase later, consulting only, or something else? What price feels right?
6. Must the plain-Wi-Fi token issue be fixed before anyone pays, or is "Tailscale or home Wi-Fi
   only, stated plainly" acceptable?
7. Who are the 10–15 people waiting (mentioned in the analysis), and how do you want to invite
   them?
8. Which comes first if only one fits this month: the design theme, or the wrist answer working
   on a real watch?
9. Which inbox for user feedback: `LeSearch-AI/mesh` issues (where it lands today) or this
   repository's issues?
