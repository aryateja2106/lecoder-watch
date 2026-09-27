# install/payload/share/skills-staged/ — a waiting room for a finished skill before a person approves adding it to the shipped set

**Read first:** `README.md` (the promotion steps)
**Surface:** agent-config
**Serialized (one agent at a time):** none
**Prove a change:** `sh scripts/check-mesh-skills.sh` after promotion (count at `scripts/check-mesh-skills.sh:72`)
**Traps:**
- Promotion raises a count in an existing check, which an unattended run may not do (CLAUDE.md non-negotiable 3); stage here and hand back.
- Nothing is staged today (`README.md:10`). Files here still ship inside `~/.mesh/share` (`install/install.sh:518`), but `mesh skills install` reads only `share/skills/` (`bin/mesh:1718-1722`).
**SDLC stage:** Deploy — a holding area so adding a shipped skill stays a human approval (see [docs/sdlc/5-ship.html](../../../../docs/sdlc/5-ship.html))
**Map:** see the file list above (1 file).
