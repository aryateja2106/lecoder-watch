# Launch copy — 0.3.0

Drafts only. Nothing here has been posted anywhere; posting is yours to do.

Links to use:
- TestFlight: `https://testflight.apple.com/join/pVYPTxc7` (live)
- Site: `https://mesh.lesearch.ai`
- Installer source: `https://github.com/LeSearch-AI/mesh-install`

---

## LinkedIn — the main post

> My coding agents kept stopping to ask me things while I was in another room.
>
> Not failing. Just… waiting. Claude Code hits a permission prompt — *can I force-push?*,
> *overwrite this file?* — and sits there. I'd come back twenty minutes later to a
> terminal that had done nothing since I left.
>
> So I built the thing that fixes it: **LeSearch Mesh**. Your machines, and the agents
> running on them, on your iPhone and Apple Watch. An agent blocks, your wrist buzzes
> with the actual question, you tap once, it carries on.
>
> Two decisions I'd defend:
>
> **It's local-first, with no cloud in the middle.** The comparable tools relay your
> sessions through their servers — easier to build, and it means your terminal output
> and your source pass through someone else's machine. Here the phone talks straight to
> a daemon on hardware you already own, over your own network. No account, no relay, no
> database. If I disappear tomorrow the daemon keeps running; it's your machine and a
> plain HTTP API you can curl.
>
> **"Continue" is not a safe word.** It sends Return — and Return accepts whichever
> option the agent already has highlighted. So a one-tap button on a watch isn't
> "acknowledge", it's *yes*, pressed by someone walking who read two lines at most. The
> app now reads the question and, for a force-push or an `rm -rf` or a `DROP TABLE`,
> turns that button red and makes it say **"Force push"** instead of "Continue", with
> one line explaining what happens. Everything else stays calm — flag everything and
> people learn to skip the warning.
>
> It's free, in TestFlight, and it takes about two minutes: install a daemon on your
> Mac or Linux box, type an eight-character code into the app, done.
>
> If you own a MacBook, an iPhone and an Apple Watch, I'd genuinely like you to break
> it: [TestFlight link]
>
> Built in public under LeSearch AI. All of it is open and MIT — the daemon, the
> installer, and the apps.

---

## LinkedIn — shorter variant

> Agents that run for hours and then freeze on one question are the actual bottleneck
> in agentic coding. Not model quality. Waiting.
>
> LeSearch Mesh puts every machine you own and every agent on it on your wrist. Agent
> blocks → watch buzzes with the question → one tap → it continues.
>
> Local-first: your phone talks straight to your machine. No cloud relay, no account,
> nothing of yours passing through my servers.
>
> One detail I'm proud of: the one-tap button sends Return, and Return accepts the
> agent's highlighted default — so it's a *yes*, not an acknowledgement. For a
> force-push or an `rm -rf` the button turns red and names the verb instead of saying
> "Continue".
>
> Free TestFlight beta. Two-minute setup. Break it for me: [TestFlight link]

---

## X / short form

> Your coding agent stops to ask a question. You're in another room. Twenty minutes
> gone.
>
> LeSearch Mesh: agents on your wrist. Blocked → buzz → one tap → continue.
> Local-first, no cloud relay, no account.
>
> And when the question is `git push --force`, the button says "Force push" in red —
> not "Continue".
>
> Free beta: [TestFlight link]

---

## Notes on what NOT to claim

- Don't say "verified end to end on device" — push delivery to a real device is still
  unproven. Say "free beta, tell me if your wrist buzzes".
- The open-source claim is now the full one: all of it is public and MIT — daemon, CLI,
  installer, and the iOS/watchOS/Mac apps. Say that; don't undersell it to the old
  "daemon only" line.
- Don't imply it works from anywhere. It works where your phone can reach your machine —
  a tailnet or the same LAN. There is no hole-punching.
- Don't name competitors as broken. "They relay through their cloud" is a factual
  difference; anything stronger invites a correction you'd lose.
- Don't say "no telemetry" or "nothing ever phones home". The apps collect nothing;
  the daemon sends one anonymized heartbeat a day, disclosed at
  `https://mesh.lesearch.ai/privacy`, and `MESHD_TELEMETRY=off` silences it. Phrase
  privacy claims as "no cloud relay, nothing of yours passing through my servers".
