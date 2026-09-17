# Who this is for, and how it makes money

*2026-09-17. Produced by a research agent that read the product spec, the launch kit, the
competitive docs, the research under `references/external/research/`, the code, and did
fresh web research on competitor pricing (URLs cited inline, fetched that day). Prices are
the owner's call; this document argues, it does not decide. Open questions at the end are
real unknowns, not rhetorical.*

## The short version

- **The customer that fits the product as it ships today** is the solo developer or indie
  founder who runs Claude Code or Codex for hours on a Mac they own, steps away, already
  has Tailscale or works on home Wi-Fi, owns an Apple Watch, and does not want their
  sessions relayed through a vendor. Not the non-technical person AGENTS.md names. That
  person is the vision; the install path (curl, `mesh pair` in a terminal, Tailscale off
  the LAN, macOS permission grants, TestFlight) does not reach them yet.
- **The wedge is real and nobody else has it:** watch terminal + Mac GUI control +
  nothing relayed through anyone's cloud + secrets redacted before they leave the Mac.
  Every 2026 competitor puts a vendor server in the path or needs SSH.
- **Monetize in this order:** GitHub Sponsors "Founding Supporter" today (zero code), one
  Apple-managed one-time in-app purchase once an App Store build exists, consulting
  (CloudAGI) as the actual 2026 revenue line. No subscription while the product is not
  shipping weekly, no license server, no relay, no team tier.
- **Before charging anything:** make the wrist answer real (PermissionRequest hook +
  session ids + one physical-watch Allow on record), fix the two notification blockers,
  install the Codex hook instead of printing it, unify the vocabulary. The headline loop
  has never been proven with buttons on a real watch; 0 of 312 recorded events were
  replyable.

## Candidate customers, scored for fit with what ships today

