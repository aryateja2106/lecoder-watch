# install/payload/share/skills/ — the five instruction sets LeSearch AI installs for every coding agent on a user's machine, so the agent can build and install apps and search past work

**Read first:** `scripts/check-mesh-skills.sh` (the rules a shipped skill must pass), `bin/mesh:1697-1716` (install to `~/.agents/skills`, symlinks from `~/.claude`, `~/.codex`, `~/.cursor`), the one `SKILL.md` you are changing
**Surface:** agent-config
**Serialized (one agent at a time):** none; but adding or removing a skill needs the count in `scripts/check-mesh-skills.sh:72` changed, which is a human edit (see `../skills-staged/README.md`)
**Prove a change:** `sh scripts/check-mesh-skills.sh` (identifiers, symlinks, install/uninstall against a temp HOME); for `native-app-builder`/`pwa-local-app-builder` also `sh scripts/check-mesh-apps.sh`
**Traps:**
- A skill must work on a stranger's Mac: no Team ID, no bundle prefix, no port that is not meshd's (AGENTS.md "Where things are" table; banned strings at `check-mesh-skills.sh:19`).
- This repo's `.claude/skills/<name>` and `.cursor/skills/<name>` are committed symlinks here (`check-mesh-skills.sh:37-48`): editing a skill changes this repo's own agents immediately. A real directory in `.agents/skills/<name>` is a stale copy.
- Five skills, not four: `AGENTS.md:124` and `check-mesh-skills.sh:2` still say four; `mesh-knowledge` was added 2026-09-23.
- `mesh upgrade` does not refresh skills (`bin/mesh:1179-1181`); users get edits only from a fresh install. `mesh uninstall` leaves `~/.agents/skills` behind (read, not run).
- One AGENTS.md here only; each skill folder is described by its own `SKILL.md` (`scripts/folder-index.py:164`).
**SDLC stage:** Build — policy-as-code the product hands to its users' agents; Design/Build guidance for this repo through the symlinks.
**Map:** the five `*/SKILL.md` `description:` lines; `apple-native-apis/references/` holds 8 topic files.
