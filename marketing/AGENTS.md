# Marketing brief for LeSearch Mesh

You are in `marketing/`, the marketing workspace of the LeSearch Mesh repo. The root
[AGENTS.md](../AGENTS.md) still applies here (secrets, the worktree-date check, grep can
lie). This file adds what marketing work needs and nothing else.

The product in one line: use your Mac from your wrist. A small daemon (`meshd`) runs on
each machine you own; the iPhone and Apple Watch app talk to it over your own network.
When a coding agent stops to ask a question, your wrist buzzes and you answer from there.

## Read this first, every session

`.agents/product-marketing.md` is the shared product context: positioning, audience,
competitors, voice, and what we may and may not claim. Every marketing skill reads it
before doing anything. If it is wrong, fix it there (bump the version, add a changelog
line), not in the output. To revise it interactively, run the `product-marketing` skill.

## Rules that keep the copy honest

1. **Every claim traces to a file in this repo.** README.md, CHANGELOG.md, ROADMAP.md,
   web/index.html, docs/competitive-position.md. Version numbers come from CHANGELOG.md.
   No invented metrics, ratings, testimonials, customer quotes, or logos. If a piece needs
   one we do not have, write `[NEEDS: ...]` in the draft and say so in your summary.
2. **Do not claim it works from anywhere.** It works where the phone can reach the
   machine: the same LAN, or a VPN the user already runs (it was built against Tailscale).
   There is no relay and no hole-punching. See README "What is, and is not, true yet".
3. **Privacy wording is a public promise.** Say "no cloud relay, nothing of yours passes
   through our servers". Never say "no telemetry": the daemon sends one anonymized
   heartbeat a day, off with `MESHD_TELEMETRY=off`. Copy must agree with
   `web/privacy.html`, the README Telemetry section, and `install/payload/meshd/telemetry.ts`.
4. **Do not call competitors broken.** "They relay through their cloud" is a factual
   difference. Anything stronger invites a correction we would lose.
5. **Lead with the watch terminal.** No competitor ships a crown-scrollable,
   auto-following, VoiceOver-accessible terminal on the wrist (docs/competitive-position.md).
   Mac screen control and the one-command install and uninstall come next. Do not race
   Moshi on the phone terminal.
6. **Push delivery to a cold real device is still unproven.** Say "free beta, tell us if
   your wrist buzzes", not "verified end to end".
7. **Agents draft; a human posts.** Nothing here gets published, submitted, scheduled, or
   sent by an agent. Before putting a date on a launch, check ROADMAP.md "Now — shipping":
   the DNS record for mesh.lesearch.ai and Beta App Review both gate any public push.

## Where things go

- `drafts/<channel>/` for copy: `drafts/linkedin/`, `drafts/x/`, `drafts/app-store/`,
  `drafts/email/`. One file per piece, date-prefixed (`2026-09-19-launch-post.md`).
  The one existing draft is [docs/launch-posts.md](../docs/launch-posts.md), written for
  0.3.0; update its version numbers before reusing it.
- `research/` for competitor and audience notes. Start from
  [docs/competitive-position.md](../docs/competitive-position.md) (August 2026).
- `.agents/product-marketing.md` for anything that should change every future piece.
- The landing page in `web/` is live on Vercel. Propose copy changes as a draft here first,
  edit `web/index.html` only when asked, and keep `web/privacy.html` in step with the
  README and `telemetry.ts` when you do.

## Skills

The marketingskills library (coreyhaines31/marketingskills, 50 skills) is installed only
here: real files in `.agents/skills/` (Codex and Cursor read that path), symlinks in
`.claude/skills/` (Claude Code reads that path). Nothing is installed at the repo root.
Start Claude Code or Codex in `marketing/` to have them all loaded. From the repo root,
Claude Code loads them the first time it reads or edits a file under `marketing/`.

- `product-marketing` first, always. Then the skill for the job: `launch`, `copywriting`,
  `aso` (the App Store listing), `social`, `seo-audit`, `pricing`, `competitor-profiling`.
- Update: `cd marketing && npx skills update`. Remove one: `npx skills remove <name>`.
  `skills-lock.json` pins what is installed.
- Codex caps the skill list it shows the model (about 8,000 characters) and shortens
  descriptions first. If a skill does not surface, invoke it by name with `$name`.
- A house skill goes in `.agents/skills/<name>/SKILL.md` with a symlink at
  `.claude/skills/<name>`. Write the description in third person, under 1,024 characters,
  with the trigger phrases spelled out. Details in README.md here.

## The shared context loop (backpass)

This file is trained, not only edited. `backpass` reads the Claude Code, Codex and Cursor
sessions that ran in this repo and proposes evidence-backed edits to a brief; a human
accepts or rejects each one. Its config is the root `.backpassrc.json`, and this brief is
listed there as a second memory file. Commands: [docs/backpass.md](../docs/backpass.md).

What it needs from you: work in real sessions (they are the training data), and when an
instruction here turns out to be wrong or missing, say so in the session in plain words.
That sentence is what backpass quotes as evidence.
