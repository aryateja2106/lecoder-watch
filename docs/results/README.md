# docs/results — measured scorecards, committed

Every JSON here was produced by `scripts/brain-eval/eval.ts` against a real endpoint on a
real machine, and is committed so a claim about a model can be traced to the run that
made it. Nothing in this directory is hand-edited.

| File pattern | Produced by |
|---|---|
| `<model>-<engine>-<date>.json` | single-endpoint mode: `eval.ts --endpoint … --json` |
| `compare-<date>.json` | compare mode: `eval.ts --a … --b … --json` |
| `compare-<date>.jsonl` | the dataset export: one row per (endpoint, probe, turn), full request and reply |

State the host in the commit message: chip, RAM, and — because the harness cannot see
another process's memory — the RSS of each server read from Activity Monitor or `ps`.
A `reads images: UNSUPPORTED` on our engine is the engine being text-only, correctly
detected, not a failed run.

None yet: as of 2026-09-02 no local model has been graded on the Mac. The first files here
will be the Qwen 3.6 (Mference) vs Ornith (LM Studio) comparison from
[docs/local-brain-runbook.md](../local-brain-runbook.md) step 6.
