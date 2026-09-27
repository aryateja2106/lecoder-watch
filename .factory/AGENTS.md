# .factory/ — settings for the "software factory" (the queue-driven way AI agents pick up GitHub issues): which checks are required, plus three helper scripts

**Read first:** `gates.conf` (required gates per level), `docs/factory/README.md` (setup and dry run), `.claude/scripts/gates.sh` (the reader)
**Surface:** checks
**Serialized (one agent at a time):** `gates.conf` — Edit denied (`.claude/settings.json:18`); human-owned policy
**Prove a change:** `./.claude/scripts/gates.sh fast` (reads `gates.conf` at `gates.sh:38-42`; GREEN on 2026-09-27); `./.factory/scripts/doctor.sh` for factory config sanity (not run in this pass)
**Traps:**
- `gates.conf` is `source`d as shell (`gates.sh:41`): anything but plain assignments executes.
- A gate name outside `types lint test build audit mutation architecture` makes the verdict MISCONFIGURED (`gates.sh:50-59`).
- Load-bearing (`docs/factory/CHARTER.md:51`); `block-merge.sh:59` blocks shell writes that name `.factory/gates.conf`.
**SDLC stage:** Test — defines what "verified" means for every factory run.
**Map:** see the file list above: `gates.conf` (10 lines), `scripts/` (3 scripts).
