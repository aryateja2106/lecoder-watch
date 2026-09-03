# Local native inference

## Why

The owner's ask, verbatim: *"I want us to have local native inference for models we are
currently using … I want to start using models like qwen 3.8 27b, but I don't have
enough memory and storage to run them. I want us to start running local models and work
on long running tasks given clear instructions."* Then, once the numbers were on the
table: *"i think the 2gb memory option is far better than 8-15gb, in fact i want us to
support all the models they are providing from this repo, we can create our own fork
and start working inside the repo."* And on audience: *"lm studio for non technical
developers who wants their existing setups to work and our own inference for better
best value for the memory spent. We want to address & support both kind of audience."*

[local-brain-and-harness](../local-brain-and-harness/proposal.md) settled the strategy
(keep meshd's session layer, adopt a harness, stage the local model in). This change
settles the mechanics, against findings verified line by line in
[docs/local-inference-references.md](../../../docs/local-inference-references.md).

## What the source says, once checked

1. **The 2 GB tier is the right tier, and it is a dial, not a constant.** Qwen 3.6
   35B-A3B runs at ~1.45 GB in the 16-slot expert-cache profile and ~6.8 GB at 96
   slots; more wired slots buy tokens/sec. `RuntimeConfiguration.defaultExpertCacheSlots`
   picks the profile from host RAM (≥24 GiB → 96, ≥16 GiB → 32, below → 16).
2. **The server cannot ask for the cheap profile.** `MferenceCLI` has
   `--expert-cache-slots`; `MferenceServer` builds its runtime straight from the
   auto-selection (`Sources/MferenceServer/Core/ServerInference.swift:218-232`) with no
   override. On a 16 or 24 GB Mac the server silently takes the larger footprint. This
   is the first patch our fork should carry.
3. **Mference is text-only — every family.** `RepackPlanner.isExcludedTensorName`
   drops `vision_tower.`, `embed_vision.`, `audio_tower.`, `model.visual.` and
   `model.audio.` at install; nothing in the engine consumes pixels. Function calling
   and terminal/browser tool use are supported and fail closed; **reading images is
   not**, so the owner's third condition cannot be met by this engine.
4. **Storage is the binding constraint, not memory.** Against ~30–40 GB free: Qwen 3.6
   (~19.6 GB), Gemma 4 (~14.3 GB) and Maple (~6.6 GB) fit; Qwen 3.8 27B fits on disk
   but wants ~15 GB RAM; DeepSeek-V4-Flash (~91 GB) and Inkling-Small (~148 GB) do not.

## What this change delivers

**Two brains, deliberately, because there are two audiences.**

- **LM Studio** — for people who already run a local setup and will not build Swift. We
  detect it and use it; we never supervise or restart it. It is also, today, **the only
  path to image input**: a vision model loaded there answers screenshot and GUI-grounding
  work that Mference structurally cannot.
- **Our Mference fork** — for the best capability per gigabyte. We supervise it, patch
  it, and measure it. First patch: `--expert-cache-slots` on the server, so the ~1.45 GB
  profile is selectable. Beyond that, expose **every family the upstream supports**, with
  disk and RAM stated up front and the ones that cannot fit this machine marked as such
  rather than hidden.

Both are reached identically: an OpenAI-compatible loopback endpoint behind meshd's
bearer auth, surfaced through one capability-gated `brain` route and one model badge on
the phone and watch. Routing is by capability, not by preference: image work goes to the
endpoint that accepts images, text and agentic work to the cheapest endpoint that passes
the function-calling and terminal probes.

**Grading is not a matter of opinion.** [`scripts/brain-eval/`](../../../scripts/brain-eval/README.md)
runs one scorecard against any OpenAI-compatible endpoint — function calling, terminal
actions through meshd-shaped tools, browser sequencing, image acceptance, prefix reuse,
stop discipline — so both engines are compared with the same probes and the answer is
recorded rather than argued.

## Target user skill level

Unchanged: non-technical. Choosing a model is picking from a named list that states its
disk and RAM cost, not pasting a HuggingFace URL. Installing and serving is one command
or one button; removal is as clean. The LM Studio path exists precisely so that someone
who already has a working setup does not have to learn ours.

## Non-goals

- Making a local model the *default* brain this cycle. Frontier-by-default stands, and
  so does the honesty requirement that goes with it.
- Building an inference engine, or embedding one in-process in meshd or the apps.
  Mference's own Mac app isolates the model in a helper process; we front a server.
- Adding a vision tower to our fork in this change. It is a Metal ViT + projector port —
  scope it separately, and use LM Studio for images until it exists.
- Running the coding model on the Jetson (949 s/token measured on kimi-k3's Orin Nano
  proof-of-life).
- Generic GGUF loading in our fork, or supervising LM Studio.
- Shipping DeepSeek-V4-Flash or Inkling-Small on this machine — they are supported in
  code and marked as not installable here.

## Open questions for the owner

1. Fork host: this session's GitHub scope is limited to `aryateja2106/lecoder-watch`, so
   the fork must be created once by hand (`gh repo fork NeelM0906/Mference --clone`, or
   the Fork button). Which account or org should own it?
2. How much RAM does the MacBook have? It selects the slot profile, and therefore both
   the footprint and the tokens/sec we will measure.
3. Vision: accept LM Studio as the image path for now, or scope the Metal vision-tower
   port as its own change?
