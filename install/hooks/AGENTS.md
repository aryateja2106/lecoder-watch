# install/hooks/ — example settings showing how to connect Claude Code, Codex and other coding agents to phone and watch alerts

**Read first:** `install/payload/bin/mesh` `cmdHooks` at `:1622` (the real registration), `docs/agents/harnesses.md` §B (how to onboard a CLI)
**Surface:** installer
**Serialized (one agent at a time):** none
**Prove a change:** `sh scripts/check-package-mesh-install.sh` (pins `claude-settings.meshwatch.example.json`, `:22`); otherwise no dedicated check — add scripts/check-hook-examples.sh
**Traps:**
- Examples only. `mesh hooks install` (called by `install/install.sh:537-548`) writes the real entries into `~/.claude/settings.json`; change behavior there, not here.
- Copied to `~/.mesh/hooks` by `install/install.sh:517`, beside the LIVE `payload/hooks/cmux-bridge.zsh` (`install.sh:520-527`): two source folders, one destination.
- `meshwatch` in the file names is a retired brand, but renaming the Claude example breaks `scripts/check-package-mesh-install.sh:22`, and existing checks may not be edited unattended (CLAUDE.md non-negotiable 3).
- `mesh upgrade` never refreshes these (`payload/bin/mesh:1027-1035` syncs `payload/hooks/` only).
**SDLC stage:** Deploy — onboarding examples shipped for a user's own agents (see [docs/sdlc/5-ship.html](../../docs/sdlc/5-ship.html))
**Map:** see the file list above (3 files).
