# Runbook — getting a local model answering, on the Mac

Every command in this file needs the Mac. None of it has been run: the session that wrote
it had no Swift toolchain, no Metal and no access to this machine. **Treat each step's
output as the evidence, not this file's expectations** (AGENTS.md rule 1).

Context and the decisions behind these choices:
[handoff-2026-09-01-local-inference.md](handoff-2026-09-01-local-inference.md) ·
[openspec/changes/local-native-inference/tasks.md](../openspec/changes/local-native-inference/tasks.md)

Record what actually happens in the task list, next to the step it verifies.

---

## 0. Confirm you are where you think you are

```sh
cd ~/Projects/lecoder-watch
git log -1 --date=short --format='%h %cd %s'      # date should be recent — rule 2
git branch --show-current
```

Work continues on `claude/local-model-inference-g3i08e` unless PR #119 has merged, in which
case branch fresh from `main`.

## 1. Move the fork out of this repo, and push the patch

It was cloned to `~/Projects/lecoder-watch/Mference` — a repo inside a repo. Move it:

```sh
mv ~/Projects/lecoder-watch/Mference ~/Projects/Mference
```

The patch is committed there as `0b00b2d` and has never been pushed. The cloud session
could not push (its GitHub grant covered only `lecoder-watch`). Push it:

```sh
cd ~/Projects/Mference
git log --oneline -3          # expect 0b00b2d on top of upstream 297c0080
git remote -v                 # expect origin = aryateja2106/Mference
git push -u origin HEAD
```

If the commit is not there, the patch re-applies cleanly against the pinned commit:

```sh
git apply ~/Projects/lecoder-watch/references/patches/0001-mference-server-expert-cache-slots.patch
```

## 2. Build

Already done once on this machine — release build clean, `swift test` 1102 tests / 179
suites, zero failures. Repeat only if the tree changed:

```sh
cd ~/Projects/Mference
swift build -c release --product MferenceServer
```

Expect ~96 s. Warnings are pre-existing upstream (`DFlash2Int4Slab`, `KVPageStore`,
`RealForwardRunner`, `MTPAttachTool`, `MapleAddRMSNormTests`). If a warning names
`ServerArguments.swift`, `ServerInference.swift` or `main.swift`, that one is ours.

Confirm the flag actually exists in the binary — this is what `start-brain.sh` checks:

```sh
.build/release/MferenceServer --help | grep -- --expert-cache-slots
```

## 3. Install a model

Disk is no longer the constraint: **175.21 GB free** as of 2026-09-01. Start with Qwen 3.6
because it is the one the whole proposal is written against.

```sh
df -h /                       # record before
swift run -c release MferenceRepack --model qwen36 --output ~/models/qwen36.gturbo
df -h /                       # record after; expect ~19.6 GB consumed
```

Resumable — re-run it if interrupted, do not restart from scratch. It should never need
2× the final size in transient space; if it does, that is a finding worth writing down.

Other families upstream supports, with this machine's verdict at 175 GB free:

| Family | Disk | Verdict here |
|---|---|---|
| `qwen36` (35B-A3B) | ~19.6 GB | Install first |
| `gemma4` | ~14.3 GB | Fits |
| `maple` | ~6.6 GB | Fits |
| `qwen38` (27B dense) | fits disk | **~15 GB RAM** — see the memory note below |
| `deepseekV4Flash` | ~91 GB | Now fits (did not at 30–40 GB free) |
| `inklingSmall` | ~148 GB | Would leave ~27 GB on the boot volume — do not |

## 4. Start the server

**Do not stop LM Studio to free the port** (AGENTS.md rule 5). `start-brain.sh` refuses to
start on a port something already answers on, deliberately.

```sh
cd ~/Projects/lecoder-watch
scripts/start-brain.sh --model ~/models/qwen36.gturbo --slots 32 \
  --bin ~/Projects/Mference/.build/release/MferenceServer
```

