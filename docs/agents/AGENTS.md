# docs/agents/ — the navigation maps coding agents read before opening code: which file, which route, which check

**Read first:** [CODEMAP.md](CODEMAP.md) (pick one file, not grep), [CONTRACTS.md](CONTRACTS.md) (daemon routes, capabilities, relay commands), [CHECKS.md](CHECKS.md) (what each `scripts/check-*` proves).
**Surface:** docs
**Serialized (one agent at a time):** `CODEMAP.md`, `CONTRACTS.md`, `CHECKS.md`, `SYMBOLS.md` are generated — never hand-edit, regenerate (header line 3 of each).
**Prove a change:**
- Generated maps: `python3 scripts/codemap-index.py` (or `sh scripts/codemap.sh` for map + graph), then `sh scripts/check-codemap.sh` (OK at e666aab).
- Hand-written files (`UI-MAP.md`, `codebase-map.md`, `harnesses.md`, `domain.md`, `issue-tracker.md`, `triage-labels.md`): no dedicated check — add scripts/check-agent-docs.sh.
**Traps:**
- `SYMBOLS.md` is 658 lines: grep it (`grep -n '^| <name> ' docs/agents/SYMBOLS.md`), never read it whole (`SYMBOLS.md:3`).
- A stale generated map is a red `check-codemap.sh`, which is a red `gates.sh full` (`index.md:21`). Adding a file, route or capability anywhere means regenerating here.
- `domain.md:34` still calls the product "LeSearch Mesh"; the canonical name is LeSearch AI since 2026-09-21 (`CONTEXT.md:5-8`). `domain.md:13` says `docs/adr/` does not exist; ADRs live flat as `docs/adr-2026-09-22-*.md`.
- `issue-tracker.md:3` points at issues on `aryateja2106/lecoder-watch`; user feedback issues land on `LeSearch-AI/mesh` (`PUBLISHED.md:25`). Two trackers.
- The harness-loaded CLAUDE.md names `docs/agents/workflows.md` as the skill index; that file does not exist in this tree (e666aab).
**SDLC stage:** Build, Test — institutional knowledge an agent reads before touching code, and `CHECKS.md` says what proves what (see [docs/sdlc/3-build.html](../sdlc/3-build.html), [docs/sdlc/4-test.html](../sdlc/4-test.html))
**Map:** [INDEX.md](INDEX.md) (generated; regenerate with python3 scripts/folder-index.py)
