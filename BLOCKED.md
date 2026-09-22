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

## Which files may go to the public LeSearch-AI/mesh repo
The public repo is a curated snapshot at 0.4.x; the landing's Changelog / Roadmap / issues
links point at it. Publishing 0.8.0 there means choosing what of this tree is public
(docs/overnight, docs/factory/runs, references/ and memory notes are not). Decide the file
list; the push itself is a branch, never a force-push.
