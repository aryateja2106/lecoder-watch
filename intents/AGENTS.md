# intents/ — Stage 1 of the lifecycle: one file per idea, written before anything is designed or built

**Read first:** [README.md](README.md) (what an intent is, the chain to spec, plan, PR), then every file with `status: accepted`.
**Surface:** specs
**Serialized (one agent at a time):** none — but only Arya sets `status: accepted` or `closed`.
**Prove a change:** `sh scripts/check-intents.sh` (front matter present, the five headings present, file named `YYYY-MM-DD-<slug>.md`).
**Traps:**
- `intent/` (singular, at the root) is unrelated: it is the local brain's tool catalogue and acceptance cases for `scripts/check-intent.sh`. Never write playbook intents there.
- An intent describes the outcome, never the implementation. If a draft names files or functions, it has become a plan; move that text to `openspec/changes/<slug>/tasks.md`.
- Findings from reviews, monitoring or security scans that need more than a one-file fix land here as `status: draft` with `source:` set; they do not skip to code.
**SDLC stage:** Plan — this folder is Stage 1: one intent file per idea, written before any design (see [docs/sdlc/1-plan.html](../docs/sdlc/1-plan.html))
**Map:** [INDEX.md](INDEX.md) (generated; regenerate with python3 scripts/folder-index.py)