**Why 32 and not the built-in rule.** On a ≥24 GiB host the engine picks 96 slots
(~6.8 GB wired). Activity Monitor on 2026-09-01 showed 16.39 GB of 24 GB already in use
with 4.26 GB compressed — roughly 7.6 GB of real headroom. 96 slots would take nearly all
of it on a laptop you are also working on. 16 is the floor chunked prefill can schedule
`(maxPendingDepth + 1) * tileExperts` and has zero headroom, and it is also the slowest
rung. 32 (~2.2 GB) is the working default.

## 5. Measure it — six numbers, honestly

This is the step that turns every borrowed figure in the proposal into ours. Run the same
model twice and record **both** memory and speed, because a footprint win that thirds
throughput is not a win.

For each of `--slots 32` and `--slots auto`:

- **peak RSS** — Activity Monitor's Memory column for `MferenceServer`, or
  `/usr/bin/time -l` on the process
- **tokens/sec** — generation, from the eval output
- **time to first token** — prefill

Write all six into
[openspec/changes/local-native-inference/tasks.md](../openspec/changes/local-native-inference/tasks.md)
Stage 2, with this host's RAM stated alongside, since the slot profile is chosen from it.

## 6. Grade it

```sh
mkdir -p docs/results
bun run scripts/brain-eval/eval.ts \
  --endpoint http://127.0.0.1:8080/v1 \
  --json docs/results/qwen36-2026-09-01.json
```

`--only IDS` re-runs single probes, `--strict` exits 1 on any failure, `--timeout MS`
defaults to 120000. Full flags: `bun run scripts/brain-eval/eval.ts --help`.

**Expect `reads images: UNSUPPORTED`.** Mference strips vision towers at repack
(`RepackPlanner.isExcludedTensorName`) in every family. That is the engine being text-only,
correctly detected — not a failed run.

Then grade LM Studio identically, with a vision model loaded, and confirm the image probe
flips to PASS:

```sh
bun run scripts/brain-eval/eval.ts \
  --endpoint http://127.0.0.1:1234/v1 \
  --json docs/results/lmstudio-2026-09-01.json
```

LM Studio did not appear in Activity Monitor's top processes — start it first, and commit
both JSON files so the two scorecards can be read side by side.

## 7. Point the daemon at it

Boot a **second** daemon on a spare port rather than touching the running one — rule 5:

```sh
MESHD_PORT=8898 MESHD_HOST=127.0.0.1 MESHD_TOKEN=throwaway \
  bun run install/payload/meshd/server.ts
```

```sh
curl -s 127.0.0.1:8898/brain | python3 -m json.tool            # fast path
curl -s '127.0.0.1:8898/brain?probe=1' | python3 -m json.tool  # measures image support
curl -s '127.0.0.1:8898/brain?need=images' | python3 -m json.tool
```

`reachable:false` is a 200, not an error — a missing brain is a state. Read tokens from
`~/.mesh/token` into a shell variable; never print or paste one.

## 8. Drive one real task through it

```sh
mesh-code brain
mesh-code run "…one real multi-step task…" --cwd ~/Projects/<something>
mesh-code show <id>
```

Paste the transcript **including failures** into Stage 4 of the task list. A run that needed
three corrections is a more useful record than one that worked.

---

## Before any commit

```sh
sh scripts/check-all.sh
```

Not optional. `check-docs-index.sh` will fail if a doc lands in `docs/` without a row in
[docs/README.md](README.md); `check-agent-risk-parity.sh` fails if `risk.ts` drifts from
`Shared/RiskClassifier.swift`.

## If something looks broken daemon-side

Ask the machine what it is actually running before debugging app code — AGENTS.md rule 6
cost a week once:

```sh
curl -s http://127.0.0.1:8899/health | python3 -m json.tool | head -20
```

An old daemon answers **200 with the old shape**, which is indistinguishable from the
feature being broken.
