---
run_id: 2026-09-21T192500Z-overnight-S7-picker
stage: implement
started_at: 2026-09-21T19:25:00Z
finished_at: 2026-09-21T19:45:00Z
status: succeeded
issue: none
pull_request: none
gate_level: fast
gate_status: GREEN
verifier: not-run (orchestrator review; check-harness-picker + check-launchable + build)
human_required: false
---

# S7 — harness picker from /doctor (b6ddc7e)

Antigravity (gemini-3.1-pro-high). One AGENT_CLIS catalogue in doctor.ts; server.ts imports it; handoff asserts subset;
DoctorReport.agents + launchable on the clients; both pickers driven by it with the static list as fallback.
