# .github/ — GitHub settings: the automatic check pipeline and the 75-item product backlog file that becomes GitHub issues

**Read first:** `workflows/ci.yml` (what runs on every PR), `backlog.json` (backlog source), `docs/backlog.md` (its readable form)
**Surface:** data
**Serialized (one agent at a time):** `workflows/ci.yml` (load-bearing, `docs/factory/CHARTER.md:50`)
**Prove a change:** `backlog.json`: `python3 -m json.tool .github/backlog.json` then regenerate `docs/backlog.md` (generator unverified; `docs/README.md:44` says edit the JSON, not the Markdown); CI: see `workflows/AGENTS.md`
**Traps:**
- `backlog.json` is 1351 lines; `scripts/sync-issues.sh:17` turns it into GitHub issues — running that creates real issues.
- No `CODEOWNERS`, no PR template, no root `REVIEW.md`: review rules live only in skills and `CLAUDE.md`.
**SDLC stage:** Plan (backlog) and Deploy (CI).
**Map:** see the file list above: `backlog.json`, `workflows/ci.yml`.
