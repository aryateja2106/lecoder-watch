# openspec/changes/reach-my-mac-from-anywhere/ — the open decision on how the phone reaches a home Mac from outside the house, and the security work that must come first

**Read first:** `proposal.md` (constraints, options A/B/C, owner questions at :156-163), `specs/connectivity/spec.md`, `tasks.md`
**Surface:** specs
**Serialized (one agent at a time):** `tasks.md`; any code it leads to in pairing, auth or tokens is serialized (root AGENTS.md "Must be serialized")
**Prove a change:** `openspec validate reach-my-mac-from-anywhere --no-interactive`; for each task, the command the task names
**Traps:**
- The owner decision A vs B (`tasks.md:29-30`) is unticked; do not build a relay. The product has since shipped over the user's own Tailscale (CONTEXT.md:17, :40), which `proposal.md:66-67` argued against as a default. Ask Arya which stands.
- `tasks.md:11-17` spells out the retired placeholder token; root AGENTS.md (Secrets paragraph) explains that writing it down is why it kept returning. Do not copy it anywhere new. The weak-token check it asks for now exists in `install/payload/meshd/doctor.ts:25-28`.
- Transport security is still absent: `grep -c tls install/payload/meshd/server.ts` = 0 while `grep -c .` = 1517, so the file is not binary-skipped (AGENTS.md rule 3). `specs/connectivity/spec.md:41-54` blocks any off-network reach until pinned TLS exists.
- Watch networking limits (`proposal.md:47-53`: HTTP data tasks only) rule out WebRTC, QUIC and WireGuard on the wrist. Re-read before proposing one.
- Several tasks need Arya's iPhone on cellular (`tasks.md:20-21`); an agent cannot prove them.
**SDLC stage:** Plan, Design — options and requirements waiting on the owner; Build is blocked on the decision point (see [docs/sdlc/1-plan.html](../../../docs/sdlc/1-plan.html), [docs/sdlc/2-design.html](../../../docs/sdlc/2-design.html))
**Map:** see the file list above (`proposal.md`, `tasks.md`, `specs/connectivity/spec.md`)
