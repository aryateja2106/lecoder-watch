# marketing/

The marketing workspace for LeSearch Mesh. It is a folder inside the main repo, not a
second repo, but everything an agent needs for marketing work lives here and nothing here
is loaded when you work at the repo root.

```
marketing/
├── AGENTS.md                  the marketing brief: rules, where things go, how skills work
├── CLAUDE.md                  one line, @AGENTS.md, so Claude Code loads the same brief
├── README.md                  this file
├── skills-lock.json           pins the installed skills (written by `npx skills`)
├── .agents/
│   ├── product-marketing.md   the shared product context every marketing skill reads first
│   └── skills/                50 skills from coreyhaines31/marketingskills (real files)
└── .claude/skills/            50 symlinks into ../.agents/skills, for Claude Code
```

Drafts go in `drafts/<channel>/` and research in `research/`; both are created by the
first file that lands there.

## Why a folder, and why this layout

Three agents work on this repo (Claude Code, Codex, Cursor) and each looks for skills in
a different place. One canonical copy plus links keeps them in sync:

| Agent | What it reads | How it finds this folder |
|---|---|---|
| Claude Code | `.claude/skills/` (symlinks here), `CLAUDE.md` chain | Loads `marketing/.claude/skills/` when started in `marketing/`; from the repo root, loads it the first time it reads or edits a file under `marketing/`. Name clashes appear as `marketing:<skill>`. [Docs](https://code.claude.com/docs/en/skills) |
| Codex | `.agents/skills/` | Scans `.agents/skills` from the cwd up to the repo root, so start Codex in `marketing/`. It also loads the root `AGENTS.md`. [Docs](https://developers.openai.com/codex/skills) |
| Cursor | `.agents/skills/` (also `.claude/skills/`) | Discovers nested `.agents/skills` folders anywhere in the repo and scopes them to files under `marketing/`. [Docs](https://cursor.com/docs/context/skills) |

The root `.agents/skills/` and `.claude/skills/` are untouched: `npx skills list` at the
root still shows the engineering skills only.

Two costs worth knowing. The 50 skill descriptions add up to about 8,900 tokens, and a
harness loads every description on every turn (bodies load only when a skill fires). Codex
caps its skill list at about 8,000 characters, shortens descriptions, and may drop some;
invoke a missing one by name with `$name`. If that is too much, keep the subset you use:

```sh
cd marketing
npx skills remove sms video image paywalls popups   # whatever you will not use
```

## Working here

1. Start your agent in `marketing/` (`cd marketing && claude`, or `codex`).
2. Run `/product-marketing` first. It reads `.agents/product-marketing.md`, summarizes it,
   and offers to update sections. Every `[NEEDS: ...]` marker in that file is a fact we do
   not have yet; the sooner they are filled, the better every draft gets.
3. Ask for the piece. The right skill triggers on plain language ("write the App Store
   description" uses `aso`, "plan the TestFlight launch" uses `launch`), or invoke it
   directly: `/launch`, `/copywriting`, `/social`, `/seo-audit`, `/pricing`.
4. Drafts land in `drafts/<channel>/`. A human posts them. Agents never publish.

The rules the brief enforces (what may and may not be claimed) are in `AGENTS.md`. They
come from `docs/launch-posts.md` "Notes on what NOT to claim", the README's "What is, and
is not, true yet", and the privacy promise.

## Keeping the skills current

```sh
cd marketing
npx skills update                    # pull newer versions of what skills-lock.json lists
npx skills list                      # what is installed here
npx skills add coreyhaines31/marketingskills --skill <name> -a claude-code codex cursor -y
```

Always run these from `marketing/`. The CLI installs relative to the current directory,
which is the whole reason the separation holds; run it at the repo root and the skills
land there instead.

The library's `tools/` folder (integration guides for GA4, Stripe, Mailchimp and so on) is
not installed by the CLI. Sixteen skills mention it; read those guides upstream at
https://github.com/coreyhaines31/marketingskills/tree/main/tools.

## Writing a house skill

The HubSpot and Futurepedia guide to Claude skills and the marketingskills contributing
rules agree on the parts that matter:

- One skill, one job. A folder `.agents/skills/<name>/` with a `SKILL.md`; `name` in the
  frontmatter must equal the folder name (lowercase, hyphens).
- The `description` decides whether the skill ever fires. Say what it does and when to use
  it, in third person, with the trigger phrases a person would actually type. Under 1,024
  characters. Vague descriptions get skipped.
- Keep `SKILL.md` under 500 lines; put long reference material in `references/` and link to
  it.
- Do not use Claude-only `` !`command` `` injection in a shared skill; Codex and Cursor
  would show the literal text.
- Then link it for Claude Code: `ln -s ../../.agents/skills/<name> .claude/skills/<name>`.

`npx skills init <name>` scaffolds the folder. The two foundation skills the HubSpot guide
recommends first, brand voice and audience profile, are already covered by the Brand Voice
and Target Audience sections of `.agents/product-marketing.md`, which every installed
skill reads; there is no need to duplicate them.

## Shared context: backpass

The brief in `AGENTS.md` is a memory file that `backpass` trains from the agent sessions
that actually ran in this repo. Setup, prerequisites and the exact commands for both the
engineering brief and this one are in [docs/backpass.md](../docs/backpass.md). The short
version, run from the repo root:

```sh
backpass --target marketing/AGENTS.md --skills-dir marketing/.agents/skills --budget 14000
backpass apply --target marketing/AGENTS.md
```

`--budget 14000` is not generosity: the always-loaded surface backpass bills is the brief
plus every skill description it can see, measured at 9,841 tokens of descriptions plus
1,335 for the brief (about 11,200) on the day this was set up.
