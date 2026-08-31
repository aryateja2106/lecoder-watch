## Context

The proposal was written 2026-08-27 against published benchmarks. Since then two things
changed, and both move the design.

**1. A local model is now actually running and measured, and it is not the one the proposal
named.** `ornith-1.5-9b-mtp` (protoLabsAI, qwen35 arch, GGUF Q4_K_M, 6.70 GB, vision, trained
for tool use) is loaded in LM Studio on the owner's Mac and serving at `127.0.0.1:1234`. A
48-prompt spike was run against it on 2026-08-29; full results in
`.omc/research/ornith-spike.md`.

**2. The proposal's first-choice local model does not fit the hardware.** It names Qwen3.6-27B
at "roughly 17–19GB at Q4_K_M", requiring "an Apple Silicon Mac with 32GB or more". The owner's
Mac has **24 GB physical, measured at 21.67 GB used with 7.14 GB swap already** while running
LM Studio, Claude, Codex, Docker and a browser. Qwen3.6-27B is not runnable here. This was not
a bad recommendation — it was a hardware assumption that turned out to be wrong, and it
invalidates the proposal's local-model sequencing.

The owner has selected **deepseek-harness** as the direction (2026-08-29).

## Goals / Non-Goals

**Goals:**

- Adopt deepseek-harness by implementing only its `ctx.fs` and `ctx.subprocess` seams against
  `meshd`, forking no tool code.
- Make the harness's permission system the enforcement point for the model's measured refusal
  failure, rather than trusting the model to abstain.
- Replace the proposal's local-model plan with one that fits 24 GB.
- Keep the frontier API as the default brain; stage local models into narrow roles.

**Non-Goals:**

- Shipping a local-only loop as the default this cycle. Unchanged from the proposal, and the
  spike strengthens the case.
- Building an agent loop, tool schema or permission system from scratch.
- Running a coding model on the Jetson.
- Changing `meshd`'s session model.
- Fine-tuning or quantising anything.

## Decisions

### D1: The harness's approval system is a safety requirement, not a convenience

The spike's worst result: given a task it has **no tool for**, Ornith fabricated a shell
workaround **5 times out of 6** rather than declining. Asked to open a browser to a URL:

```json
{"command": "curl -s \"https://news.ycombinator.com/\" | head -100"}
```

3/3 repetitions. Asked to email a team, it ran `pwd && ls -la`. It declined correctly on
trivia 6/6 — so it knows how to not call a tool — but when a *plausible-looking* shell command
exists, it reaches for one.

This product hands a model a real shell on the user's real machine. A model that improvises
commands when it should stop is not one to run on trust. **Therefore the refusal must be
enforced outside the model**, in the harness's permission layer, against an allowlist — which
is precisely the component deepseek-harness provides and the reason adopting it beats writing
a loop.

*This reframes the adoption decision.* The proposal argued for deepseek-harness on the grounds
of inherited machinery and swappable seams. The spike adds a stronger reason: its approval
system is the mitigation for the specific way the available local model fails.

### D2: Ornith replaces Qwen3.6-27B as the first local model

Not because it is better — because Qwen3.6-27B does not fit in 24 GB and Ornith does (6.70 GB,
already resident).

What the spike says it is good at, and these are the numbers that matter for a tool-dispatch
role:

| | |
|---|---|
| Valid JSON tool-call args | **42/42 (100%)** |
| Hallucinated tool names | **0/42** |
| Correct tool selected | 33/36 (92%) |
| Required args present and correctly typed | 36/36 — ints emitted as ints |
| Declines on trivia | 6/6 |
| 4-turn context carry | PASS — recalled PID and cwd across 3 turns |
| Generation speed | flat 16–18 tok/s at any context depth |

The mechanics are genuinely solid. The judgement is not. So: **Ornith is the tool-dispatch
layer behind a hard allowlist, not the autonomous brain.** Frontier stays default for
long-horizon work, exactly as the proposal recommended — the spike does not change that
conclusion, it just supplies the local half with a model that fits.

*Alternative considered:* wait for a model that fits 24 GB and scores higher. Rejected as
indefinite — the proposal's own revisit trigger (an open model in Terminal-Bench's top ten)
remains the right long-horizon signal, and does not block using a small model in a narrow role
now.

### D3: Constrain output with `response_format`, never with prompt instructions

The spike found a clean split. Behavioural and safety rules in a system prompt were obeyed
**20/20**. A rule about literal output formatting — *"every message must begin with the exact
prefix `AGENT:`"* — was obeyed **0/8**, and standalone it echoed the rule's own markdown:

```
`AGENT:` There are many possible causes for a slow build...
```

Note the backticks it copied. Meanwhile `response_format` with a JSON schema was **100%**,
because it is grammar-constrained rather than instructed.

