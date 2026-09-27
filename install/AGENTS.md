# install/ — the one-command installer that puts LeSearch AI (daemon, `mesh` command, agent alert helpers) on a Mac or Linux machine

**Read first:** `install/install.sh` (what a user's machine actually runs), `docs/mesh-cli-and-remote-install.md` (user flow; its hardcoded-token lines are stale), `docs/product/PRODUCT.md` §3 (the install contract)
**Surface:** installer
**Serialized (one agent at a time):** `install/install.sh` (token handling `install.sh:789-800`, service env `:820-843`); anything about pairing, auth, tokens (AGENTS.md "Must be serialized")
**Prove a change:**
- `sh scripts/check-install-idempotent.sh && sh scripts/check-mesh-onboarding.sh && sh scripts/check-package-mesh-install.sh && sh scripts/check-mesh-uninstall.sh` (each uses a temp HOME)
- `sh scripts/check-token-rotate.sh` if tokens or the service env changed; then `./.claude/scripts/gates.sh fast`
- Real proof is a run against a throwaway `MESH_HOME` + `MESH_LABEL_PREFIX` (`install.sh:155-156`), never the live `~/.mesh` (AGENTS.md rule 5)
**Traps:**
- Re-running the one-liner is a no-op when `meshd/server.ts` VERSION matches and the daemon answers (`install.sh:767-774`); bin/skills/bridge edits without a VERSION bump never land. `--force` reinstalls.
- `scripts/package-mesh-install.sh:15-30` tars the working tree, not `git ls-files`: untracked files (this AGENTS.md included) ship to users. `scripts/release-mesh-install.sh:40` has no clean-tree check.
- `install.sh:515` replaces `~/.mesh/bin` wholesale; macOS Accessibility is granted per binary, so a needless reinstall kills watch input (`install.sh:737-742`).
- Whatever install.sh writes, `mesh uninstall` must remove (AGENTS.md design principle 5). It does not remove the rmux-bridge service or `~/.agents/skills` today (`payload/bin/mesh:2181-2244`; read, not run).
- Never print the token; the install summary prints only its location (`docs/mesh-cli-and-remote-install.md:134-136`).
- tmux session names must not contain a dot (`install.sh:169`, `docs/playbooks/daemon-and-mesh.md:121-136`).
**SDLC stage:** Deploy (the only path onto a machine) and Maintain (upgrade, repair, uninstall).
**Map:** `docs/agents/CODEMAP.md` section `install/`; `hooks/` and `payload/` each have an AGENTS.md.
