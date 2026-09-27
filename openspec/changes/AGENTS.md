# openspec/changes/ — open proposals: one folder per decision the owner has not finished making

**Read first:** `../config.yaml` (rules at lines 102-113), then the change's `proposal.md`, then its `tasks.md`
**Surface:** specs
**Serialized (one agent at a time):** each change folder, one agent at a time; its `tasks.md` checkboxes especially
**Prove a change:** `openspec validate <change-name> --no-interactive`; `openspec list` shows ticked/total tasks
**Traps:**
- Both changes date from 2026-08-24 and later work has overtaken them: `local-brain-and-harness` by `docs/adr-2026-09-22-local-brains-and-streaming-moe.md` and `docs/adr-2026-09-22-on-device-brain.md`; `reach-my-mac-from-anywhere` by the product now running over the user's own Tailscale (CONTEXT.md:17). Read the ADRs before acting on a task.
- `tasks.md` checkboxes are not maintained: the weak-token check exists in `install/payload/meshd/doctor.ts:25-28`, yet `reach-my-mac-from-anywhere/tasks.md:14` is unticked. Verify in code before assuming a task is open.
- Create new changes with the `openspec-propose` skill (`.claude/skills/openspec-propose/`), not by hand; close them with `openspec-archive-change`.
- A proposal is not a playbook `intent.md`: it has no "Affected users and systems" or "Constraints" heading. New asks start in `intents/`.
**SDLC stage:** Plan, Design, Build — `proposal.md` ≈ intent plus design options, `specs/*/spec.md` ≈ spec deltas, `tasks.md` ≈ the Build-stage plan with proofs (see [docs/sdlc/1-plan.html](../../docs/sdlc/1-plan.html), [docs/sdlc/2-design.html](../../docs/sdlc/2-design.html), [docs/sdlc/3-build.html](../../docs/sdlc/3-build.html))
**Map:** see the file list above (2 change folders)
