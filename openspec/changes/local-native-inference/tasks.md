# Tasks

Sequenced so each stage produces something runnable before the next depends on it.
The local-brain-and-harness spike tasks are prerequisites for stage 3, not repeated
here.

## Stage 1 — the daemon knows about a local brain (Seam A)

- [ ] **Write `install/payload/meshd/brain.ts`** following the `wol.ts`/`files.ts`
      claim-function pattern: `GET /brain` returns `{reachable, endpoint, model,
      source}` by probing configured loopback candidates (MferenceServer
      `127.0.0.1:8080/v1`, LM Studio `127.0.0.1:1234/v1`; `MESHD_BRAIN_URL`
      overrides). Server down is `{reachable:false}` with HTTP 200 — never a 500.
      Add `"brain"` to `CAPABILITIES`. The `server.ts` edit is two lines plus the
      capability string (serialized file — one agent, nothing else in the same PR).
      *Verify by running: boot a spare-port daemon (`MESHD_PORT=8898 … bun run
      install/payload/meshd/server.ts`), `curl -s :8898/brain` with and without a
      fake OpenAI server on the candidate port, paste both JSON bodies here. Then
      `bun x tsc --noEmit -p install/payload/meshd/tsconfig.json`.*
- [ ] **Add the wire types**: `BrainStatus` in `Shared/Models.swift` and
      `MeshClient.brain()` in `Shared/MeshClient.swift` (both serialized files),
      gated on the `brain` capability string, never on version.
      *Verify by running: `sh scripts/check-all.sh` plus the three xcodebuild
      invocations from AGENTS.md.*
- [ ] **Show which model is answering**: a model badge beside the existing
      `agentType` chips in `iOS/ContentView.swift`/`TerminalView.swift` and
      `Watch/WatchViews.swift`, sourced from `/brain`; absent capability = no badge,
      never a placeholder.
      *Verify by running: simulator screenshots against a spare-port daemon with a
      stub OpenAI server, one with the brain reachable and one without.*
      **Needs Arya's physical devices** for the final wrist-legibility check.

## Stage 2 — a local model actually serving on the Mac

- [ ] **Check disk, then install Qwen 3.6 35B-A3B via mference's streaming
      installer** on the MacBook (~19.6 GB; installer is resumable and never needs
      2× disk). Do not touch the running LM Studio (AGENTS.md rule 5).
      *Verify by running: `df -h` before/after pasted here, plus the installer's
      `verified-install.json` summary.*
- [ ] **Run MferenceServer and measure honestly**: tokens/sec, peak RSS, time to
      first token, on the owner's actual machine, using mference's own benchmark
      protocol (no competing model process — coordinate a window when LM Studio is
      idle, never kill it).
      *Verify by running: record the three numbers here with the hardware and
      context-length settings.*
- [ ] **Prove the prompt cache does what stage 3 needs**: two `POST
      /v1/chat/completions` requests where the second exactly extends the first's
      history; confirm `usage.prompt_tokens_details.cached_tokens` covers the
      prefix.
      *Verify by running: paste both usage blocks here.*
- [ ] **Supervise it**: `mesh` CLI (or launchd via the installer payload) starts the
      server, waits for the `MferenceServer ready` line, restarts on crash, and
      `mesh uninstall` removes every trace (principle 5 — one clean install, one
      clean uninstall).
      *Verify by running: `mesh doctor` shows the brain; kill the server process and
      show it comes back; run the uninstall check script.*

## Stage 3 — a long-running task through the local brain (Seam B)

- [ ] **Point the harness at the local endpoint** (one config value on its OpenAI
      adapter, per the local-brain-and-harness spike) and run it inside a mux
      session started with `POST /agents/new`. Give it one real multi-step task from
      the product's own use with clear instructions, and let it run past the phone
      locking.
      *Verify by running: transcript pasted into the spike notes, including
      failures, plus the `/agents/:n/output` capture showing progress while the
      phone was asleep.* **Needs Arya's physical iPhone** for the phone-asleep leg.
- [ ] **Serialize agent turns against the single-tenant server**: whatever drives
      the harness must send complete history each turn and hold one conversation at
      a time (the server retains exactly one cached prefix; a second interleaved
      conversation thrashes it).
      *Verify by running: two concurrent sessions; show the second queues rather
      than corrupting or starving the first, and state the measured turn-time cost
      of the cache miss.*
- [ ] **Re-check the honesty gate** inherited from local-brain-and-harness: README
      and web wording still say local models are *supported*, not the default.
      *Verify by re-reading README.md and web/index.html against the agent-brain
      spec delta.*

## Explicitly deferred (do not pick these up inside this change)

- [ ] ~~Jetson as an LLM host~~ — measured out (949 s/token on kimi-k3; ~14 tok/s
      on a 7B). Routing/grounding only, and not in this change.
- [ ] ~~DFlash2 drafter~~ — revisit when upstream lands verify-row batching; MTP is
      the speculation path.
- [ ] ~~Weight-streaming for dense models (kimi-k3's pinned-prefix trunk)~~ —
      superseded for now by choosing MoE models; keep the technique in the
      reference doc for the day a dense model is non-negotiable.
