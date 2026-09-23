# PUBLISHED — LeSearch AI 0.8.0

The ledger `scripts/check-published.sh` reads. Every line here is evidence that was
produced by running something, not by describing it. Written 2026-09-22 from the publish
run recorded in [docs/factory/runs/2026-09-22T093000Z-publish.md](docs/factory/runs/2026-09-22T093000Z-publish.md).

Gate: `FACTORY_GATES: level=full status=GREEN passed=4 failed=0 failing=none skipped=none misconfigured=none`
Gate SHA: b6b319097f97d02029fb838195f7c41051887eff
Gate log: docs/overnight/2026-09-21/gate-full-publish-2026-09-23-tail.txt
Gate note: this line is from a run on 2026-09-23 at the sha above, with `MESH_BRAIN_URL`
pinned to `http://127.0.0.1:1234/v1`. Without it `check-brain`'s live half is red on this
Mac and the gate with it: the probe order tries ollama (:11434) before LM Studio (:1234),
and this machine's only ollama model is a text fine-tune that answers `get_time
machine="jetson"` as prose instead of emitting a tool call. LM Studio serving the
already-on-disk spark-x2.5-4b returns a real `get_time({"machine":"jetson"})` in 1.4 s.
The override is the documented knob for a machine running more than one server, but the
probe order picking the weaker one is a defect, not a preference — see BLOCKED.md. The log
is the tail of that run (the decisive line, the end of `test`, and all of `build`); the
gate's own full output was not captured to a file.
PR: #133 OPEN (draft) — https://github.com/aryateja2106/lecoder-watch/pull/133
Landing: https://lesearch.ai
Installer: https://lesearch.ai/install.sh
Clean-device install: fresh simulator 8DDE6724-086C-489F-8345-ABEBE220242F (iPhone 17 Pro, iOS 27.0, created for the run and deleted after) — `mesh apps install --sim --device` — OK: installed LeSearch AI 0.8.0 and it launched (scripts/check-clean-install.sh, output quoted below)
Supabase project: zmisjteztezaqfflwbgf
Signup user: 6411d66d-77bc-4837-b911-10979a49947f (created in-app on 2026-09-22 through Settings → Account → Create account, confirmed; a second, API-level signup dd844c8e-e1b8-4e63-a579-6c5b04844dd2 proved the same path before the UI existed)
Feedback row: 50cb992c-a357-4a2f-b533-dd700f1d2469 (written by the published build 0.8.0 (3) from Settings → Report a problem; a second row b99adb11-3c36-49ad-8fec-9776cc6b4d21 proved the dedupe path)
Feedback issue: https://github.com/LeSearch-AI/mesh/issues/1
Feedback worker: launchd job `ai.lesearch.feedback-worker` on this Mac — `scripts/feedback-worker.plist` runs `bun scripts/feedback-to-issues.ts` every 600 s, logging to `~/.mesh/logs/feedback-worker.log`. It holds the Supabase service key (from the gitignored `supabase/.env`) and files through `gh`. Moving it to a Supabase edge function needs an issues-only token — see BLOCKED.md.
Fresh-eyes issues: https://github.com/LeSearch-AI/mesh/issues?q=label%3Aux-review (7: #2–#8)
Blockers: BLOCKED.md

## What "published" means here

1. Every self-check green and the full factory gate GREEN, quoted verbatim above.
2. The tree clean and pushed, PR #133's body carrying the third-pass table.
3. https://lesearch.ai serving the 0.8.0 landing, `/install.sh` resolving to the daemon's
   own release, and a device that had never seen the app installing and launching it.
4. Supabase live: a fresh signup works end to end, and the published app writes a real
   feedback row.
5. That row becomes a deduped GitHub issue labeled `from-users`.
6. Docs a stranger can walk, with real screenshots.
7. A fresh-eyes review by an agent with no repository context, filed as issues.
8. This file.
9. `docs/overnight/2026-09-21/STATE.md` carrying the M8 row and a refreshed handoff.

## Publish proof

**The landing page.** `web/` deploys to the `lesearch-website` Vercel project;
`vercel deploy --prod` on 2026-09-22 produced deployment `dpl_Eq7j7R5Ugipgcsp4739hBfnbgaTS`,
aliased to https://lesearch.ai. Live: the hero says *Version 0.8.0*, `/install.sh`
307s to `LeSearch-AI/mesh-install/releases/latest/download/install.sh`, `/getting-started`
and `/privacy` answer 200, `/beta` 307s to the TestFlight link. The previous production
deployment (`lesearch-website-94wasg6jk`, 188 days old) is the rollback target.

**Clean-device install.** `MESH_CLEAN_INSTALL_LIVE=1 sh scripts/check-clean-install.sh`
creates a simulator that has never seen the app, proves the bundle is absent, installs
with the user's own command and launches it:

```
check-clean-install: OK — fresh simulator 8DDE6724-086C-489F-8345-ABEBE220242F
(clean-install-1790074031, iPhone 17 Pro) had never seen com.lecoder.meshwatch;
mesh apps install --sim --device installed LeSearch AI 0.8.0 and it launched (pid 28263)
```

Its first screen is `docs/product/shots/clean-install-first-launch.png`. That capture is
also what found the first-run bug fixed in this run: a fresh install opened on *"LeSearch
AI is locked"* because the biometric gate ran before any machine was paired. The phone
app itself still reaches users through TestFlight — that upload is Arya's (BLOCKED.md).

**The daemon a new machine installs.** `sh scripts/release-mesh-install.sh --publish` cut
**https://github.com/LeSearch-AI/mesh-install/releases/tag/v0.8.0** (2026-09-22 12:49 UTC)
from this green tree: `install.sh`, `mesh-install.tgz` (351 028 bytes, 84 files), its
sha256 and `SHA256SUMS.txt`. Verified by downloading what a stranger downloads —
`https://github.com/LeSearch-AI/mesh-install/releases/latest/download/mesh-install.tgz`
now carries `const VERSION = "0.8.0"`. Before this, `curl -fsSL https://lesearch.ai/install.sh | sh`
installed **0.5.2 from 2026-08-27**: the cold review's one blocker
([issues/2](https://github.com/LeSearch-AI/mesh/issues/2)), and the reason a new user would
have got none of the terminal, Chat, Linux control or redaction work the site describes.

**Supabase.** Project `zmisjteztezaqfflwbgf` (org LeSearch AI), schema in
`supabase/migrations/` and pushed with `supabase db push`. Probes:
`GET /rest/v1/feedback` with no key → 401; with the app's anon key → 401 (insert-only);
an anon insert carrying `user_id` → 401; a plain anon insert → 201; the private
`feedback-attachments` bucket accepts a `<uuid>.png` and refuses to serve it back (400).
Auth: a fresh signup returns a session and signs in (`/auth/v1/signup` then
`token?grant_type=password`), e-mail confirmations off until SMTP exists (BLOCKED.md).

**The feedback loop, end to end.** From the published build on a simulator: Settings →
Account → Create account, then Report a problem → *Send to LeSearch AI*, which showed
`Sent. Reference 50cb992c.` The row arrived with `app_version 0.8.0`, `app_build 3`,
`device arm64`, `os iOS 27.0`, `user_id` set. `bun scripts/feedback-to-issues.ts` filed it
as **https://github.com/LeSearch-AI/mesh/issues/1** — labeled `from-users` + `bug`, citing
the row id, with the reporter shown as *contact on file (hash 46579747325b)* and never as
the address. Ten minutes later the launchd job picked up the second report by itself and
deduped it onto the same issue as a comment (`issue_status: duplicate`), which is the
pipeline running unattended, not a one-off invocation.

## Fresh-eyes review

One agent with **zero repository context** was given only the published URL, the
getting-started page, a persona brief (a solo developer who runs Claude Code and Codex on
a Mac and a Linux box, loses forty minutes to an unanswered "Allow this?") and a Linux
machine, and told to use the product cold. It found seven things; all are issues labeled
[`ux-review`](https://github.com/LeSearch-AI/mesh/issues?q=label%3Aux-review).

**Blocked a first-time user — fixed before this file went green:**

- [#2](https://github.com/LeSearch-AI/mesh/issues/2) `curl -fsSL https://lesearch.ai/install.sh | sh`
  installed **0.5.2 from 2026-08-27**, still branded MeshWatch, with none of the terminal,
  Chat, Linux control or redaction work the site sells. The public installer had simply
  never been re-cut. Closed by publishing v0.8.0 (above) — the reviewer downloaded and read
  the tarball, and so does the check now.

**Fixed in this run, though they did not block the core flow:**

- [#4](https://github.com/LeSearch-AI/mesh/issues/4) a clean install opened on *"LeSearch AI
  is locked"* — the biometric gate ran before any machine was paired, so it protected
  nothing.
- [#7](https://github.com/LeSearch-AI/mesh/issues/7) `mesh kb search` with no results printed
  nothing at all, which reads as a hang. It says so now, on stderr, so stdout stays a result
  stream.
- [#6](https://github.com/LeSearch-AI/mesh/issues/6) the landing FAQ pointed only at
  TestFlight feedback; the in-app path — the one this run built — was invisible on the page a
  first-time visitor reads.

**Triaged to the backlog, with the reason:**

- [#3](https://github.com/LeSearch-AI/mesh/issues/3) `ssh host '~/.mesh/bin/mesh doctor'` dies
  with `/usr/bin/env: 'bun': No such file or directory`, because the installer's PATH line
  lives in the interactive-only part of `.bashrc`. It never bites a person typing in a
  terminal, only scripts and remote agents; the fix is a launcher shim in the installer and
  belongs with the next installer change, not with this publish.
- [#5](https://github.com/LeSearch-AI/mesh/issues/5) the public snapshot's CHANGELOG ends at
  0.4.0 and its ROADMAP still says "beta hardening (0.5)", which makes the site look like it
  is overselling. Refreshing it means deciding what of this tree is public — Arya's call, in
  BLOCKED.md.
- [#8](https://github.com/LeSearch-AI/mesh/issues/8) the only `from-users` issue is this run's
  own proof, which reads as a developer's test rather than evidence the pipeline carries real
  reports. It becomes moot the first time a real report lands.

**What the review could not judge:** the entire phone and watch surface — pairing, the
terminal, Chat, menus, notifications, Live Activity, remote screen — because the reviewer had
no device. That gap is a real-device pass, and it is in BLOCKED.md.

## What a stranger can and cannot get today

Honest reading of the line above, because "published" is easy to overclaim:

- **The daemon: yes.** `curl -fsSL https://lesearch.ai/install.sh | sh` on any Mac or Linux
  box installs 0.8.0 today, with no account and nothing of ours in the path.
- **The phone app: only through TestFlight, which still serves the 2026-08-27 build.**
  Uploading 0.8.0 is one command and it is **Arya's**, not because of effort but because App
  Store Connect holds a stray **1.0** pre-release: shipping 0.8.0 is a version downgrade, and
  iOS makes every existing tester delete and reinstall, which wipes their Keychain and every
  machine they had paired. That is a decision about other people's data, so it sits in
  BLOCKED.md with the exact command. Until it lands, a new user gets the daemon at 0.8.0 and a
  month-old phone app — the pairing and terminal work, the native terminal and the in-app
  feedback do not.

Everything this run could prove without his hands is proven above; that one thing it could
not, and did not fake.

## Outstanding human blockers

Carried from [BLOCKED.md](BLOCKED.md), which holds the detail; nothing below was faked or
waited on, and the queue continued past each one.

- Real iPhone: install 0.8.0 OTA and exercise it
- Re-pair the real phone and watch to `pi`
- Vercel AI Gateway card + rotate `AI_GATEWAY_API_KEY`
- CloudKit container decision for the Hundred app's friend sync
- Attended VNC credential flow on the live Mac (stage only)
- Custom SMTP for Supabase Auth (then turn e-mail confirmations back on)
- Issues-only GitHub token as a Supabase secret (move the worker to an edge function)
- Repo consolidation under LeSearch-AI — confirm the archive list and the transfer
- TestFlight 0.8.0 upload (the only way a stranger gets the phone app)
- The Mac's default brain is a model that cannot call tools — the gate above is green only
  because `MESH_BRAIN_URL` points past ollama at LM Studio. Making that the machine's real
  answer (an ollama model that tool-calls, or a probe order that prefers a server that does)
  is Arya's call. The Pi and the Jetson need nothing.

## Housekeeping

The Tailscale share that served the installer overnight — `tailscale serve --https=8890`
onto a python `http.server` on 127.0.0.1:8897 — is **off**: the mapping was removed and the
server stopped, and `https://arya-macbook-pro.tailaddf1e.ts.net:8890/mesh-install.tgz` no
longer answers. Machines now take the daemon from the public release, which is the point of
cutting it. The other two `tailscale serve` mappings (`/` → the bridge on :7820, `/a` → the
daemon's hosted apps) are unrelated and were left alone.

The launchd job `ai.lesearch.feedback-worker` is loaded and running on this Mac every ten
minutes. It is what turns a report into an issue; if this Mac is off, reports queue in
Supabase and are filed when it comes back.
