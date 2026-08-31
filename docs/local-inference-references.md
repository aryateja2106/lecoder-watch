# Local inference references — what the two vendored codebases teach us

2026-08-31. Companion to [references/](../references/README.md) and to
[openspec/changes/local-brain-and-harness/](../openspec/changes/local-brain-and-harness/).
That change answered "which harness, which model"; this doc answers "how does a model
bigger than the Mac's RAM actually run on it", from two codebases that each solved half
of the problem.

The owner's constraint, verbatim: *"I want to start using models like qwen3 27b, but I
don't have enough memory and storage to run them."* Both references attack exactly that.

---

## kimi-k3-in-c — RAM is a speed dial, not a capacity floor

`references/kimi-k3-in-c/`, pinned `117e9d2`. A single-binary, pure-C99 CPU inference
engine for Moonshot's Kimi K3 (2.78T-param MoE). Its thesis is the sentence this whole
doc exists for: the 1.56 TB checkpoint runs in **8 GB of RAM (8.24 GB measured peak
RSS) with byte-identical output** to a 224 GB run — only tokens/sec changes (26.5
s/tok at 8 GB → 5.59 s/tok trunk-resident at 128 GB+). Apache-2.0, ~8.9k lines of C,
no BLAS, no GPU. It is CLI-only and greedy-only — an engineering artifact plus a 148 KB
tutorial README, but verified end-to-end against the real checkpoint (all 93 layers
conformance-checked against PyTorch; logit parity max |diff| 7.87e-6).

### The four reductions (their ledger)

5,560 GB naive bf16 → 1,560 GB (experts ship in MXFP4) → 113.49 GB resident (MoE
routing: 1.447 TB of experts never load) → **8.24 GB measured** (dense trunk streamed
from disk). 189× below the shipped checkpoint, lossless.

### Techniques that transfer to us (ranked by fit)

1. **Pinned-prefix + ring streaming of dense weights** (`src/io/k3_trunk.{c,h}`).
   Repack layers contiguously once (`tools/pack_trunk.py`), pin layers 0..K
   permanently, stream the rest through a 1–2-slot ring with a dedicated reader
   thread prefetching layer L+1 while L computes (1.70× measured). The anti-LRU
   lesson is worth quoting: a cyclic layer scan is LRU's pathological case — 90 LRU
   slots over a 93-layer cycle hits 0%; **pinning a prefix hits exactly K/N,
   deterministically**. This is the direct answer to "model bigger than RAM": it
   degrades in speed, never in capability.
2. **Session state snapshot/resume** (`k3_state_save/load`, `src/cli/k3_run.c:197-295`).
   Persists sequence + KV caches + recurrent state with a 12-dimension architecture
   fingerprint in the header; refuses mismatches rather than guessing. Measured:
   turn two of a conversation resumed in 182.6 s vs 706.8 s from scratch (3.9×),
   restore itself 0.3 s. For a daemon hosting long-running multi-turn agent
   sessions, this is the "long-running" piece: an agent session's model state
   survives restarts and evictions.
3. **Bounded-memory embedding/lm_head streaming** (`K3ModelStream`,
   `src/model/k3_bind.h:90-117`). Embedding tables and output heads are the silent
   multi-GB residents in every engine; streaming exact rows and projecting in 4 MB
   chunks keeps a 4.70 GB embed+head permanently off-resident. Their ultra mode
   plans ~3 GB total and runs on 8 GB ARM boards (Jetson Orin results in
   `docs/results/`).
4. **Up-front memory plan + refusal to start.** The engine sums every planned
   allocation against `MemAvailable` and refuses with both numbers printed rather
   than OOM-ing an hour into a session. A daemon must never discover mid-task that
   the model didn't fit. (Darwin-aware RSS reporting already in
   `src/cli/k3_run.c:452-477`.)
5. **Page-cache-bypass I/O for stream-once weights** (`src/io/k3_portable_io.h:61-90`).
   O_DIRECT on Linux, `F_NOCACHE` on macOS: weights read once and evicted must not
   flow through the unified page cache, where they evict the working set — they
   measured the buffered path at ~1/5 device speed under memory pressure. Also a
   real Darwin bug we'd have hit: `pread` EINVALs at ≥2³¹ bytes, hence their 1 GiB
   chunk cap.
