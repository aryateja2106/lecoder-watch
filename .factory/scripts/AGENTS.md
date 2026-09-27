# .factory/scripts/ — three helper scripts for the AI work queue: set up its GitHub labels, sanity-check its setup, and prove a test really catches the bug it claims to

**Read first:** `prove-test.sh` (failing-test-first proof), `doctor.sh` (setup check), `bootstrap-github.sh` (queue labels)
**Surface:** checks
**Serialized (one agent at a time):** `prove-test.sh` — `factory-verify` depends on it (`.agents/skills/factory-verify/SKILL.md:10`)
**Prove a change:** `sh scripts/gate-lint.sh` (bash syntax of every `.factory/scripts/*.sh`, `gate-lint.sh:16`); behaviour: no dedicated check — add `scripts/check-prove-test.sh` on a throwaway repo
**Traps:**
- `prove-test.sh` needs a clean working tree and rewrites it temporarily (`prove-test.sh:2-3`); never run it with uncommitted work.
- `bootstrap-github.sh --apply` creates GitHub labels (`:7`); without `--apply` it only previews. Needs `gh` signed in (`:9-15`).
**SDLC stage:** Test (negative test proof) and Deploy (queue setup).
**Map:** see the file list above: `bootstrap-github.sh` (44 lines), `doctor.sh` (71), `prove-test.sh` (107).
