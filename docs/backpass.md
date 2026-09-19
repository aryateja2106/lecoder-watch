# backpass: training the briefs from real sessions

`AGENTS.md` is what every agent loads on every session. Until now it changed only when a
human remembered a failure and edited it. [backpass](https://github.com/kunchenguid/backpass)
closes that loop: it reads the transcripts that Claude Code, Codex and Cursor left on disk
for this repo, works out which instructions helped, which were ignored, and which mistakes
no instruction covers, and proposes edits backed by verbatim quotes from those sessions.
Nothing is written until you accept each edit in `backpass apply`.

Its own description of the mechanism:

```
AGENTS.md / CLAUDE.md + skills (the weights)
  → agent session               (forward pass)
  → transcript on disk          (loss signal)
  → backpass: collect, distill, calculate loss, aggregate
  → backpass: propose edits      (diffs + skill extractions)
  → you accept or reject         (the human gate)
  → back to the weights
```

## What is set up in this repo

- `.backpassrc.json` at the root. backpass always resolves its config and state at the git
  toplevel, whatever directory you run it from, so there is exactly one config.
- Three memory files listed, in order: `AGENTS.md` (the engineering brief, trained by
  default), `CLAUDE.md` (a one-line `@AGENTS.md` pointer; backpass recognises it as such
  and warns if anyone turns it back into a second brief), and `marketing/AGENTS.md` (the
  marketing brief, trained on request with `--target`).
- `.backpass/` (evidence, proposals, the review page) is per checkout and ignored by git.
- Skill extractions for the engineering brief go to `.agents/skills/`; for the marketing
  brief, pass `--skills-dir marketing/.agents/skills`.

## Prerequisites, once per machine

```sh
npm install -g backpass acpx@latest   # Node 22.5 or newer
```

backpass has no API keys of its own. Every model call goes through `acpx` to a harness you
have already logged into; `claude` or `codex` on your PATH and authenticated is enough. Its
default ladder tries Codex first for the cheap per-transcript pass and falls back to Claude.

## The engineering brief (root AGENTS.md)

```sh
cd <repo root>
backpass scan          # which sessions it found, and how it tied them to this repo
backpass               # analyze, aggregate, propose. Never writes.
backpass apply         # review each edit with its evidence; accept or reject; then it writes
backpass status        # cache state and the budget bar
```

## The marketing brief (marketing/AGENTS.md)

```sh
cd <repo root>
backpass --target marketing/AGENTS.md --skills-dir marketing/.agents/skills --budget 14000
backpass apply --target marketing/AGENTS.md
```

Why the flags:

- `--target` names one configured memory file. A typo fails loudly and lists the valid
  names. Without it, a run trains the first file in the list, the engineering brief.
- `--skills-dir` is where an extracted skill is written. Extractions from the marketing
  brief belong under `marketing/`, not at the root.
- `--budget` is the always-loaded token cap backpass enforces: the brief plus every skill
  description it can see. Measured on 2026-09-19 with `backpass status --skills-dir
  marketing/.agents/skills --budget 14000`: 9,841 tokens of descriptions (the 50 marketing
  skills plus the 23 root entries backpass also sees) and 1,335 for the marketing brief,
  about 11,200 in all. The default 5,000 would put every run into shrink mode before the
  brief had a single line. The root brief keeps the default: 4,171 of 5,000.

`status` does not take `--target`; it always shows every configured file. To see the
marketing surface billed the way a marketing run bills it, pass the other two flags:

```sh
backpass status --skills-dir marketing/.agents/skills --budget 14000
```

Switching between the two targets re-analyses the sampled transcripts (one cheap model call
each, up to 100), because evidence is cached against the memory surface it was judged
against. That is by design, not a broken cache.

## Two things it will tell you that are fine

- When `apply` writes an extracted skill: `.claude/skills is a real directory, not a
  symlink to ../.agents/skills`. True. The root `.claude/skills/` mixes OpenSpec's own skill
  copies with per-skill symlinks the `skills` CLI made, so it cannot be one directory link.
  The consequence is only that a skill backpass extracts into `.agents/skills/` is not
  visible to Claude Code until you add its link:
  `ln -s ../../.agents/skills/<name> .claude/skills/<name>`. Same for the marketing folder,
  with `marketing/` in front of both paths.
- On root runs: `marketing/AGENTS.md is a separate memory file and will NOT be updated`.
  Also true, and the reason `--target` exists.

## What was verified when this was set up

In the checkout that created this file (2026-09-19): `backpass init`, `backpass status`,
`backpass scan` (it found one Claude Code session and tied it to this repo at tier 1), and
target resolution for `marketing/AGENTS.md` with the flags above (`--target nope` and
`--target CLAUDE.md` both refused, naming the valid targets). A full run and `apply` need
`acpx` and an authenticated harness, which that container did not have, so the first real
backward pass is yours to run.

## What backpass reads

Local transcript stores, directly from disk, never uploaded: `~/.claude/projects/`,
`~/.codex/sessions/`, `~/.cursor/chats/`, and four other harnesses. A session belongs to
this repo when its working directory was inside one of this repo's worktrees or clones, or
when it recorded one of this repo's git remotes. Sessions run inside `marketing/` count the
same as any other. Sessions from your other machines can join over SSH, configured in
`~/.config/backpass/config.json`, never in the repo file.

Obvious secrets are redacted before a distilled transcript reaches a model, and every
proposed edit needs quotes from at least two distinct sessions. One bad session never
rewrites the brief.
