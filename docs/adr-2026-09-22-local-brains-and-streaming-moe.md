# ADR 2026-09-22 — local brains on every machine, and whether to build our own streaming-MoE engine

*Status: proposed (owner: Arya). Written overnight 2026-09-21/22 from measurements, not opinions;
every number below was produced on the fleet that night and is reproducible with the named check.*

## Question

The product promise is "control any machine you own from your wrist, in plain language, and hand
work to agents". Two local-model questions sit under it:

1. **Intent on the device.** When the watch hears *"restart the jetson"*, what turns it into
   `POST /system {action: restart}` on the right daemon without a cloud round trip?
2. **A big model on small hardware.** Arya likes what Edge0 does (SSD expert offload + Recover-LoRA +
   prerouter; a 35B-A3B MoE in ~3 GB of RAM on Apple Silicon) and asked whether we should build our
   own, in Swift or Rust, so it runs on the Mac, the Jetson, the Pi and eventually the phone.

## What we measured (2026-09-22)

| Where | Engine · model | Task | Result |
|---|---|---|---|
| Mac (M-series, 24 GB) | **Needle 2** CLI (Cactus-Compute/needle2, 45M params, 14 MB binary) over `intent/mesh-tools.json` (16 tools, one per daemon route) | 28 wrist phrases → tool call (`scripts/check-intent.sh`) | **20/28 right tool** with first-draft descriptions → **26/28 after one pass of description tuning** (22/28 with every expected argument). Mean confidence 0.28, **~700 ms/phrase, 34 MB peak RAM**. Misses left: argument extraction (session names, copy direction). |
| Pi 5 (8 GB, CPU) | Needle 2 linux-arm64 CLI | *"restart the jetson"* | `power({machine: jetson, action: restart})`, confidence 0.52, **224 tok/s decode, 25 MB RAM** |
| Pi 5 | ollama · qwen3:1.7b | OpenAI tool call (`check-brain.sh` local half) | correct `get_time({machine: jetson})` in **23–40 s** (~3.5 tok/s) |
| Jetson Orin Nano 8 GB (CUDA 12.6) | ollama 0.34 · qwen3:4b | same | correct call in **12 s** (~11 tok/s). Default context OOMs the shared 8 GB; needs `OLLAMA_CONTEXT_LENGTH=2048` + q8_0 KV cache. Qwen3 spends the whole budget thinking unless the prompt carries `/no_think`. |
| Mac | **edge0-8b** (Edge0, MLX, Ling-3.0 based, 4-bit, prerouter K=8, 4.2 GB on disk) | chat | first token ~10 s cold, **~11 tok/s warm**, RSS 3.8–4.1 GB with experts mmapped |
| Mac | edge0-8b + our patch `references/patches/0002-edge0-openai-tool-calls.patch` | OpenAI tool call | **correct call in 3.8 s, 14 completion tokens.** Upstream Edge0 drops the `tools` array and never parses `<tool_call>`; the patch threads tools into the chat template and parses the calls. Worth an upstream PR. |
| — | edge0-35b | — | **not run**: 23 GB checkpoint, 13 GB free on this Mac after the night's builds. |

Cost of the on-device path per phrase: Needle **0.7 s / 34 MB / no network**. Cost of the "large local brain" path per phrase: 4–40 s and 1–4 GB, per machine.

## Decision (proposed)

1. **Needle 2 is the intent router, on every surface.** It runs on the watch (watchos-arm64 lib), the phone, the Mac and both Linux boxes from the same 14 MB artefact and the same `intent/mesh-tools.json`. Slice 2 = fine-tune on our phrases (`pip install "cactus-needle[train,metal]"`, `needle finetune`) to fix argument extraction; the acceptance suite and floor already exist (`check-intent.sh`, floor 24/28). Confidence gate + `RiskClassifier` before any action, exactly as PRODUCT.md §9 says.
2. **The large local brain is whatever OpenAI-compatible server the machine already runs; meshd only *fronts* it.** `GET /brain` (ported from PR #119 tonight) finds edge0 :8001, ollama :11434, mference :8080 or LM Studio :1234. On the Mac that is **Edge0** (fastest per watt, MLX, SSD-streamed experts; tool calling via our patch). On the Jetson and the Pi it is **ollama/llama.cpp** — which already does the two things people want from "SSD streaming": mmapped weights loaded on demand and, for MoE models, `--n-cpu-moe` / `-ot` expert offload to host memory. Nothing to build for Linux to get a usable local brain today.
3. **Do not build our own streaming-MoE engine before launch.** Edge0's own README lists the CUDA backend as roadmap; matching its recipe (expert pool paging, a trained prerouter per checkpoint, Recover-LoRA distilled from the FP teacher) is a research project with a training pipeline, not a port. Our differentiation is the *orchestration* (watch → any machine → any agent → files back), not the kernel. Revisit after 1 October with a measured target (e.g. "35B-A3B at ≥ 8 tok/s on the Jetson in < 6 GB") and Edge0's CUDA backend status; if we do build, Rust + `candle`/`mistral.rs` with an MLX-Swift frontend is the candidate, and the first deliverable is the **facade** Edge0 already defines (`backends/base.py`) so checkpoints/adapters stay compatible.
4. **Contribute upstream instead:** the tool-calling patch to Edge0; the description-tuned `mesh-tools.json` and phrase set as a Needle example.

## Consequences

- New surface in the daemon: capability `brain`, module `brain.ts`, env `MESHD_BRAIN_URL`. No daemon starts or stops a model server.
- Fleet state tonight: ollama enabled on the Pi (qwen3:1.7b) and installed on the Jetson (qwen3:4b, systemd drop-in for context/KV); edge0-8b under `references/external/models` on the Mac (gitignored), served manually on :8001 — **not a launch feature**, a measured option.
- Checks: `check-intent.sh` (Needle suite, floor), `check-brain.sh` (structural + fleet + local tool-call halves).
- Open: the daemon-side router (Needle inside meshd as the front of `/brain`) and the watch integration are app code and wait for the fine-tune numbers.