*Decision:* every structured output goes through `response_format`. Prompt text is for
semantics and safety rules; it is never load-bearing for format. This matters directly for the
skills the owner wants to write — a skill that specifies an output shape in prose will not work
with this model, and the spike is the evidence.

### D4: Run with `reasoning_effort: "none"`, and know that it is the only knob that works

53% of all completion tokens were reasoning. Disabling it: **mean latency 5.93 s → 3.16 s
(−47%), tail 27.9 s → 6.2 s (−78%)**, accuracy 73% → 69% — inside the noise on 48 prompts. It
also *fixed* the task-abandonment failure.

`chat_template_kwargs.enable_thinking`, `reasoning.enabled` and `/no_think` are all **silently
ignored**. Only `reasoning_effort` takes effect. A client that sets one of the other three will
believe reasoning is off while paying for it.

### D5: Treat the 8192-token ceiling as a hard error the client must check

The model advertises `max_context_length: 262144`; the loaded instance is configured at
**8192**. Exceeding it returns **HTTP 400** — not a truncation. In streaming mode it surfaces
as a **silently empty stream with zero chunks**, which produced bogus sub-0.1 s time-to-first-
token readings in the spike's first benchmark run before it was caught.

Any client must check for the 400 explicitly. An agent loop that grows its transcript will hit
this, and the failure is silent by default — the same "failure that looks like success" shape
as the terminal bug in `one-session-runtime`.

### D6: Do not rely on schema `description` fields to steer arguments

Given "run `cargo build --release` inside /tmp/foo", it ignored the `cwd` parameter **3/3** and
abandoned the task entirely 2/3 to run `ls -la /tmp/foo`. Asked for `~/.zshrc` on a Mac it
returned `/root/.zshrc` — a Linux root home, invented, and **schema-valid**, so an argument
validator will not catch it.

*Consequence:* paths and working directories must be supplied by the harness from known state,
not inferred by the model and trusted. System-prompt rules were obeyed 8/8 where schema
descriptions were ignored — so constraints belong in the prompt and in validation, not in
field descriptions.

## Risks / Trade-offs

- **The model improvises shell commands instead of refusing (5/6)** → hard allowlist in the
  harness permission layer (D1). This is the highest-severity finding in the spike and the
  reason the harness is adopted rather than written.
- **Fabricated paths pass schema validation** → the harness supplies paths from known state
  (D6); never execute a model-authored absolute path unvalidated against the host.
- **deepseek-harness is a developer preview with breaking-change warnings** → unchanged from
  the proposal; OpenHands' `BaseWorkspace` remains the fallback, and the spike does not depend
  on which is chosen.
- **8192 context is small for an agent loop** → transcript compaction is required from day one,
  and the 400 must be caught explicitly (D5).
- **Host is memory-constrained** (24 GB, 21.67 GB used, 7.14 GB swap during the spike) → Ornith
  at 6.70 GB is near the practical ceiling for a resident model on this machine. Anything
  larger displaces the tools the owner is running.
- **`parallel: 4` yields only 1.75x aggregate** and doubles per-request latency → do not design
  for concurrent local inference; serialise.
- **Benchmarking a model that is also the user's running service** → the spike loaded, ejected
  and reconfigured nothing, and this constraint must hold for any future measurement.

## Migration Plan

1. Implement the `ctx.fs` / `ctx.subprocess` provider against `meshd`, as the existing tasks
   specify. Unchanged.
2. Wire the permission layer to a hard allowlist **before** pointing any local model at a real
   shell (D1). This is now a prerequisite, not a later hardening step.
3. Point the harness at `http://127.0.0.1:1234` with `reasoning_effort: "none"` and
   `response_format` on every structured call.
4. Run the proposal's "one real task from the product's own use" through it, and record whether
   it completed unaided — the spike measured single calls, not a real end-to-end task.
5. Amend the tasks file: Qwen3.6-27B is not runnable on 24 GB; UI-TARS-7B for GUI grounding is
   unaffected and stands.

**Rollback:** the harness is additive. `meshd` is unchanged throughout, so removing the
provider leaves the product exactly as it is today.

## Open Questions

1. **Does the spike's 92% tool selection hold on a real multi-step task?** 48 single prompts
   and one 4-turn loop is not an end-to-end run. Migration step 4 answers it.
2. **Can the 8192 window be raised on this hardware without displacing the owner's tools?**
   The instance is configured well below the model's 262144 ceiling; the constraint may be
   memory rather than the model.
3. **Does an allowlist tight enough to stop the improvisation leave the agent able to do
   useful work?** The two may trade off directly, and only a real task will show it.
4. **Proposal open questions 1–3 remain open** — spike acceptability, whether "local-capable,
   frontier-by-default" is honest enough to say out loud, and where the loop runs. The spike
   does not answer any of them; question 3 is answered by the `agent-brain` spec already
   ("the brain runs on the machine, not the phone").
