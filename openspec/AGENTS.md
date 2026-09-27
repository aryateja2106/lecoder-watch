# openspec/ — written proposals and requirements for bigger product changes, before anyone builds them

**Read first:** `config.yaml` (house rules every proposal must follow), `specs/terminal-sessions/spec.md` (the one accepted spec), `docs/product/PRODUCT.md` (the spec that is actually enforced)
**Surface:** specs
**Serialized (one agent at a time):** `config.yaml` (shared brief for Claude Code, Codex and Cursor — root AGENTS.md "Working alongside other agents")
**Prove a change:** `openspec validate --all --no-interactive` (CLI 1.6.0 at /opt/homebrew/bin; 2026-09-27: 3 passed, 0 failed) and `openspec list` for task counts. No `scripts/check-*` runs it — no dedicated check — add `scripts/check-openspec.sh`.
**Traps:**
- Not the product's source of truth any more. `scripts/check-product-spec.sh:2-9` enforces `docs/product/PRODUCT.md`; nothing enforces anything here. Every file was last changed 2026-08-24 (`git log -- openspec`). Edit PRODUCT.md for product behaviour; open a change here only for a decision that needs a proposal.
- `config.yaml` is stale: it says "LeSearch Mesh" (config.yaml:4; retired name per CONTEXT.md "Names") and "no telemetry" (config.yaml:65), which contradicts root AGENTS.md design principle 2 and `web/privacy.html:118-132`. Its route list (config.yaml:44-58) omits `/agents/:n/chat`, `/exposures`, `/built-apps`; use `docs/agents/CONTRACTS.md`.
- The useful part is `config.yaml:102-113`: a proposal names the owner's complaint, Non-goals and user skill level; every task ends in a runnable proof; device-only tasks are marked for Arya.
- Nothing has ever been archived (no `changes/archive/`). Both open changes are 30 days old: 1/16 and 0/11 tasks ticked (`openspec list`).
- Playbook intents go in `intents/`, not here and not in `intent/` (see `intents/AGENTS.md`).
**SDLC stage:** Design — `specs/` holds accepted requirements; `changes/` holds proposals that mix Plan (why) and Design (requirements) with a task list close to a Build plan (see [docs/sdlc/2-design.html](../docs/sdlc/2-design.html))
**Map:** see the file list above (3 entries: `config.yaml`, `changes/`, `specs/`)
