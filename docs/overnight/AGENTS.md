# docs/overnight/ — dated logbooks of unattended night runs: what was planned, what landed, proof logs and screenshots

**Read first:** `<date>/STATE.md` (slice table, the resume point), `<date>/REPORT.md` (morning summary for Arya), the newest `<date>/HANDOFF-*.md`.
**Surface:** docs
**Serialized (one agent at a time):** the active run's `STATE.md` (one run owns it); finished dated folders are history, do not rewrite.
**Prove a change:** `sh scripts/check-published.sh` (structural half; it reads `2026-09-21/STATE.md`, the gate log and `2026-09-21/shots/*.png` — `scripts/check-published.sh:48-49,166-167`).
**Traps:**
- Convention (one folder today, `2026-09-21/`): `STATE.md` + `REPORT.md` + `HANDOFF-<date>[-topic].md` + raw `*.txt` gate/check logs + `shots/`. Per-slice run records go in `docs/factory/runs/`, not here.
- `check-published.sh` hard-codes `docs/overnight/2026-09-21/` (`:48-49`); `PUBLISHED.md:9` names `2026-09-21/gate-full-publish-2026-09-23-tail.txt` as the gate log. Renaming or pruning that folder turns the finish line red.
- The live half needs at least 4 committed `2026-09-21/shots/*.png` (`check-published.sh:166-167`). A plain `sh scripts/check-all.sh` rewrites those PNGs (sim-fleet check), dirtying the tree; only `MESH_SHOTS_DIR=<tmp>` avoids it (`:120-122,141-146`). Do not commit the rewritten PNGs by accident.
- `STATE.md:3` names a worktree and branch (`feat/lesearch-ai-overnight-2026-09-21`) that were right that night; do not take branches from it (AGENTS.md rule 2).
- `folder-index.py` skips `docs/overnight` for AGENTS.md but will generate `2026-09-21/INDEX.md` (12 entries); its header links an AGENTS.md that folder does not have.
**SDLC stage:** Build, Test — logbooks of unattended build nights; their committed gate logs are the proof `PUBLISHED.md` quotes (see [docs/sdlc/3-build.html](../sdlc/3-build.html), [docs/sdlc/4-test.html](../sdlc/4-test.html))
**Map:** 37 tracked files; run `git ls-files docs/overnight` to list them; `2026-09-21/INDEX.md` is generated (regenerate with python3 scripts/folder-index.py).
