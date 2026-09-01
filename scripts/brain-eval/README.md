# brain-eval — grade any local brain on the four things that matter

One scorecard, two engines. `eval.ts` speaks plain OpenAI Chat Completions, so the
same probes grade **our own inference** (MferenceServer) and **LM Studio** and print
comparable results. It answers the only questions that decide whether a local model
can run a long task on a Mac:

| Capability | What the probe actually does |
|---|---|
| function calling | one correct call, then a full two-turn tool loop with `tool_call_id` |
| terminal actions | given meshd-shaped `agent_output`/`agent_send` tools, answer a blocked `[y/N]` prompt |
| browser actions | given navigate/type/click, sequence them for a real instruction |
| reads images | send an `image_url` part and classify: supported, or refused as text-only |
| long-running economics | prefix reuse (`cached_tokens`) and stop-sequence discipline |

A model failing a probe is a **measurement**, not a script error — the run still exits 0.
Use `--strict` to fail a CI job on it.

```sh
bun run scripts/brain-eval/eval.ts --endpoint http://127.0.0.1:8080/v1   # our inference
bun run scripts/brain-eval/eval.ts --endpoint http://127.0.0.1:1234/v1   # LM Studio
bun run scripts/brain-eval/eval.ts --endpoint … --json docs/results/qwen36.json
```

`--model` (defaults to whatever the endpoint lists first), `--api-key`, `--timeout`
(default 120 s — local models are slow), `--only ids`, `--strict`.

## Verifying the harness itself

`stub-server.ts` is a deliberately dumb endpoint that imitates a **text-only** engine,
so every branch — including the image-refusal path — gets exercised without a model:

```sh
bun run scripts/brain-eval/stub-server.ts --port 8099 &
bun run scripts/brain-eval/eval.ts --endpoint http://127.0.0.1:8099/v1
# 9 pass · 0 fail · 1 unsupported   ← the unsupported one is images, correctly classified
```

Point it at a dead port to confirm it can fail: `--endpoint http://127.0.0.1:8098/v1 --timeout 3000`.

## Running it against our own inference (on the Mac)

Mference is **Apple Silicon + macOS 15+ + Metal only**. It cannot run on a Linux CI box
or in a cloud agent container, so these commands are for Arya's Mac.

```sh
# 1. Install a model. Streams from HuggingFace and repacks; never materializes the
#    full checkpoint, needs no 2x disk, and --resume picks up an interrupted run.
swift run -c release MferenceRepack --model qwen36 --output ~/models/qwen36.gturbo

# 2. Serve it on loopback.
swift run -c release MferenceServer --model ~/models/qwen36.gturbo --max-context 32768

# 3. Grade it.
bun run scripts/brain-eval/eval.ts --endpoint http://127.0.0.1:8080/v1 \
  --json docs/results/qwen36-$(date +%Y%m%d).json
```

Do not kill a running LM Studio to make room (AGENTS.md rule 5) — pick a window when
it is idle, or run the server on another port with `--port`.

## Which model fits 30–40 GB of disk

Storage is the real constraint, not RAM. Figures are upstream's, measured on their
hardware — replace them with our own once step 3 above has run here.

| Family | `--model` | Disk | RAM | Verdict for this machine |
|---|---|---|---|---|
| Maple Preview 20B-A1B | `maple` | ~6.6 GB | ~645 MiB | fits easily; smallest real option |
| Gemma 4 26B-A4B | `gemma4` | ~14.3 GB | ~2 GB | fits; the app's default |
| **Qwen 3.6 35B-A3B** | `qwen36` | **~19.6 GB** | ~2.2 GB @ 32 slots (~1.45 GB @ 16) | **fits — first choice** |
| Qwen 3.8 27B dense | `qwen38` | ~15.1 GB | ~15 GB | disk fits, RAM does not |
| DeepSeek-V4-Flash | `deepseekV4Flash` | ~91 GB | ~6.8 GB | does not fit |
| Inkling-Small | `inklingSmall` | ~148 GB | ~9 GB | does not fit |

Qwen 3.6 + Maple together is ~26 GB and leaves headroom. Qwen 3.6 + Gemma 4 is ~34 GB
and is tight against a 40 GB budget.

## The RAM number has a catch — read this before quoting ~1.45 GB

That figure is the **16-slot** expert-cache profile. Slots are a speed dial: more wired
slots means fewer SSD reads and more tokens/sec, at more RAM. The profile is chosen from
host memory in
[`RuntimeConfiguration.defaultExpertCacheSlots`](../../references/mference/Sources/Mference/Runtime/Configuration/RuntimeConfiguration.swift):

- ≥ 24 GiB host → **96 slots, ~6.8 GB wired**
- ≥ 16 GiB host → 32 slots
- below that → 16 slots, ~1.45 GB

Upstream's `MferenceCLI` exposes `--expert-cache-slots`; upstream's `MferenceServer` does
not, and builds its runtime from the auto rule at `ServerInference.swift:218-232` with no
override. **Our fork adds the flag** —
[`references/patches/0001-mference-server-expert-cache-slots.patch`](../../references/patches/0001-mference-server-expert-cache-slots.patch),
applied with `git apply` in a fork checkout and built on the Mac. `scripts/start-brain.sh`
passes it, and refuses to start rather than silently ignoring a profile an unpatched
server cannot honour.

**Prefer 32 slots (~2.2 GB), not 16.** Two reasons, both from the scheduler rather than
taste. 16 is the exact floor chunked prefill can schedule —
`(maxPendingDepth + 1) * tileExperts` in `PrefillRoutedTileScheduler` — so it has zero
headroom. And because slots buy speed, 16 is also the slowest rung, which hurts most on a
prefill-bound workload. 32 is still a fraction of the 96 that auto-selects on a 24 GB
machine. Keep 16 reachable for measuring the smallest possible footprint; do not make it
the default.

Whatever profile you pick, **measure throughput, not just footprint**: `eval.ts` times
every probe, so run it against both and compare. A profile that halves memory and thirds
throughput is not obviously a win.

## Running it against LM Studio

No build step — LM Studio serves an OpenAI-compatible endpoint on `:1234` once a model
is loaded and the server is started. This is the path for people who already have a
local setup and will not compile Swift. It is also, today, **the only way to get image
input**, because Mference strips vision towers at repack: load a vision model (a
Qwen-VL or UI-TARS build) in LM Studio and the `vision` probe flips from `N/A` to `PASS`.
