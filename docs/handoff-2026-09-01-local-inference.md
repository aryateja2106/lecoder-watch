# Handoff — local inference and the harness decision (2026-09-01)

Written at the end of a cloud session, for a session starting locally on the Mac.
**The next session's focus is the deepseek-harness question**, with the local model
underneath it.

Everything factual here was either measured or read out of the source. Where something is
assumed, it says so. Nothing in this file repeats what a spec, a README or a code comment
already says — it links instead.

## Start here

| Read | For |
|---|---|
| [AGENTS.md](../AGENTS.md) | The eight rules. Rule 1 (verify by running) and rule 5 (never restart live services) both bite in this work. |
| [openspec/changes/local-brain-and-harness/proposal.md](../openspec/changes/local-brain-and-harness/proposal.md) | Why a harness at all, and why deepseek-harness specifically. **The decision the next session has to make.** |
| [openspec/changes/local-native-inference/](../openspec/changes/local-native-inference/) | The model half: proposal, tasks, spec deltas. The task list is the work queue. |
| [docs/local-brain-runbook.md](local-brain-runbook.md) | The exact commands, in order, to get a local model answering. |
| [docs/local-inference-references.md](local-inference-references.md) | The engine study, verified line by line. |
| [install/payload/agent/README.md](../install/payload/agent/README.md) | What `mesh-code` is and the three counter-intuitive things in it. |
| PR [#119](https://github.com/aryateja2106/lecoder-watch/pull/119) | Everything below, as a diff. Draft, CI green, `mergeable_state: clean`. |

Branch: `claude/local-model-inference-g3i08e`, 16 commits ahead of `main`, pushed.
Root [HANDOFF.md](../HANDOFF.md) is a **July artifact** — its "work on `backup/2026-07-02`,
never push" instruction is long dead. Do not follow it.

## Why this handoff exists

The previous session ran in a **cloud container**, not on the Mac. It had a fresh clone of
`lecoder-watch` and nothing else: no Swift toolchain, no Metal, no `adb`/`xcrun`, no access
to `~/.mesh`, no LM Studio, no way to see the machine. Every "needs the Mac" marker in the
task lists traces to that.

That is also why the previous session's diagnosis of the unresponsive terminal was wrong.
It guessed a full disk. The storage panel shows **175.21 GB free**. Whatever wedged the
terminal, it was not that, and it is no longer reproducible — treat it as closed unless it
recurs.

## The machine, as measured 2026-09-01

From the storage and Activity Monitor panels, not inferred:

- **Disk: 175.21 GB free** of 494.38 GB. Developer 21.37 GB, System Data 127.66 GB.
- **RAM: 24.00 GB physical.** Used 16.39 GB · Cached 3.77 GB · **Swap 523.4 MB** ·
  pressure **green**. App 7.63 GB, Wired 3.54 GB, **Compressed 4.26 GB**.
- Running and not to be restarted (AGENTS.md rule 5): `cmux` (pid 22579), `Device Hub`,
  two `omp`, `Maccy`, `Raycast`, several `claude`.
- **LM Studio does not appear** in the top processes by memory. The list is truncated at
  ~130 MB, so it may be idle rather than absent — but confirm it before relying on the
  image path, because that path is the only way this product reads a screenshot today.

**Two things follow from those numbers, and they change earlier decisions.**

1. **The disk constraint is gone.** The proposal was written against "~30–40 GB free" and
   marked DeepSeek-V4-Flash (~91 GB) and Inkling-Small (~148 GB) as not installable here.
   At 175 GB free, **DeepSeek-V4-Flash now fits.** Inkling-Small still does not with any
   comfort — it would leave ~27 GB on a boot volume. The task list has been corrected.
2. **The memory constraint is real and tighter than the spec sheet suggests.** 24 GB
   physical is not 24 GB available: 16.39 GB is already in use with 4.26 GB compressed, so
   the actual headroom is **~7.6 GB plus reclaimable cache**. The engine's built-in rule
   picks **96 expert-cache slots (~6.8 GB wired)** on a ≥24 GiB host. That would consume
   essentially all of it. **Default to 32 slots (~2.2 GB).** This was already the
   recommendation on theoretical grounds; the machine's actual occupancy confirms it.

## What is done

Sixteen commits. The detail is in the PR body and the code; this is only the shape.

- **`mesh-code`** — a local coding agent driving commands through persistent `meshd`
  sessions. `install/payload/agent/*.ts` + `bin/mesh-code`. Verified against a real daemon
  and a real multiplexer on Linux: exact exit codes, 200000/200000 lines captured, `cd`
  persistence, timeout and recovery, malformed-argument correction, durable state.
- **`GET /brain`** — daemon capability reporting which local server is up, which model it
  holds, and whether it accepts images. Server down is 200 with `reachable:false`.
  Capabilities measured via `?probe=1`, not guessed.
- **`scripts/brain-eval/`** — one capability scorecard that runs against any
  OpenAI-compatible endpoint, so our engine and LM Studio are graded by identical probes.
  **Since 2026-09-02 it also compares two endpoints side by side** (`--a`/`--b`): ten
  use-case probes shaped like the owner's real day (CLI with mesh-code's seven tools, a
  page outline for the browser, `xcrun simctl` and a test digest for iOS, frontmost-app
  discipline for macOS), tokens/sec and time-to-first-token with reasoning split from the
  answer, a per-capability *better for* verdict, and a `.jsonl` dataset export. Verified
  against three stub personas — `check-brain-eval-compare.sh`, ~50 assertions — because
  no model has been graded yet.