6. **Trace-driven cache sizing** (`k3_cache_dump_trace` + `tools/sim_cache.py`).
   Record accesses once, replay any cache size/policy offline (Belady/LRU) —
   answers "how much RAM does *our* workload need" without owning the big machine.
7. **For a local MoE** (a Qwen3-30B-A3B-class model is the realistic big-model play
   on a MacBook): the expert-streaming stack — MXFP4 matvec that never dequantizes
   (`src/core/k3_ops.c` ~1290, packed nibbles read via LUT; the expert cache stores
   MXFP4 too, 7.5× more experts per GB), one coalesced 17.5 MB pread per expert,
   3-phase parallel batch prefetch at queue depth 16 (`src/cache/k3_cache.c:131`).
   Plus the measured warning: balanced routers defeat LRU — their expert cache did
   nothing below ~36 GB of arena, and at fixed 128 GB budget, giving RAM to the
   dense trunk beat giving it to the expert cache 16.80 vs 28.38 s/token. **Budget
   the dense trunk first; allocation beats capacity.**
8. **Measurement hygiene**: cgroup-enforced memory ladders with swap off, a noise
   floor measured before claiming wins, byte-identical output as the correctness
   gate for every optimization. Cheap to copy into our benchmarking.

### What we should NOT take

- The CPU kernels. Scalar/AVX2/NEON with FMA deliberately disabled for
  bit-reproducibility is a testing contract, not performance engineering; MLX/Metal
  is orders faster on Apple Silicon. Use MLX for the math, this repo for the
  byte-placement discipline.
- The n-gram speculative decoder (only wins on repetitive text) and the int8 hybrid
  draft (their own note `docs/notes/int8-draft-container.md` measures it as a
  100 GB+-machine technique — drafts still pay full expert I/O).
- Huffman trunk compression — shelved by its own measurement (decode starves the
  laptops it targets).
- Its "never quantize the trunk" stance is specific to K3's training regime, not a
  general law. For dense 27B-class models, a well-made 4–5-bit quant is the first
  and biggest lever, before any streaming.

---

## mference — "big MoE models in 'small' GB of RAM", on Apple Silicon, with a server

`references/mference/`, pinned `297c008`. A from-scratch **Swift + Metal** inference
engine for Apple Silicon (macOS 15+, arm64 only). Not built on MLX — its only
dependencies are swift-transformers (tokenizers) and SwiftNIO; it consumes
MLX-community quantized checkpoints byte-for-byte with its own Metal INT4/INT8/ternary
kernels. It is a library + CLI + streaming installer + native Mac chat app + an
**OpenAI-compatible loopback HTTP server** (`Sources/MferenceServer/`). Licenses all
permissive (MIT + Apache-2.0 + MIT LICENSE-MLX; ship the NOTICE bundle if we ever
redistribute binaries). Self-described research system, but unusually disciplined:
206 test files vs 211 source files, byte-identity gates on every optimization, a
frozen benchmark protocol, and honest published failures.

### The models it actually runs (pinned checkpoints, no generic GGUF loading)

| Family | Shape | RAM | Disk | Speed (24 GB M5-class) |
|---|---|---|---|---|
| Gemma 4 26B-A4B | MoE top-8 | ~2 GB | ~14.3 GB | 31–35 tok/s (5–6 on an 8 GB M2 Air) |
| **Qwen 3.6 35B-A3B** | MoE hybrid | **~1.45 GB** | ~19.6 GB | 23–29 tok/s; 10–14 under a verified 8 GB working set |
| **Qwen 3.8 27B dense** | 48 GDN + 16 attn layers | ~15 GB | ~15.1 GB | **15.0 tok/s with MTP** (2.35× mlx-vlm on the same checkpoint) |
| DeepSeek-V4-Flash 284B-A13B | MoE, 2-bit experts | ~6.8 GB | ~91 GB | 5–6 tok/s |
| Inkling-Small 276B-A12B | MoE top-6 | ~9 GB | ~148 GB | 5–7 tok/s (M3 Ultra) |
| Maple 20B-A1B | ternary | ~645 MiB | ~6.6 GB | — |

