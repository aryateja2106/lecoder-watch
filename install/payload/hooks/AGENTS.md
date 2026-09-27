# install/payload/hooks/ — a shell snippet that starts the Mac-only cmux terminal bridge every time a terminal window opens

**Read first:** `cmux-bridge.zsh` (57 lines, the comments are the history), `docs/playbooks/daemon-and-mesh.md` (the three bridges and their ports)
**Surface:** installer
**Serialized (one agent at a time):** none
**Prove a change:** `sh scripts/check-bridge-kill-scope.sh`; then time a new interactive zsh (it must stay imperceptible, `cmux-bridge.zsh:3-5`)
**Traps:**
- Sourced by EVERY interactive zsh on a Mac with cmux (`install/install.sh:520-527`); any port kill must be `lsof -ti "tcp:$port" -sTCP:LISTEN` (`cmux-bridge.zsh:37-42`, AGENTS.md rule 8), or opening a terminal kills meshd.
- Hardcodes `/opt/homebrew/bin/bun` (`cmux-bridge.zsh:44`) while the installer puts bun in `~/.bun/bin` (`install/install.sh:125-137`).
- Not `install/hooks/` (examples). `docs/playbooks/daemon-and-mesh.md:15` wrongly says this is not in the install payload.
**SDLC stage:** Build — product code shipped to users: a shell snippet that starts the cmux bridge in every new terminal (see [docs/sdlc/3-build.html](../../../docs/sdlc/3-build.html))
**Map:** 2 tracked files; run `git ls-files install/payload/hooks` to list them.
