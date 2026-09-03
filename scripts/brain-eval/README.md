# brain-eval — grade any local brain, or compare two, on the things that matter

One scorecard, two engines. `eval.ts` speaks plain OpenAI Chat Completions, so the
same probes grade **our own inference** (MferenceServer) and **LM Studio** and print
comparable results. It answers the questions that decide whether a local model can run
a long task on a Mac — and, in compare mode, **which of two models is better for what**.

| Capability | What the probes actually do |
|---|---|
| function calling | one correct call, then a full two-turn tool loop with `tool_call_id` |
| terminal actions | answer a known `[y/N]` prompt; **read the pane before typing into a quiet session** |
| browser actions | sequence navigate/type/click; **use only selectors from a page outline, not priors** |
| cli agent | with the seven tools `mesh-code` really gives the model: write a script without a multi-line command; list before editing an unnamed file; `str_replace` with a **unique** anchor; change approach after exit 127; call `finish` when done |
| ios simulator | boot the right device by **listed UDID** (the `booted` alias is the trap); read the file a **test digest** names |
| macos control | activate Notes **before** typing — keystrokes go to the frontmost app |
| reads images | send an `image_url` part and classify: supported, or refused as text-only |
| long-running economics | prefix reuse (`cached_tokens`) and stop-sequence discipline |

The use-case probes are one decision each on a fixed history, shaped byte-for-byte like
the tool results `install/payload/agent/tools.ts` emits. Every one targets a specific
small-model failure and reports it as a **tag** — `heredoc`, `hallucinated-path`,
`non-unique-find`, `repeated-failing-command`, `no-finish`, `guessed-selector`,
`blind-send`, `wrong-target`, `typed-into-wrong-app`, and so on — because the tags, not the
pass counts, say which dataset to build.

A model failing a probe is a **measurement**, not a script error — the run still exits 0.
Use `--strict` to fail a CI job on it.

```sh
bun run scripts/brain-eval/eval.ts --endpoint http://127.0.0.1:8080/v1   # our inference
bun run scripts/brain-eval/eval.ts --endpoint http://127.0.0.1:1234/v1   # LM Studio
bun run scripts/brain-eval/eval.ts --endpoint … --json docs/results/qwen36.json
```

`--model` (defaults to whatever the endpoint lists first), `--api-key`, `--timeout`
(default 120 s — local models are slow), `--temperature` (default 0), `--max-tokens`
(512), `--only ids`, `--strict`.

## Comparing two brains

```sh
bun run scripts/brain-eval/eval.ts \
  --a http://127.0.0.1:8080/v1 --label-a qwen36-mference \
  --b http://127.0.0.1:1234/v1 --label-b ornith-lmstudio \
  --repeat 3 --json docs/results/compare-$(date +%Y%m%d).json \
  --jsonl docs/results/compare-$(date +%Y%m%d).jsonl
```

Compare mode streams every probe (identical bodies plus `stream_options.include_usage`,
which both servers honour), so each row carries **time-to-first-token and tokens/sec**
alongside pass/fail. Reasoning models are handled: `<think>` blocks — whether they arrive
as `reasoning_content`, `reasoning`, or inline tags — are split from the answer, and
the reported TTFT is to the first *answer* token, which is what an agent loop waits for.
A one-token reply shows `—` for tok/s: one token is not a rate. A server that buffers a
tool call and emits it in a burst is caught (far fewer deltas than tokens, or an impossible
rate) and its rate is measured first-byte → done, labelled `burst` in the JSON.

**Sequencing is what makes the numbers mean something.** Probes run one at a time, each
fully on one endpoint then fully on the other, first-mover alternating per probe, never
concurrent — our engine serves one generation at a time and keeps a single cached prefix,
and both models share one GPU and one SSD. A probe's time is the sum of its turns'
request→done windows, so harness work never reaches the speed rule. `--repeat 3` makes
the status the **majority** over repeats (a tie is a fail; the table shows the pass rate),
takes the speed median over passing repeats only, and flags `nondeterministic` when the
repeats disagreed.

**The verdict rule is deliberately dull**, per capability: more passes wins; then fewer
fails — an honest "unsupported" beats a wrong action, which is why a text-only engine
loses *reads images* without being penalised elsewhere; then a ≥20 % median-speed edge on
paired passes; otherwise the literal word *tie*. No overall winner is computed. Two more
lines always print: *unsupported on A, passing on B* (the capability boundary) and
*failure modes by endpoint* (what to fix, or what to train on).

`--jsonl` writes one row per (endpoint, probe, turn) with the **full request, tools,
assistant message and timing** — the seed of the dataset, and the failures are its most
valuable rows. `--cache-bust` appends one nonce to every system prompt on both sides so
TTFT is cold-prefill; `--no-warmup` skips the untimed warm-up request each endpoint gets
first (LM Studio loads lazily, our engine's expert cache starts cold).

**Budget.** `--max-tokens` defaults to 2048 on both, because a reasoning model spends it
on the think block before answering. A reply the budget cut off before any answer is tagged
`truncated`, listed under *not compared*, and never counted as a fail — raise the budget
and re-run. The streamed sample is the sample that is graded: fragments that do not
reassemble into JSON are tagged `malformed-arguments`, never quietly re-sampled.

**Temperature.** Default 0 on both. Ornith's authors recommend 0.6 for coding and never 0
(reasoning models can loop in the think block at 0); Mference defaults to 0.2 when unset,
LM Studio to the model's own default. Set it explicitly, and it is recorded in
`settings`. For a like-for-like, run once at 0 and once at 0.6 rather than mixing.

## Verifying the harness itself

`stub-server.ts` is a deliberately dumb endpoint with three personas, so every branch —
including every failure branch — gets exercised without a model:

| Persona | Imitates | Used to prove |
|---|---|---|
| `textonly` (default) | MferenceServer: refuses images, reports `cached_tokens`, no reasoning | the baseline: **19 pass · 0 fail · 1 unsupported**, the unsupported one being images |
| `vision` | LM Studio with a reasoning model: accepts images, streams `reasoning_content`, no `cached_tokens`, 20× slower frames | compare mode detects the capability boundary and the speed gap |
| `dumb` | a small model at its worst | each use-case probe fails **for its designed reason** — a probe failing for the wrong reason is a harness bug |

```sh
sh scripts/check-brain-eval-compare.sh   # boots all three, runs both modes, ~50 assertions
sh scripts/check-brain-eval-sse.sh       # the stream accumulator, synthetic + live
```

Point the eval at a dead port to confirm it can fail: `--endpoint http://127.0.0.1:8098/v1 --timeout 3000`.

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