| | Who | Their pain | Fit today |
|---|---|---|---|
| **A. Agent-native solo developer with an Apple Watch** | Runs Claude Code and/or Codex for hours on a Mac they own, often plus a Linux box; on Tailscale or home Wi-Fi; comfortable with `curl | sh` and macOS permission dialogs | "Came back to find it stuck on a y/n prompt for 20 minutes"; six tmux panes and no idea which agent is waiting; fear of YOLO mode as the alternative (HN and Claude Code issue threads in `references/external/research/search-language-and-appstore.md`) | **8/10.** Every proven capability is theirs: install + QR pair, transcript Chat, watch terminal, Mac control, redaction ledger, hand-off. Week-one gaps: notifications never carried buttons, Codex hook is printed not installed, TestFlight-only, LAN/tailnet only |
| B. Non-technical AI-agent enthusiast (AGENTS.md's stated target) | Excited about agents, will not configure SSH, port forwarding or a VPN | Same stalls, plus they cannot get past setup at all | **3/10.** Install is terminal-only; off-LAN needs Tailscale; TCC grants; the friendliest surface (MeshDesktop) is not distributed; Codex-in-ChatGPT gives them zero-setup supervision free. `positioning-rewrite.md` §9 already recommends dropping this audience from copy until a stranger's cold install is recorded |
| C. Relay-averse, secrets-sensitive builder | Contractors and 2-5 person shops on client or proprietary code who refuse to pipe transcripts through Anthropic/OpenAI/Happy/Omnara relays | Agents print keys into transcripts that go to vendor clouds and lock screens; NDA exposure | **6/10.** Redaction + exposure ledger, no relay, no account, MIT, telemetry opt-out. But LAN transport is plain HTTP with a bearer token (the repo's own proposal calls it "a remote-code-execution box with a password sent in the clear"), and there is no per-user auth or audit trail beyond exposures. Same person as A with a sharper reason to pay |
| D. Multi-machine fleet operator / CloudAGI client | Agents 24/7 on a Mac plus Linux boxes or a VPS; wants one view, wake/power, per-agent isolation | Which machine is waiting; boxes asleep; agents sharing one home directory | **6/10.** Fleet pairing, Linux install with systemd and `--user` isolation, stats/tailnet/WoL, hand-off. Gaps: no cross-machine "every waiting session" list (#29), WoL never run from a phone, Linux has no screen capture, Docker/VPS install still open (PR #121). This is the consulting lane, not an app sale |

**Recommendation: A, with C as the copy angle.** B leaves launch copy until a stranger's
cold install is on record; D is sold as an engagement, not an app.

### Positioning statement

> For solo developers who run Claude Code or Codex for hours on a Mac they own and step
> away, LeSearch Mesh is the iPhone and Apple Watch supervisor that shows the agent's real
> conversation, lets you answer it from your wrist, and takes the Mac's screen when the
> agent can't, over your own network with nothing relayed through anyone's cloud and every
> key it prints redacted before it leaves the Mac. Unlike Claude Remote Control, Codex
> mobile, Happy, Omnara and Agent Approve, no vendor server is in the path; unlike Moshi,
> there is no SSH, no Tailscale scripting and no Remote Login: one pasted command in, one
> command out.

## The field, September 2026

| Product | Price | What they are | What they lack vs Mesh |
|---|---|---|---|
| [Moshi](https://getmoshi.app/pricing) | Free tier; Pro $7.99/mo, $69.99/yr, $199 lifetime; 4.7★ (502) | "A terminal built for phones": SSH/Mosh to a host you already control, tmux/Zellij/herdr pickers, agent inbox with approve/deny, Lock Screen + Watch, on-device voice | Needs an SSH-reachable host (their guide: Tailscale, sshd, mosh, tmux). No Mac GUI control; the watch cannot attach a shell |
| [Happy](https://happy.engineering) | Free, MIT; 4.9★ (970+) | Remote control for Claude Code and Codex from iOS/Android/web, end-to-end encrypted relay | Relay through their backend; no watch; no Mac screen |
| [Omnara](https://apps.apple.com/us/app/omnara-claude-codex-mobile/id6748426727) | App free (4.4★, 36); paid tier unknown, pricing page 404s; third parties cite $9-29/mo | "Command center for your coding agents", YC-backed, cloud sync, watch added in 2.0.5 | Vendor cloud in the path |
| [Agent Approve](https://www.prnewswire.com/news-releases/agent-approve-brings-ai-agent-observability-and-control-to-your-wrist-302819165.html) | $14.99/mo, 7-day trial (launched 2026-07-07) | Watch-first control plane for 14+ agents, destructive-pattern policy, remembered decisions, `npx agentapprove` + QR | E2E-encrypted relay; no terminal; no Mac control. Closest to Mesh's wrist loop |
| [Claude Code Remote Control](https://code.claude.com/docs/en/remote-control) | Bundled with Pro/Max/Team/Enterprise | Continue a local session from phone or browser; permission prompts forwarded with push | Through Anthropic's servers; Claude only; no watch; no Mac screen |
| [Codex in ChatGPT](https://openai.com/index/work-with-codex-from-anywhere/) | Free on every ChatGPT plan (2026-05-14) | Supervise a Codex session on your Mac from the ChatGPT app, QR pairing | OpenAI relay; macOS host only; no watch |
| [Conductor](https://www.conductor.build/pricing) | Free local; Pro $50/mo cloud; Teams $60/user/mo | Parallel agents in isolated workspaces on your Mac; mobile tied to the paid cloud tier | No watch, no Mac screen |
| Blink Shell, Termius, Prompt 3 | Blink+ annual (~$19.99/yr cited); Termius Pro ~$10/user/mo; Prompt 3 $9.99/yr or $49 once | SSH clients | No agent layer, no watch |
| [watch-control](https://github.com/CryptoPilot16/watch-control) | Free, 2★ | Approve Codex/Claude from a Watch over Tailscale, tmux poller + PermissionRequest hook | Proof the wrist loop is buildable without a relay; not a product |

Two facts to hold onto. "Approve from the phone" became table stakes in 2026 and two of
the four vendors give it away. The only things nobody gives away are the watch terminal,
the Mac's screen and pointer, and "nothing leaves the Mac". Lead with those.

## Monetization options

| Model | Price | Why | Risk |
|---|---|---|---|
| **One-time App Store IAP "Mesh Pro"** (non-consumable), app-side gates only; daemon stays MIT and ungated | Suggested $29 once, Founding Supporter code honored (anchors: Prompt 3 $49 once, Moshi $199 lifetime) | Least ongoing burden of any paid path: Apple handles billing, tax, refunds, payouts. No license server, no relay, no account. Gates live in Swift only (Mac-control hub on the watch, hand-off menu, more than 2 paired machines, built-app Install), so the free product still proves the whole alert-to-answer loop | Needs an App Store listing first (TestFlight cannot sell IAP; nine unchecked boxes in `docs/app-store-submission.md`). Review risk under 4.2.7 / 2.1. One-shot revenue. Source-builders bypass it (accept it, as Happy does). India payout and GST handling unknown |
| Free app + Pro subscription, lifetime-locked Founder tier | $2.99/mo or $24.99/yr; Founder $19.99/yr for life | Category norm; recurring | A subscription implies weekly shipping and support, the opposite of a consulting-first 2026. Charging monthly for a product with an unproven headline loop invites one-star reviews |
| Paid daemon "Pro" key via a merchant of record (Lemon Squeezy / Paddle) | $49/yr | Does not depend on App Store approval; MoR handles GST for an India seller | Gating an MIT daemon is an honor system; adds key-validation code to a daemon whose selling point is "reviewable in one sitting"; a second billing vendor |
| Team / fleet license | $99/yr per fleet or $8/user/mo | Where B2B money is (Termius, Conductor) | Premature: no per-user auth, SSO, admin surface or audit log; highest ongoing burden; requires server-side features the product refuses |
| **Sponsorware: GitHub Sponsors "Founding Supporter"** (early TestFlight access + lifetime Pro code when the store build lands) | $5/mo or $49 once | Available today with zero code; MIT-compatible; converts the 10-15 people waiting into a named cohort who also become the device-proof testers | Low revenue; verify Sponsors payout eligibility for an India-resident account; sponsors expect responsiveness |
| **Consulting-led (CloudAGI):** product free, sell "agents on hardware you own, supervised from the wrist" engagements with Mesh as the deliverable | Engagement pricing | Aligns with the 2026 revenue-first focus; a live demo no competitor can show | Product revenue stays zero; a demo that is "correct but dead" costs a client; consulting time competes with the fixes the product needs |

**Recommendation.** Step 0, today, zero code: open GitHub Sponsors with a Founding
Supporter tier that promises early TestFlight access and a lifetime Mesh Pro code. Keep
the alert-to-answer loop, Chat, both terminals, Mac control on the phone, and redaction
free forever; keep daemon and apps MIT. Step 1, after the App Store build exists: one
Apple-managed non-consumable IAP at a suggested $29, gating only app-side conveniences that
need no daemon change. In parallel, CloudAGI sells fleet setups with Mesh as the
deliverable. That, not the IAP, is the 2026 revenue.

## What to change in the product for this customer

Ranked by impact against effort. Evidence is where the agent found the gap.

| # | Change | Why it matters to A | Effort | Evidence |
|---|---|---|---|---|
| 1 | **Make the wrist answer real:** register `PermissionRequest`, populate `Agent.sessionId`, record one physical-watch Allow | The one thing every competitor sells and the landing promises; until a real watch answers a real prompt the product is a terminal viewer with a dead headline | M | `install/payload/bin/mesh:1209` `HOOK_EVENTS = ["Notification", "Stop"]`; `server.ts:794,1024` the only sessionId sites; `push.ts:228-229` withholds buttons when not replyable; 0/312 events replyable; memory note: a PermissionRequest hook "fired, blocked 25 s, and its allow verdict was obeyed", so the path is proven possible |
| 2 | Install the Codex hook instead of printing it | Half the ICP runs Codex, and Codex-in-ChatGPT is now free for them | S | `mesh:1266-1268` prints instructions; issue #20; landing claims "Claude Code, Codex, whatever you run" |
| 3 | One vocabulary: Allow / Deny / Reply / Stop; stop calling the daemon "the agent" | Six labels for the blocked state and four names for one Enter keystroke do not earn a tap | S | `Watch/WatchViews.swift:1048`, `iOS/ContentView.swift:442`, `PairMachineView.swift:114,319`, `DaemonCapabilities.swift:95-96`; the table is already in `messaging-audit.md` §3 |
| 4 | Ship the notification path: fix #99 and #80, merge PR #120 | The ICP's first real test is "did the buzz arrive and was it answerable" | M | #99 (push gate silences info-level), #80 (banner raised then deleted), PR #120 draft; cards piled 5-7 deep |
| 5 | Rewrite landing and store copy to the proven record: lead with the watch terminal and Mac control, drop the FAQ "Yes" to away-from-home until reach exists | This ICP reads Show HN comments; one "it never buzzed" reply kills the launch | S | `web/index.html:583-584`; replacement copy in `positioning-rewrite.md` §3, §7 |
| 6 | Stop leading Monitor and the watch home with a Usage row that is empty for everyone but the owner | A stranger sees "No usage data" first on two screens; depends on OpenUsage on :6736 | S | `server.ts:700-745`; issues #35-40 cover the native replacement |
| 7 | `mesh doctor` proves the alert loop end to end (synthetic PermissionRequest through hook, `/events`, APNs, device ack), red when buttons are absent | Three features shipped correct and dead; the ICP will not debug hook registration | M | issue #23; `doctor.ts` already exercises the real screen path for the same reason |
| 8 | App Store submission pack: version alignment, in-app privacy link, Demo Host, device video | No IAP can be sold from TestFlight | L | `project.yml:10` 0.5.1 vs `server.ts:25` 0.6.0; no Privacy string in iOS/; `docs/app-store-submission.md` |
| 9 | Pinned self-signed TLS on meshd before charging money or saying anything about off-LAN use | The relay-averse buyer is paying for "nothing leaves the Mac"; a bearer token over plain HTTP undercuts that | L | `openspec/changes/reach-my-mac-from-anywhere/proposal.md`; PRODUCT-SPEC §6.6 |
| 10 | Distribute MeshDesktop signed and notarized (or a Homebrew tap) instead of telling users to build it in Xcode | The menu-bar app is the permissions and pairing surface that removes the Terminal step | L | `install.sh` has zero MeshDesktop references; `mesh desktop` tells the user to run Xcode; issues #49, #77, #41 |

Items 1-4 are also the "before any price" gate in the short version. The security review
(`docs/review-2026-09-17.md`) adds three transport findings that matter to customer C in
particular; read that before promising "nothing leaves the Mac" to anyone on hotel Wi-Fi.

## Open questions only the owner can answer

1. Is $29 one-time acceptable, and does the Founding Supporter promise (lifetime Pro code)
   get honored for the people on the waiting list?
2. Do the iOS and watch apps stay MIT once an IAP gate exists? Source-builders will bypass
   it. If that is not acceptable the gate moves to the daemon, which conflicts with
   "reviewable in one sitting".
3. Apple Developer payouts and GST for an India-domiciled seller, Small Business Program
   eligibility, and GitHub Sponsors payout eligibility in India: all unverified.
4. Has any stranger completed a cold pairing on a physical iPhone? No record exists. That
   is the proof that would justify widening toward B.
5. Which mesh-install release is the fleet running today versus daemon 0.6.0?
6. Will App Review treat Mac control as a 4.2.7 mirror of specific software (Claude Code)
   rather than a generic mirror of the user's own Mac? Is the Demo Host route acceptable?
7. AGENTS.md still names non-technical people as the audience. Narrow launch copy to
   developers while keeping the vision sentence?
8. Is pinned TLS a hard prerequisite for the first paid tier, or is "LAN and tailnet only,
   plain HTTP" acceptable to charge for as long as the copy says so?
9. Is there a live CloudAGI engagement that would use Mesh as the deliverable? Without one
   the consulting-led option has no proof point.
