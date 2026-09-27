---
name: factory-implement
description: Claim and implement one ready GitHub issue, run fail-closed gates, obtain independent verification, and open a draft pull request.
---

# Factory implementation for cursor-agent

Read `docs/factory/CONTRACT.md`, `docs/factory/CHARTER.md`, and then the canonical workflow
in `.claude/skills/factory-implement/SKILL.md`. Use a fresh cursor-agent session or subagent
for the verifier context. If an independent context is unavailable, stop before opening a
non-draft pull request and say plainly that the verification step did not run.
