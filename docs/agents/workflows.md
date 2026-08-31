# Mesh workflows

Edit this file when you want a different default. Agents should read it
when you type `/mesh`, `/taste`, or `/see`, or when you attach a recording.

Claude Code's built-in `/design` is the artboard canvas. Never add a repo
command named `design` — that would hide the built-in skill.

Factory and OpenSpec stay the product queue. Matt and Addy are the general
engineering loop. Do not invent a second issue tracker.

## Pick a skill

| You have | Type | Then |
|---|---|---|
| A screen recording or screenshots of the live app | `/see` | `from-recording` |
| New UI artboards (Claude Design canvas) | `/design` (built-in) | leave it alone; do not override |
| Watch, iPhone, widget, or terminal UI to polish | `/taste` | `meshwatch-ui-taste` |
| A Claude Design artboard / HTML mockup to turn into SwiftUI | say so | `claude-design-to-meshwatch-swiftui` after taste |
| Landing page *story* — scroll-driven rebuild of `web/` | `/scrollcraft` | `scrollcraft` (eight grammars, one peak, own footage) |
| Landing page *polish* of the existing `web/index.html` | `/impeccable` | `impeccable`, then Taste `design-taste-frontend` |
| A factory queue item ready to build | `/factory` | `factory-implement` — not Matt's `/implement` |
| A product idea that needs a Mesh spec | `/opsx:propose` | `openspec-propose` |
| A general spec (not a Mesh OpenSpec change) | `/spec` | `spec-driven-development` |
| A spec that needs tasks | `/plan` | `planning-and-task-breakdown` |
| Implementation in thin slices | `/build` | `incremental-implementation` |
| Something broken | say so | `debugging-and-error-recovery` / `diagnosing-bugs` |
| A PR or diff to review | say so | `code-review-and-quality` |
| An interview to lock the problem | `/grill` | `grill-with-docs` |

## From a recording

1. Drop the video or frames in the chat, or put the file in `docs/recordings/`.
2. Say what you want: review, fix, or implement.
3. The agent watches first. It does not guess the missing seconds.
4. It names the surface (watch / iPhone / desktop / landing), the job on
   screen, and what is wrong or missing.
5. It then follows the row in the table above.

Physical Watch and iPhone proof still belongs to you. An agent can watch a
recording and change code; it cannot feel the crown or the wrist banner.

## Collisions — ours wins

- Mesh product queue: `factory-triage` / `factory-implement`, not Matt `triage` / `implement`.
- Mesh spec change: `openspec-propose`, not Addy `spec-driven-development`.
- Native app UI: `meshwatch-ui-taste` first. Do not run `/impeccable init` at
  the repo root (it would write `PRODUCT.md` / `DESIGN.md` over `CONTEXT.md`).
- Landing *story*: `/scrollcraft`. Landing *polish*: `/impeccable`. Never add a
  repo command named `design`. Build from our own recordings, not generated
  video, unless Arya asks.
