# Tasks

Every task ends in something runnable. Stage 0 is done and its proof is in the repo;
Stages 1–4 need the Mac, because Mference is Apple Silicon + macOS 15+ + Metal only and
cannot run in CI or a cloud agent container.

## Stage 0 — the scorecard (done)

- [x] **Build a capability scorecard that works against any OpenAI-compatible endpoint**,
      so our inference and LM Studio are graded by identical probes: function calling,
      terminal actions through meshd-shaped tools, browser sequencing, image acceptance,
      prefix reuse, stop discipline. → `scripts/brain-eval/`
      *Verified by running: against `stub-server.ts`, 9 pass · 0 fail · 1 unsupported,
      the unsupported one being images, correctly classified from the endpoint's 400.
      Negative control against a dead port reports 3 fails, so the harness can fail.*

## Stage 1 — the fork, and the patch that pays for it

- [ ] **Create the fork** (one manual step — this session's GitHub scope covers only
      `aryateja2106/lecoder-watch`): `gh repo fork NeelM0906/Mference --clone`. Record
      the upstream commit it forks from; upstream is a single-maintainer research repo,
      so pin and merge deliberately rather than tracking `main`.
      *Verify by running: `git -C <fork> log -1` and `git remote -v` pasted here.*
- [x] **Write the `--expert-cache-slots` patch for `MferenceServer`** —
      `references/patches/0001-mference-server-expert-cache-slots.patch` (3 files, 53
      insertions), plus `scripts/start-brain.sh` to pass it. Rejects values outside
      `allowedExpertCacheSlots`, and rejects `8` specifically: it is an allowed CLI rung
      but below chunked prefill's floor of `(maxPendingDepth + 1) * tileExperts`, so it
      would throw mid-generation instead of at startup.
      *Verified on the Mac, 2026-09-01: `swift build -c release --product MferenceServer`
      succeeded, and `swift test` passed 1102 tests across 179 suites with zero failures.
      Every compiler warning in that run is pre-existing upstream code — the patch touches
      only ServerArguments.swift, ServerInference.swift and main.swift, none of which
      appear in any warning.*
- [ ] **Build and measure it on the Mac.** Apply the patch in the fork, build, then run
      the server twice on the same model — once at `--slots 32`, once at `--slots auto`
      (96 on this 24 GiB host).
      *Verify by running: record peak RSS AND tokens/sec for each, because slots trade
      memory for speed and a footprint win that thirds throughput is not a win.
      `scripts/brain-eval/eval.ts` already times every probe — run it against both.*
- [ ] **Expose every upstream family in our install path** — `gemma4`, `qwen36`,
      `qwen38`, `maple`, `deepseekV4Flash`, `inklingSmall` — each carrying its disk and
      RAM cost, and each marked installable or not against this machine's free space.
      Default the memory profile to 32 slots (~2.2 GB), not 16: 16 is the exact chunked-
      prefill floor with zero headroom, and the slowest rung.
      A family that cannot fit is shown and disabled, never hidden.
      *Verify by running: the install list on this host — **175.21 GB free, measured
      2026-09-01** — shows Qwen 3.6, Gemma 4, Maple and now DeepSeek-V4-Flash (~91 GB)
      installable, and Inkling-Small (~148 GB) refused with both numbers because it would
      leave ~27 GB on the boot volume. The earlier "~30 GB free" assumption is superseded;
      disk is no longer the binding constraint on this machine — memory is.*

## Stage 2 — Qwen 3.6 serving, measured honestly

- [ ] **Install Qwen 3.6 35B-A3B** (~19.6 GB, resumable, never needs 2× disk):
      `swift run -c release MferenceRepack --model qwen36 --output ~/models/qwen36.gturbo`.
      Do not disturb the running LM Studio (AGENTS.md rule 5).
      *Verify by running: `df -h` before and after, plus the `verified-install.json`
      summary, pasted here.*
- [ ] **Measure it at both ends of the dial**: tokens/sec, peak RSS, and time to first
      token at `--expert-cache-slots 16` and at whatever auto selects on this Mac.
      *Verify by running: six numbers recorded here, with the host's RAM stated, since
      the slot profile is chosen from it.*
