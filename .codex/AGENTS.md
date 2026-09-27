# .codex/ — project settings for Codex (OpenAI's coding assistant): the code-lookup tool it may use and the safety hook it must run

**Read first:** `hooks.json` (the merge/push guard), `config.toml` (codegraph lookup server), root `AGENTS.md` (the brief Codex reads)
**Surface:** agent-config
**Serialized (one agent at a time):** `hooks.json` — Edit denied in `.claude/settings.json:22`; policy file
**Prove a change:** no dedicated check — add `scripts/check-block-merge.sh` (the script `hooks.json:10` runs); `config.toml` applies only once the folder is trusted in `~/.codex/config.toml` (`config.toml:1`)
**Traps:**
- `hooks.json:10` runs `.claude/hooks/block-merge.sh`: Codex inherits its false positives (reads that mention `.codex/` plus `>`, `sed`, `rm`, `cp`, `mv`, `tee` are blocked, `block-merge.sh:59-62`).
- Load-bearing: `docs/factory/CHARTER.md:54`.
- `config.toml:4` needs the `codegraph` CLI on PATH; built by `sh scripts/codemap.sh`.
**SDLC stage:** Build (3.4 hooks) and Deploy (5.2 merge gate) for the Codex harness.
**Map:** see the file list above: `config.toml`, `hooks.json`, `skills/` (6 OpenSpec skills).
