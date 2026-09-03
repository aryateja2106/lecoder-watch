# Scoping a small Metal vision tower for the Mference fork

2026-09-01. The ask: *"we need to figure out how to bring image processing into our
inference as that's important … scope a small metal vision tower port because looking at
the screenshot being able to read them and take action is one of the critical tasks, so
do not discount that too much."*

Delegating images to LM Studio stays the shipping answer meanwhile — `GET /brain?need=images`
already routes to whichever reachable endpoint accepts an `image_url` part, and
`scripts/brain-eval/` grades both engines on it. This document scopes the port that would
eventually remove that dependency. Line references are to
[`references/mference/`](../references/README.md) at the pinned commit.

## The finding: most of the ViT is already in the repo

A vision tower is a stack of {LayerNorm → attention → MLP} over image patches. Almost all
of that arithmetic exists in Mference already, which is what makes a *small* port
plausible.

| Piece | Status | Where |
|---|---|---|
| INT4-affine GEMM | **reuse as-is** | `prefill_dequant_int4_qmm_f16_block`, `Metal/Prefill/prefill.metal:822` — general `[T,K]x[N,K]→[T,N]`, no shape constraint beyond `K % 64 == 0` |
| Bidirectional attention | **reuse by parameter** | `attention_prefill_causal_tiled`, `prefill.metal:1011`. `startPosition` feeds only the window floor and causal ceiling (`:1033-1038`); set `slidingWindow = 0` and `startPosition >= kvValidCount` and it is bidirectional with **no kernel edit** |
| GELU-tanh | **reuse as-is** | `Metal/Primitives/utility.metal:7` |
| Patch embedding | **no kernel needed** | ViT patch embed has stride == kernel size, so patches are non-overlapping: a pure gather plus one matmul. Do the unfold on the CPU in preprocessing and call the existing GEMM |
| LayerNorm | **new, small** | Zero hits for `layernorm` across `Sources/Mference/Metal` — only RMS variants, which do not mean-centre |
| Broadcast bias-add | **new, small** | — |
| Image decode / resize / patchify | **new, Swift side** | No CoreGraphics or vImage anywhere in `Sources/` today |
| Repack keeping the tower | **one-line flip** | `RepackPlanner.swift:344-352` `isExcludedTensorName` |

The `.gturbo` resident format already stores rank-4 shapes, INT4 + BF16 scale/bias
companions, and plain BF16 tensors, and the layout validator only checks
`packed_experts` — so the tower needs no new container work.

## Decisions worth keeping

- **Target Gemma 4's tower first**, not Qwen's. The repo's own fixtures show Gemma's as a
  flat `encoder.layers.N.{input_layernorm, self_attn.q_proj.linear}` stack terminating in
  a single projection tensor (`SyntheticSnapshot.swift:140-146`). Confirm against real
  safetensors headers before committing (Stage 0).
- **Rule out Inkling-Small** despite its tower being the smallest and best-formatted
  (18 tensors, already affine 4-bit group-64) — its 148 GB install does not fit this
  machine, so it cannot be the first target.
- **Splice image embeddings by blitting rows into `scratch.hidden`** between the embedding
  lookup and the layer loop (`RealForwardRunner.swift:1889-1902`), rather than teaching
  the embedding kernel about images.
- **The tower is extra mmap'd resident bytes, not new wired memory.** `model_weights.bin`
  is mapped `PROT_READ/MAP_PRIVATE` and wrapped with `makeBuffer(bytesNoCopy:)`
  (`ResidentBuffer.swift:5,128-146`), so tower pages fault in when an image is processed
  and stay evictable. This matters: the whole point is not to spend the memory budget.

## Staged plan, each stage independently verifiable

0. **Measure before porting.** Confirm delegation genuinely works and dump the real
   tower's tensor names, dtypes and shapes from the safetensors headers. *Runnable on
   Linux today* — the only stage that is.
1. **Repack keeps the tower, behind a flag.** Smallest change producing a `.gturbo` with
   vision weights in it. Verified by extending the synthetic snapshot with a miniature
   tower.
2. **Prove the runtime reads a vision tensor back.** One accessor, one checksum matching
   an independently computed value.
3. **CPU reference tower in Swift.** Ground truth before any Metal: cosine similarity
   ≥ 0.999 against mlx-vlm's vision output.
4. **GPU tower** from the existing kernels plus the three small new ones, layered the way
   this repo already tests kernels (LayerNorm parity test first).
5. **Preprocessing and the splice** — the first point where a screenshot changes a
   generation. Must be proven by a *run*, not a build.
6. **Server plumbing**: accept `image_url`, place the placeholder tokens, keep the prompt
   cache honest. Gradable from Linux against the Mac's endpoint with `brain-eval`.

Stages 1–5 are Mac-only.

## Risks, stated plainly

- **Seeing is not the same as being useful.** Qwen 3.6 activates ~3B parameters. A tower
  ported to 0.999 cosine parity can still yield a model that reads a screenshot and draws
  the wrong conclusion. Stage 0's delegation measurement is what tells us whether a local
  VLM of this size is worth the port at all.
- **`padTo4` truncates with `s.prefix(4)`** (`RepackPlanner.swift:811-817`) and will
  silently write a wrong logical shape for a rank-5 Conv3d patch-embed tensor — exactly
  the shape a Qwen-lineage ViT uses. Silent, so it needs an explicit guard.
- **If the tower is stored BF16 rather than INT4-affine, the reuse story degrades
  sharply.** The only BF16 matmul in the tree caps T at 8 (`dflash2.metal:17-42`,
  `float acc[8]`), which will not carry several thousand patches.
- **The repo contradicts itself on the Qwen tower's size** (`SupportedModelSource.swift:89-92`
  vs `docs/QWEN38_PERFORMANCE.md:16`). Resolve in Stage 0 rather than trusting either.
- **The prompt cache is single-prefix.** Images make prefixes that look textually
  identical but mean different things; getting the cache identity wrong yields confident
  answers about the *previous* screenshot.

## Recommendation

Do Stage 0 now — it is free and runs on any machine. Do not couple the agent's
screenshot ability to this port: `brain.ts` already routes image work to LM Studio, and
that path should stay the answer until Stage 3 proves parity on real weights.
