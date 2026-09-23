# BLOCKED — needs Arya's hands (2026-09-22 publish run)

Each heading is one decision or action only Arya can take. The publish check
(`scripts/check-published.sh`) carries every heading below into `PUBLISHED.md`, so nothing
here is silently dropped. Nothing in this file was faked or waited on; the queue continued.

## Real iPhone: install 0.8.0 OTA and exercise it
Apps tab → LeSearch AI → Install (0.8.0 is served OTA from the Mac daemon; cable +
`mesh apps install meshwatch` also works). Then try the remote keyboard, gestures, the Live
Activity and the Choose cards on the phone and on the watch. The unattended proof below used
a fresh simulator, never a physical device.

## Re-pair the real phone and watch to `pi`
Its token was rotated twice on 2026-09-22.

## Vercel AI Gateway card + rotate `AI_GATEWAY_API_KEY`
The key was pasted in chat once; it lives in `~/.config/secrets.env`. Add a card to the team
before fx / Jev can answer.

## CloudKit container decision for the Hundred app's friend sync

## Attended VNC credential flow on the live Mac (stage only)
ADR platform-shape §6 slice 2. Never driven unattended.

## Custom SMTP for Supabase Auth (then turn e-mail confirmations back on)
The project has no SMTP provider, and Supabase's built-in mailer only delivers to team
members. To make a fresh signup work today, `mailer_autoconfirm` is ON (supabase/config.toml,
`[auth.email] enable_confirmations = false`). Once you add a provider (Resend, Postmark, SES —
needs an account and a card) set `enable_confirmations = true` and `supabase config push`.

## Issues-only GitHub token as a Supabase secret (move the worker to an edge function)
The feedback pipeline runs as a launchd job on this Mac (`ai.lesearch.feedback-worker`,
every 10 min) using the Mac's own `gh` login, which is broader than issues-only. Mint a
fine-grained PAT on LeSearch-AI/mesh with Issues: read/write, `supabase secrets set
GITHUB_ISSUES_TOKEN=…`, and the same script can move into an edge function on a cron.

## Repo consolidation under LeSearch-AI — confirm the archive list and the transfer
Today the source of truth is `aryateja2106/lecoder-watch` (public, this branch), while the
landing links point at `LeSearch-AI/mesh` (a curated 0.4.x snapshot, 2026-08-21) and the
installer at `LeSearch-AI/mesh-install` (kept: the install.sh URL contract). Proposed final
layout, recorded in PUBLISHED.md; nothing below was done unattended:

1. Transfer `aryateja2106/lecoder-watch` into the LeSearch-AI org (GitHub transfer keeps
   history and redirects the old URL; reversible) and make it the monorepo home — then
   either rename it `mesh` after archiving the snapshot, or keep both names with the
   snapshot archived. Your call.
2. Archive (reversible, never delete): `LeSearch-AI/meshwatch` (private clean-slate
   from 2026-06-17, superseded), `LeSearch-AI/lesearch` (Rust control-plane spike,
   2026-04), `LeSearch-AI/lesearch-protocol` (spec superseded by docs/agents/CONTRACTS.md),
   `LeSearch-AI/lesearch-factory` (superseded by the in-repo factory),
   `aryateja2106/lecoder-mconnect` (the old CLI the lesearch.ai waitlist page linked).
3. Keep: `LeSearch-AI/mesh-install`, `LeSearch-AI/.github`.
Reply with the list you approve and the archives get applied in one pass.

## TestFlight 0.8.0 upload (the only way a stranger gets the phone app)
`sh scripts/release-testflight-asc.sh --dry-run` runs clean on this tree (0.8.0, build
202609221043) but stops on purpose: App Store Connect still holds the stray **1.0**
pre-release, so shipping 0.8.0 is a version downgrade — testers on 1.0 must delete and
reinstall, which wipes their Keychain and every pairing. The publish plan (T20, owner
human) already names the decision and the hatch:
`MESH_ALLOW_VERSION_DOWNGRADE=1 sh scripts/release-testflight-asc.sh --external`
(then Beta App Review for the public link `lesearch.ai/beta`). The upload can also hang
on a Keychain dialog for `asc` (memory: shell-slowness-and-asc-keychain) — keep the Mac
unlocked. Until then the public link serves the 2026-08-27 build; the landing and
getting-started say "TestFlight" and are correct the moment this lands.

## The Mac has no tool-calling local model, so the full gate cannot go green
`check-brain` (inside `check-overnight`, inside the full gate) asks each machine's local
model server for a tool call. The Pi and the Jetson answer (ollama, qwen3:1.7b and
qwen3:4b). This Mac answers on ollama :11434 but its only model is `nl2shell-local`
(811 MB, a text fine-tune): it replies `get_time machine="jetson"` as prose instead of
emitting a tool call, so the check fails — correctly. Whatever served the Mac's brain
earlier today (edge0 on :8001, per the overnight record) is not running any more; the
Mac daemon restarted around 09:00 and Tailscale had stopped.

Two ways to close it, both yours because both cost something of yours:
- `ollama pull qwen3:1.7b` on this Mac (~1.4 GB download, the same model the Pi runs), or
- start whatever served :8001 before (edge0 / LM Studio) and leave it running.

Until then the publish ledger cannot carry a green full-gate line at a current sha, and
`scripts/check-published.sh` will say so rather than pretend. Nothing about the app, the
daemon, the site or the feedback pipeline is affected — this is one live check about local
models on one machine.