**The reframe that answers the owner's complaint directly:** the wished-for "Qwen 3.8
27B" dense model needs ~15 GB resident (a 24 GB Mac). But **Qwen 3.6 35B-A3B — the
same quality class — runs in ~1.45 GB of RAM and ~20 GB of disk**, 10–14 tok/s even
under an mlock-ballasted 8 GB working set. On a memory-constrained Mac the binding
constraint becomes ~20 GB of disk, not RAM.

### How it fits big models in small RAM

- **SSD expert streaming with a per-layer LFU slot cache** (`PreadExpertStreamer.swift`,
  `ModelExpertIO.swift`): commons mmapped + zero-copy `MTLBuffer`s; each layer's
  experts in one fixed-stride page-aligned file; 16–128 wired 2 MiB-aligned slots.
  Same empirical result as kimi-k3-in-c from the other direction: **explicit `pread`
  beats mmap demand paging cold** (2.79 ms vs 9.88 ms per expert), and fully-resident
  mode *lost* to slot rungs under page-cache pressure.
- **Compute/I/O overlap** on decode: attention+router → pread misses while the
  shared-expert branch runs on GPU → routed MoE; a GPU-resident expert-to-slot map
  skips CPU planning entirely on all-hit layers. All byte-identical to the disabled
  paths.
- **Paged KV with an SSD spill tier + Quest-style sparse decode**
  (`KVPageStore.swift`, `docs/QWEN38_LONG_CONTEXT.md`): 64-token pages, RAM pool
  auto-sized to physical−22 GiB, LRU spill to disk, per-page K min/max metadata so
  each token attends sinks + recent window + top-k pages, selected lag-one so page
  fetches hide in the inter-token gap. 262k context on a 24 GB M5 at 7.9 tok/s plain
  / 14.0 with MTP; a needle prompt through SSD spill retrieved its passkey exactly.
  This is the "long agent transcript" enabler.
- **Speculative decoding, byte-identical by construction.** Default **MTP** uses the
  checkpoint's native multi-token-prediction layer (re-attached at install by
  `MferenceRepack --attach-mtp`, +239 MB): draft 3, verify all in one target pass
  with kernels that replicate decode arithmetic bitwise → 7.9 → 15.0 tok/s. The
  newer **DFlash2 block-diffusion drafter** (the PR #22 merge) drafts better (3.53
  vs 2.27 tokens/round, INT4-quantized at load to ~1.05 GB wired) but currently only
  wins +3.7% on chat and loses ~11% on code — verify cost is per-row and k=6 pays it
  six times; their own doc names batching the verify rows as the unlock. Adopt MTP;
  watch DFlash2.
- **Streaming installer** (`RemoteStreamingRepacker.swift`): installs multi-GB
  checkpoints from HuggingFace via bounded byte-range reads — max scratch during a
  validated install was 512 KiB, resumable, drops vision towers (~3.5 GB saved on
  Qwen 3.8). Never needs 2× disk. This addresses the *storage* half of the
  owner's complaint.

### The serving surface (what meshd would talk to)

`MferenceServer`: `GET /health`, `GET /v1/models`, `POST /v1/chat/completions` with
SSE streaming — loopback only (or one exact Tailscale IPv4), **no auth, no TLS, one
model, strictly one generation at a time** (queue up to 4). It keeps a **single-prefix
prompt cache** across requests: if a request's history exactly extends the retained
conversation, the verified KV prefix is reused and reported in
`usage.prompt_tokens_details.cached_tokens`. That is exactly the shape of an agent
loop — each tool-call iteration re-sends a growing prefix — so long-running tasks get
cheap turns for free, *provided the daemon serializes agent turns and sends complete
history*. Native tool-call parsing per family surfaces OpenAI `tool_calls`
(`tool_choice` auto/none only); no JSON-schema/structured output, no logprobs.
Startup prints a ready line for supervisors; clean SIGINT/SIGTERM.

### Risks

Model lock-in (six pinned checkpoints, adding a family is a kernel-level port);
single-tenant serialized server that must sit behind meshd's auth; macOS 15+/arm64
only; single-maintainer research pace; on RAM-rich hosts mlx-lm is ~2.3× faster for
the MoE families — mference's value is the footprint (the exception: dense Qwen 3.8
+ MTP, where it beats mlx-vlm 2.35×).

