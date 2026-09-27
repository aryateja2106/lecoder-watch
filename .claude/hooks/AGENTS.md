# .claude/hooks/ — automatic safety scripts that run before or after an AI assistant acts, so it cannot merge code or push to the main branch on its own

**Read first:** `block-merge.sh` (the live guard), `../settings.json:26-36` (how it is wired), `docs/factory/CHARTER.md` (why)
**Surface:** agent-config
**Serialized (one agent at a time):** `block-merge.sh` — shared by Claude Code and Codex (`.codex/hooks.json:10`)
**Prove a change:** `sh scripts/gate-lint.sh` (syntax only, `gate-lint.sh:23-24`); behaviour: no dedicated check — add `scripts/check-block-merge.sh` that pipes `{"tool_input":{"command":"…"}}` into the hook and asserts exit 2 / exit 0
**Traps:**
- `block-merge.sh:59-62` also blocks harmless reads: a command naming `.claude/`, `.agents/` or `.codex/` plus a space-preceded `>`, `sed`, `tee`, `rm`, `mv`, `cp` exits 2 (measured: `diff -rq .claude/a .agents/b >/dev/null`). Words that merely start with those letters count too.
- A test that pipes canned JSON into the hook must not contain the blocked words literally, or the hook blocks the test command itself.
- It is defence in depth only (`block-merge.sh:4-6`); GitHub branch protection is the real boundary. Cursor has no equivalent hook.
- `stop-published.sh` is dormant: it says it is wired from `settings.local.json` (`:5`) but nothing references it now. Wiring it into shared `settings.json` would hold every session in a publish loop (`:81-87`).
- Blocks are not logged anywhere (`block-merge.sh:26-32` writes stderr only).
**SDLC stage:** Build, Deploy — deterministic guardrails (playbook 3.4) and the approval gate on merges and protected branches (5.2) (see [docs/sdlc/3-build.html](../../docs/sdlc/3-build.html), [docs/sdlc/5-ship.html](../../docs/sdlc/5-ship.html))
**Map:** see the file list above: `block-merge.sh` (65 lines), `stop-published.sh` (88 lines).
