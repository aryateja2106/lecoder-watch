---
name: factory-verify
description: Independently verify a factory pull request, including fail-closed gates, negative test proof, scope, and load-bearing review.
---

# Factory PR verification for cursor-agent

Read `docs/factory/CONTRACT.md`, `docs/factory/CHARTER.md`, and then the canonical workflow
in `.claude/skills/factory-verify/SKILL.md`. Use a fresh session for any critic pass and the
shared `.factory/scripts/prove-test.sh` procedure for negative test proof.

Read the diff cold. Ignore the implementer's account of what was done.
