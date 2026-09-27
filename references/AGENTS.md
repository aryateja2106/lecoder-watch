# references/ — outside reading: quality checklists the agent skills point to, and a list of other projects worth borrowing from

**Read first:** `reference-projects.md` (what to take from each outside project, and what to leave), `definition-of-done.md` (the standing bar), the checklist a skill names
**Surface:** docs
**Serialized (one agent at a time):** none
**Prove a change:** no dedicated check — add `scripts/check-references.sh` (for example: every skill's `references/*.md` link resolves)
**Traps:**
- `external/` is gitignored (`.gitignore:53`): clones, research outputs and models live only on this Mac. `codegraph`/`graphify` do not index it (`reference-projects.md:18`, `codegraph.json:3`); open the file a row names.
- `scripts/check-intent.sh:23` expects a model binary under `external/models/needle2/`; it is absent, so that check skips. Fetching it is Arya's decision.
- The six checklists are generic (e.g. `security-checklist.md:3` "web application security"), not written for this product. Skills cite them as `../../references/*.md` (`.claude/skills/security-and-hardening/SKILL.md:77`), which from `.claude/skills/<name>/` resolves to `.claude/references/` — a path that does not exist. Treat those links as pointing here (unverified whether any harness rewrites them).
- `patches/0002-edge0-openai-tool-calls.patch` applies to a gitignored clone (`patches/README-0002.md:17-18`); the streaming path is unpatched.
- Before building something a listed project already solved, write the ADR first and cite the file (`reference-projects.md:18`).
**SDLC stage:** Design + Build — checklists feed the skills; reference projects feed design decisions.
**Map:** INDEX.md (9 tracked direct entries; generate with `python3 scripts/folder-index.py`)