---

## Where this plugs into LeSearch Mesh

Today **no model inference runs anywhere in the product** — it is a viewing/steering
surface for third-party agents. The only model *names* on the wire are hosted ones in
`/usage`'s `topModels`. LM Studio appears in-repo only as a service we must never
restart. The `local-brain-and-harness` proposal (unimplemented, all boxes unchecked)
already settled the strategy: keep meshd's session layer, adopt a harness, stage the
local model in. These references fill in the *how*. Three seams, each independently
shippable:

**Seam A — a `brain.ts` meshd module fronting a local model server.** meshd already
fronts two loopback services (OpenUsage at `:6736`, the cmux bridge); a local
OpenAI-compatible server (MferenceServer at `:8080/v1`, or LM Studio's `:1234/v1`)
would be the third of that species. A self-contained module (the `wol.ts`/`files.ts`
pattern: one import + one claim line in `server.ts`, one new `CAPABILITIES` string)
that health-checks the server and exposes which model is loaded — meshd contributing
exactly what MferenceServer lacks: bearer auth, the Host/browser guard, fleet
reachability. New wire types in `Shared/Models.swift` + `MeshClient.swift`
(serialized files — one agent at a time) and a model badge next to the existing
`agentType` chips satisfy the spec's "client shows which model is answering".
Operational hazard: rule 6 — useless to the fleet until a `mesh-install` release
ships it, and clients must gate on the capability string, never version.

**Seam B — the harness in a mux session (the long-running-tasks piece).** Run the
harness as a process on the Mac, started via `POST /agents/new`, with its
`ctx.subprocess`/`ctx.fs` provider speaking meshd's existing `/agents/:n/send|output`
routes — the existing spike task explicitly asks whether zero new routes suffice.
The phone/watch then already see, steer, and get pushed about the task through
today's plumbing; pointing the harness's OpenAI adapter at Seam A's local endpoint is
one config value. Long-horizon economics come from MferenceServer's prompt cache
(send full history each turn, get `cached_tokens` back) — which also means meshd
must treat the model server as single-tenant and serialize agent turns to avoid
thrashing the one retained prefix.

**Seam C — MeshDesktop supervises the model server.** The non-technical-user answer
to "download and run Qwen": a menu-bar flow that installs (mference's resumable
streaming installer), launches (wait for the ready line), and shows the loaded model
— feeding Seam A's status. Separately, UI-TARS-style GUI grounding composes entirely
from existing routes (`GET /screen.jpg` in, `POST /input` out): a small local vision
model could be the first inference the product runs with **no new daemon surface at
all**.

### What the two references agree on (treat as settled)

1. **Stream from SSD with explicit reads, not mmap, not page cache.** Both measured
   it independently (pread beat mmap ~3.5× cold in mference; the buffered path ran
   at ~1/5 device speed in kimi-k3-in-c). RAM budgets go to pinned/hot weights.
2. **Byte-identical output is the correctness gate for every memory/speed trick.**
   Both repos gate speculation, streaming, and caching on bit-equality with the
   naive path. Any local-inference work here inherits that discipline.
3. **Plan memory up front and refuse to start** rather than OOM mid-task.
4. **The footprint answer to "model too big" is architecture choice first
   (MoE-with-few-active-params), quantization second, streaming third.** Speed
   degrades; capability doesn't.

### Recommendation

Adopt, in order: (1) Seam A `brain.ts` + model badge — small, visible, satisfies the
spec's honesty requirement; (2) MferenceServer supervised on the Mac with **Qwen 3.6
35B-A3B** as the first local model (~1.45 GB RAM/~20 GB disk beats waiting for a
32 GB machine), Qwen 3.8 27B + MTP when a 24 GB Mac is available; (3) Seam B harness
spike per the existing tasks, with the local endpoint as one of its configured
brains. Defer: embedding inference in-process anywhere (mference's own Mac app
isolates the model in a helper process — copy that judgment), the Jetson for
anything interactive (949 s/token measured on kimi-k3), and DFlash2 until its
verify-batching lands.