- **The `--expert-cache-slots` patch** —
  `references/patches/0001-mference-server-expert-cache-slots.patch`. **Built and tested on
  this Mac 2026-09-01: release build clean, `swift test` 1102 tests / 179 suites, zero
  failures.** All warnings in that run are pre-existing upstream; none of the three patched
  files appears in any of them.
- **Two reference codebases vendored and studied** — see [references/README.md](../references/README.md).
- **A Metal vision-tower scope** — [docs/vision-tower-port-scope.md](vision-tower-port-scope.md).
  Most of the ViT already exists in the Mference kernels; the new work is LayerNorm,
  bias-add, preprocessing and plumbing.

## What is NOT done, stated plainly

- **No local model has ever run.** Not once. Every number about tokens/sec, memory or
  latency in any document here is upstream's arithmetic or a reference measurement — none
  of it is ours. `mesh-code` has only been driven by a scripted stand-in.
- **The patch is built but not exercised.** No server has been started with
  `--expert-cache-slots`. The ~2.2 GB and ~6.8 GB figures are unverified.
- **Nothing in the iOS/Android command surface has been executed** — the cloud box had no
  `adb`, `xcrun`, `xcodebuild` or Android SDK. `mobile.ts`'s digesters are pure text
  functions and are tested; the commands they parse for are not confirmed.
- **The Swift client work was deliberately not written.** `BrainStatus` in `Shared/Models.swift`
  and `MeshClient.brain()` are both serialized files, and writing them blind — with no way
  to build or run the apps — is exactly the failure AGENTS.md rule 1 describes.
- **The fork has one unpushed commit.** See "The fork" below.

## The decision the next session has to make

This is the important part, and it is why the focus is the harness.

