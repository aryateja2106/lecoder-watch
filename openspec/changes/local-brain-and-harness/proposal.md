# The local brain and the harness

## Why

The stated ambition: *"bring the best agent coding local model (strong with terminal, GUI
navigation and coding), strong harness (similar to deepseek harness) and tools package in a
minimal application where the primary client interface is phone and watch."*

Researched August 2026. The answer splits cleanly, and one half is much better news than
expected.

## Finding 1: the architecture is already right — this is the good news

The field has converged on **a persistent PTY/tmux session as the shell layer**, and that is
exactly what `meshd` already is.

- **Terminal-Bench's own reference agent, Terminus**, was built deliberately neutral so as
  not to favour any model, and it "operates purely through tmux sessions without dedicated
  tools" — a tmux pane plus raw keystrokes. ([tbench.ai/about](https://www.tbench.ai/about))
- **OpenHands** migrated away from stateless `subprocess` — it could not preserve the
  working directory or handle interactive prompts — to a `TmuxBashSession` as the default,
  keeping subprocess only as a fallback.
  ([OpenHands#9971](https://github.com/OpenHands/OpenHands/issues/9971))
- **OpenCode** gates interactive mode behind `pty: true`. **Claude Code** keeps a persistent
  bash session so state carries between calls. **deepseek-harness** encodes the split
  directly in its type system: one-shot `subprocess/` and persistent `terminal/` are
  separate, independently swappable capability packages.

`meshd` — detached multiplexer sessions, text capture, keystroke send, state that survives
between calls — is the same shape these teams each arrived at independently. It is not a
shortcut taken on the way to something better. **It is the hard, differentiated part, and it
is done.**

## Finding 2: adopt the harness, do not build it

`deepseek-harness` (released 2026-08-13, MIT, DeepSeek AI) is a plugin-composition runtime
where the agent loop, tool registry and model adapter are all replaceable plugins, and
execution reaches the outside world through two seams: `ctx.fs` and `ctx.subprocess`.

That those seams are real and load-bearing is not a marketing claim — a third party,
`dsh-worlds`, relocated an entire execution environment (cwd, env, processes, persistent
PTY terminals, LSP, filesystem) into a long-lived Docker container by implementing *only
those two interfaces*, forking none of the tool code.
([frozo-ai/dsh-worlds](https://github.com/frozo-ai/dsh-worlds))

The same seam could point at `meshd` instead of Docker. We would inherit the agent loop,
the tool registry, the approval/permission system, and an adapter for any OpenAI-compatible
endpoint — which is how a local model plugs in for free — without touching the daemon.

The caveat is real: it is a **developer preview with explicit breaking-change warnings**, a
few weeks old. Treat it as a time-boxed spike, not a bet. **OpenHands** is the mature
fallback: its `BaseWorkspace` abstraction is conceptually the same, at the cost of being
more Docker- and Python-opinionated.

Either way, the phone and watch client and the bridge into the harness stay ours. Neither
project has anything comparable, and that is the differentiator.

## Finding 3: the local model must be staged, not shipped as the brain

This is the part of the ambition that the evidence does not support on a six-month horizon.

- Open models lag closed ones by **about 4 months, or 8 ECI points**, per Epoch AI's own
  measurement — a gap they describe as similar to that between GPT-5 and GPT-5.5, and one
  that has widened slightly since late 2025.
  ([epoch.ai](https://epoch.ai/data-insights/open-closed-eci-gap))
- On **Terminal-Bench 2.1**, the entire top of the leaderboard is closed frontier models.
  The only open-weight entry in that slice sits roughly 25 points below the leader.
  ([tbench.ai leaderboard](https://www.tbench.ai/leaderboard/terminal-bench/2.1))
- The gap is worst precisely where this product needs reliability most: long-horizon,
  many-tool-call agentic loops. Single-shot coding is where local models look best.
- **No shell- or terminal-specialist open model exists.** Terminal-Bench performance tracks
  general agentic capability; there is no separate terminal-tuning axis to exploit.

What *is* realistic locally, verified against primary model cards rather than aggregator
blogs:

- **Qwen3.6-27B** — Apache 2.0, 27B dense, SWE-bench Verified 77.2, Terminal-Bench 2.0
  59.3, roughly 17–19GB at Q4_K_M. Runs on an Apple Silicon Mac with 32GB or more.
  ([model card](https://huggingface.co/Qwen/Qwen3.6-27B))
- **UI-TARS-7B** — Apache 2.0, works from raw screenshots with no accessibility tree, has a
  working MLX conversion. The realistic option for GUI grounding.
  ([bytedance/UI-TARS](https://github.com/bytedance/UI-TARS))
- **The Jetson Orin Nano 8GB is not a coding-agent host.** Measured: ~14 tok/s generation on
  a 7B Q4 model. Its honest role is narrow and fast — routing, a small grounding pass, a
  sub-4B fallback — not the brain of an agentic loop.

## Non-goals

- Shipping a local-only agent loop as the default in this cycle.
- Building an agent loop, tool schema or permission system from scratch.
- Running the coding model on the Jetson.
- Replacing `meshd`'s session model with anything. It is the part that is right.

## Recommendation

1. **Keep the daemon exactly as it is.** It is the converged design.
2. **Time-box a spike** writing a `ctx.subprocess` / `ctx.fs` provider for deepseek-harness
   that talks to `meshd`. Days, not weeks. If the preview churn hurts, fall back to
   OpenHands' `BaseWorkspace`.
3. **Frontier API stays the default brain** for long-horizon work for now, with local models
   staged in for narrow subtasks where privacy, latency or cost dominate.
4. **Qwen3.6-27B on the Mac** as the first local model, for well-scoped single-step tasks.
   **UI-TARS-7B** when GUI grounding is wanted.
5. Revisit when an open model appears in the top ten of Terminal-Bench.

## Open questions for the owner

1. Is a time-boxed spike against a three-week-old developer preview acceptable, or should
   this wait for it to stabilise?
2. Does the local model need to be the *default* to satisfy the vision, or is
   "local-capable, frontier-by-default" honest enough to ship and say out loud?
3. Does the harness run on the machine (inside `meshd`) or on the phone? On the machine is
   the only answer that survives the phone being asleep.
