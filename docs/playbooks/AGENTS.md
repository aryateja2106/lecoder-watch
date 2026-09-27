# docs/playbooks/ — step-by-step runbooks for Apple's build tools (Xcode, simulators, device installs, TestFlight) and the local daemon

**Read first:** [README.md](README.md) (the three iron rules + which playbook), then the one playbook for your task, e.g. [xcode-cli.md](xcode-cli.md).
**Surface:** docs
**Serialized (one agent at a time):** none.
**Prove a change:** no dedicated check — add scripts/check-playbooks.sh (at minimum: every command a playbook names still exists in `scripts/`). Docs-only: `./.claude/scripts/gates.sh fast`.
**Traps:**
- Written 2026-08-28 (all six files, `git log`); versions and Xcode paths in them may lag. Confirm `DEVELOPER_DIR` against `CONTEXT.md:113-116` (Xcode 27 beta for the physical devices).
- Root `AGENTS.md` still does not link this folder (`README.md:10-13` asks for it; grep of AGENTS.md: 0 hits). Only `docs/README.md:36` leads here. Do not edit AGENTS.md yourself; flag it.
- `docs/README.md:36` says "Six imperative playbooks"; there are five plus this README.
- `daemon-and-mesh.md:75-77` documents the sanctioned restart path (`svc` skill); that is for when Arya asks. To test a change, boot a side-port daemon instead (AGENTS.md rule 5, `daemon-and-mesh.md:4`).
- Anything whose proof is on the physical iPhone or Watch (`device-install.md`) must be handed back to Arya ("What an agent cannot verify", AGENTS.md).
**SDLC stage:** Build and Deploy — the exact commands to compile, install and release.
**Map:** see the file list above (6 files).