[local-brain-and-harness/proposal.md](../openspec/changes/local-brain-and-harness/proposal.md)
Finding 2 says, in as many words: **adopt the harness, do not build it.** Write a
`ctx.subprocess` / `ctx.fs` provider that points deepseek-harness at `meshd`, the way
[`dsh-worlds`](https://github.com/frozo-ai/dsh-worlds) pointed it at Docker, and inherit
the agent loop, tool registry, permission system and model adapter for free.

**That spike was never run.** All four items under "Spike — time-boxed, throwaway" in
[local-brain-and-harness/tasks.md](../openspec/changes/local-brain-and-harness/tasks.md)
are still unchecked.

Instead, the previous session built `mesh-code`: its own loop (`loop.ts`), its own tool
registry (`tools.ts`), its own model adapter (`model.ts`), its own permission system
(`risk.ts`). That is the thing the proposal advised against building. It was not a
considered reversal of Finding 2 — the harness question simply never came up while the
model work was in front of it.

**So decide, explicitly, before writing more agent code.** The honest framing:

| Component | If you adopt deepseek-harness |
|---|---|
| `exec.ts` | **Keep.** Three designs deep and measured; the two obvious approaches are both broken (see its header comment). This is the `ctx.subprocess` implementation, whatever loop sits above it. |
| `meshd.ts` | **Keep.** Typed daemon client — this is `ctx.fs` plus the session routes. |
| `mobile.ts` | **Keep.** Digesting a 34 KB xcodebuild log to 307 chars matters more with a small model, not less. Harness-agnostic. |
| `risk.ts` | **Keep or adapt.** Mirrors `Shared/RiskClassifier.swift` so CLI, phone and watch agree on "destructive". If the harness brings its own permission system, this becomes its policy source, not dead code. |
| `brain.ts`, `brain-eval/` | **Keep.** Daemon route and scorecard, both independent of the loop. |
| `loop.ts`, `tools.ts`, `model.ts` | **This is what the harness would replace.** ~840 lines. |

So the cost of adopting the harness is bounded and knowable: three files. The spike is
still cheap, and the pieces that were expensive to get right are the ones that survive
either way. **Run the spike before extending `mesh-code` further.**

The caveat from the proposal still stands: deepseek-harness is a developer preview with
explicit breaking-change warnings. OpenHands' `BaseWorkspace` is the mature fallback.

## The fork, and where the Mac-side work actually lives (updated 2026-09-02)

`aryateja2106/Mference` — public fork of `NeelM0906/Mference`; `main` is pinned at
upstream `297c0080947d8be0ddc65f973217c0d14d1d68fd`.

**What reached GitHub:** branch `claude/expert-cache-slots` at `e27bbcb`, one commit,
**byte-identical to `references/patches/0001-mference-server-expert-cache-slots.patch`**
(verified by applying the patch to the pinned commit and diffing trees). That is the whole
of it.

**What did not — and this is most of the value:** a Cursor session running in
`~/deepseek-harness` reported porting **paged full-attention KV to Qwen 3.6**. Upstream's
`KVPageStore` / `Qwen38PagedKVRuntime` are Qwen 3.8-only, and the upstream *server* has no
paged-KV flags at all (`--kv-paged` and `--kv-pool-pages` exist only in
`MferenceCLI/Args.swift`). So that port is new engineering in two places: the Qwen 3.6
runner, and server-side plumbing. As reported by that session, not measured by anything in
this repo:

| Reported | Value |
|---|---|
| Server config | context 32768 · expert slots **16** · kv paged on · kv pool 48 pages |
| RSS after two chats | 1.14 GiB |
| RSS idle | ~0.97 GiB |
| Prompt cache | `cached_tokens: 19` on the second turn (single-prefix) |
| Spill | a 5,459-token prefill past the 3,072-token hot pool wrote `$TMPDIR/mference-kvpages-*/kvpages.spill` |
| Restart | `./scripts/run-qwen-server.sh` in `~/deepseek-harness/Mference` |

It also stood up **dsh web with a "LeSearch" plugin** on `http://127.0.0.1:3080` (ttyd on
`:7681`). None of this is on GitHub. It exists only on the Mac.

**There are now two clones of the fork on the Mac**, and they have diverged:

| Clone | Has | Status |
|---|---|---|
| `~/Projects/lecoder-watch/Mference` | the patch, as local commit `0b00b2d` | behind; inside this repo (gitignored as a seatbelt) — **delete it** |
| `~/deepseek-harness/Mference` | the patch **plus** the paged-KV port, `scratch/qwen36.gturbo`, `run-qwen-server.sh` | ahead; **this is the one to keep and push** |

Push it, so the next session anywhere can read it:

```sh
cd ~/deepseek-harness/Mference
git status --short | head            # see what the Cursor session left uncommitted
git add -A && git commit -m "feat: paged full-attention KV for Qwen 3.6, server-side paged-KV flags"
git push -u origin HEAD:claude/qwen36-paged-kv
```

Then vendor `scripts/run-qwen-server.sh` into this repo beside `scripts/start-brain.sh`
(or fold its flags into it — they only differ by the paged-KV flags, which
`start-brain.sh` must gate on `--help` output the way it already gates
`--expert-cache-slots`, because the upstream server rejects unknown flags).

## Ornith, identified

"Ornith" is a real, public model family — [ornith-ai](https://github.com/ornith-ai/Ornith-1),
MIT — not a private name. The one that fits this Mac and LM Studio is
**Ornith-1.5-35B-A3B** (MLX 4/6/8-bit or GGUF), and three facts about it decide how the
comparison against Qwen 3.6 has to be run:

1. **It is the same architecture class as Qwen 3.6-35B-A3B** — 35B MoE, ~3B active per
   token, built on Qwen 3.5. Its card claims it beats Qwen 3.6 on every agentic benchmark
   listed (Terminal-Bench 2.1: 67.8 vs 52.5; SWE-bench Verified: 79 vs 73.4). So the
   comparison is **engine vs engine as much as model vs model**: Mference streams
   experts from SSD at ~1.1 GiB resident; LM Studio holds the whole MLX model in RAM
   (roughly 18–20 GB at 4-bit on a 24 GB machine). Memory footprint is a first-class
   axis of the verdict, not a footnote.
2. **It is a reasoning model.** Every assistant turn opens with a `<think>…</think>`
   block. Depending on LM Studio's version and the model, that arrives as
   `delta.reasoning_content`, `delta.reasoning`, or inline `<think>` tags inside
   `delta.content`. Time-to-first-token and tokens/sec are meaningless unless reasoning
   is split from the answer — `scripts/brain-eval/sse.ts` does that and is tested
   against all three shapes.
3. **Its authors recommend temperature 0.6 (coding) or 1.0 (benchmarks), never 0.**
   Reasoning models at temperature 0 can loop inside the think block. A fair comparison
   sets temperature explicitly on both endpoints (Mference defaults to 0.2, LM Studio to
   the model's own default) and records it in the result.

It speaks the Qwen3 XML tool dialect (`<tool_call>` / `<function=…>`), the same one
`mesh-code` already parses. When LM Studio fails to parse it, the XML lands in `content`;
the eval classifies that separately from "answered in prose", because it is a server
configuration finding, not a model capability finding.

## Two harnesses are now running in parallel — decide on purpose

The Cursor session took the route [local-brain-and-harness](../openspec/changes/local-brain-and-harness/proposal.md)
Finding 2 recommends: deepseek-harness (`dsh web`) with a plugin. This repo took the
other route: `mesh-code`, our own loop. **The harness decision is being made by
accident, in two directories, by two agents that cannot see each other.** Make it on
purpose: read the previous section of this document, run the spike in the deepseek-harness
task list, and record the outcome as a spec delta.

## Traps this work has already hit

Each of these cost real time. They are recorded where they belong (code comments, PR body,
`references/README.md`); listed here only so they are not re-discovered.

1. **`cmd | tee log` loses `cd` and reports success for every failure.** A pipeline runs in
   a subshell; `$?` after a pipe is tee's. Process substitution fixes both and buries the
   completion marker instead. See `exec.ts`'s header.
2. **A user message mid-run re-prefills the whole history** on the Qwen dialect. Guidance
   goes into a tool result the loop is already sending.
3. **Qwen's parser types arguments opportunistically** — `command="true"` arrives as boolean
   `true`. Coerce, never type-reject.
4. **`sed -i` is not portable** — BSD sed on the macOS runner broke two checks. Copy the
   module beside the driver and import relatively (`check-codex-state.sh`'s pattern).
5. **`install.sh` enumerates payload directories**, so `bin/mesh-code` shipped without its
   `agent/` implementation — correct in the repo, dead on every machine. Caught by CI.
6. **Retry at temperature 0 is a no-op.** Retry at 0.4.
7. **A 24 GB host is not 24 GB of headroom.** See the machine section.

## Suggested skills for the next session

- **`/workflow-authoring`** — was used for the design phase of this work (12 agents: 6
  design, 6 adversarial critique; the critiques caught four real bugs in shipped code).
  Worth reaching for again on the harness spike, where several approaches want comparing
  before one is committed to. Not worth it for the runbook, which is a linear sequence.
- **`openspec`** — this repo's specs live in `openspec/changes/<name>/`. The harness
  decision should land as a spec delta under `local-brain-and-harness`, not as a code
  commit with a rationale in the message.
- No custom skill exists for this repo's check discipline; `scripts/check-all.sh` is the
  gate and it is not optional before a commit.

## First three things to do

1. **`git log -1 --date=short --format='%h %cd %s'`** — AGENTS.md rule 2. This repo has
   many worktrees and a session was once spent editing a six-week-old one.
2. **Run the runbook** ([docs/local-brain-runbook.md](local-brain-runbook.md)) to the point
   where a local model answers a real prompt. Everything downstream is blocked on that,
   and nothing about it is verified today.
3. **Then run the harness spike**, before writing any more agent-loop code.
