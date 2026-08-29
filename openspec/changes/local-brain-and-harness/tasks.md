# Tasks

Sequenced so the cheap, reversible learning happens before any commitment.

## Spike — time-boxed, throwaway

- [ ] **Read deepseek-harness's `ctx.subprocess` and `ctx.fs` interfaces** and write down,
      in this file, whether `meshd`'s existing session API can satisfy them without adding
      a route. *Verify by writing the answer here with the interface quoted.*
- [ ] **Write a provider that adapts those two seams to `meshd`.** Follow how `dsh-worlds`
      did it for Docker. Throwaway code; do not merge it yet.
      *Verify by running: the harness completes one multi-step task end to end on a real
      machine through `meshd`, with the transcript pasted into the spike notes.*
- [ ] **Record what broke.** Preview instability, missing stdin, sandbox assumptions.
      *Verify by writing the list here — an empty list is itself a finding worth stating.*
- [ ] **Decide: continue with deepseek-harness, fall back to OpenHands, or defer.**
      Owner decision, informed by the two items above.

## Local model, on the Mac only

- [ ] **Run Qwen3.6-27B at Q4_K_M under MLX or llama.cpp** and measure honestly: tokens per
      second, memory resident, time to first token.
      *Verify by running: record the three numbers here on the actual machine.*
- [ ] **Give it one real task from the product's own use** — not a benchmark — through the
      harness, and record whether it completed unaided.
      *Verify by running: paste the transcript, including failures.*
- [ ] **Try UI-TARS-7B via its MLX conversion** against a screenshot from `/screen.jpg`, and
      record whether the click coordinates it returns actually land.
      *Verify by running: send its coordinates through `POST /input` and observe the Mac.*
- [ ] **Do NOT attempt a coding model on the Jetson.** Measured ceiling is ~14 tok/s on a
      7B. If a Jetson role is wanted, scope it to routing or a grounding pass.

## Before any claim is made publicly

- [ ] **Make the client show which model answered.** *Verify on device: run one session on a
      local endpoint and one on a hosted one, and confirm the two look different.*
- [ ] **Audit the wording.** No "local" claim while the default is hosted.
      *Verify by re-reading README.md and web/index.html against the spec delta.*

## Revisit trigger

- [ ] Re-run this research when an open-weight model enters the Terminal-Bench top ten.
      Today the top of that board is entirely closed models.
