# install/payload/share/ — the help page for the `mesh` command and the skills LeSearch AI gives to every coding agent on a user's machine

**Read first:** `skills/AGENTS.md`, `bin/mesh:1697-1716` (how skills are installed and linked)
**Surface:** agent-config
**Serialized (one agent at a time):** none
**Prove a change:** `sh scripts/check-mesh-skills.sh` (skills); no dedicated check for `man/` — add scripts/check-man-page.sh
**Traps:**
- Copied to `~/.mesh/share` by `install/install.sh:518`; NOT refreshed by `mesh upgrade` (`bin/mesh:1179-1181`), so an edit here reaches existing users only via a fresh install (`install.sh --force`).
- `install.sh --uninstall` removes `~/.mesh/share` (`install.sh:649`), but `mesh uninstall` leaves `~/.agents/skills` (`bin/mesh:2246-2300`; read, not run).
**SDLC stage:** Build — skills that act as policy for users' agents, plus the `mesh` man page (see [docs/sdlc/3-build.html](../../../docs/sdlc/3-build.html))
**Map:** 21 tracked files; run `git ls-files install/payload/share` to list them — `man/`, `skills/`, `skills-staged/`