- [ ] **Grade it**: `bun run scripts/brain-eval/eval.ts --endpoint http://127.0.0.1:8080/v1
      --json docs/results/qwen36-<date>.json`.
      *Verify by running: commit the JSON. Expect `reads images: UNSUPPORTED` — that is
      the engine being text-only, not a failure of the run.*
- [ ] **Grade LM Studio the same way** on `:1234/v1`, with a vision model loaded, and
      confirm the image probe flips to PASS.
      *Verify by running: commit that JSON too, and put the two scorecards side by side.*

## Stage 3 — the daemon and the clients

- [x] **Write `install/payload/meshd/brain.ts`** following the `wol.ts`/`files.ts` claim
      pattern: probe both endpoints (ours and LM Studio, `MESHD_BRAIN_URL` overriding),
      report `{reachable, endpoint, model, source, capabilities}` where capabilities
      include whether the endpoint accepts images. Server down is HTTP 200 with
      `reachable:false`, never a 500. Add `"brain"` to `CAPABILITIES`. The `server.ts`
      edit is two lines plus the capability string.
      *Verified by running, on a spare-port daemon (`MESHD_PORT=8898`) against a stub
      model server, `bun x tsc --noEmit` clean:*
      - *no server running → HTTP 200, both candidates `reachable:false`, `brain:null`
        — a missing brain is a state, not a fault*
      - *server up → `brain.model = "stub-qwen36"`, `images:"unknown"` on the fast path
        (no generation spent)*
      - *`?probe=1` → `images:"no"`, measured from the endpoint's own 400, then served
        from cache on the next plain call*
      - *`?need=images` → `brain:null` with reason "no reachable local model accepts
        images; load a vision model in LM Studio"*
      - *`/health` advertises the `brain` capability; the claim sits after the 401 gate,
        so the tokenless 200 seen locally is the daemon's documented loopback exemption*
- [ ] **Add the wire types and the model badge**: `BrainStatus` in `Shared/Models.swift`,
      `MeshClient.brain()` in `Shared/MeshClient.swift` (both serialized), and a badge
      beside the existing `agentType` chips on iOS and the watch. No capability, no badge
      — never a placeholder.
      *Verify by running: `sh scripts/check-all.sh` and the three xcodebuild invocations;
      simulator screenshots with the brain reachable and unreachable.*
      **Needs Arya's physical devices** for the wrist-legibility check.
- [ ] **Route by capability, not preference**: image work goes to an endpoint whose
      capabilities include images; text and agentic work to the cheapest endpoint that
      passed the function-calling and terminal probes.
      *Verify by running: with only our inference up, an image request is refused with a
      reason naming the missing capability, not a generic failure.*

## Stage 4 — a long-running task on the local brain

- [ ] **Point the harness at the local endpoint** and run it inside a mux session started
      with `POST /agents/new`. One real multi-step task, clear instructions, left running
      past the phone locking.
      *Verify by running: transcript pasted here including failures, plus
      `/agents/:n/output` showing progress while the phone was asleep.*
      **Needs Arya's physical iPhone** for the phone-asleep leg.
- [ ] **Serialize turns against the single-tenant server** and send complete history each
      turn, so the one retained prefix keeps paying (`cached_tokens`).
      *Verify by running: two concurrent sessions; the second queues rather than
      corrupting the first, with the measured turn-time cost of the cache miss stated.*
- [ ] **Re-check the honesty gate**: README and web wording still describe local models
      as supported, not the default.
      *Verify by re-reading README.md and web/index.html against the spec deltas.*

## Deferred, with reasons

- [ ] ~~Vision tower in our fork~~ — a Metal ViT + projector port. LM Studio carries
      images until it is scoped as its own change.
- [ ] ~~Jetson as an LLM host~~ — 949 s/token measured on kimi-k3's Orin Nano run.
- [ ] ~~DFlash2 drafter~~ — upstream measures it losing ~11% on code/prose until
      verify-row batching lands. MTP is the speculation path.
- [ ] ~~Dense-model weight streaming (kimi-k3's pinned-prefix trunk)~~ — superseded by
      choosing MoE families; keep the technique documented for the day a dense model is
      non-negotiable.
