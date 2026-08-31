# Local native inference

## Why

The owner's ask, verbatim: *"I want us to have local native inference for models we are
currently using … I want to start using models like qwen 3.8 27b, but I don't have
enough memory and storage to run them. I want us to start running local models and work
on long running tasks given clear instructions."*

[local-brain-and-harness](../local-brain-and-harness/proposal.md) already settled the
strategy (keep meshd's session layer; adopt a harness; stage the local model in,
frontier-by-default). It left the *mechanics* open: which local engine, how a
too-big model fits the owner's actual Mac, and how the daemon and clients learn a
local brain exists. Two vendored codebases — studied in depth in
[docs/local-inference-references.md](../../../docs/local-inference-references.md),
source in [references/](../../../references/README.md) — close those gaps.

## What the references established

1. **The memory complaint dissolves with the right model shape.** Dense Qwen 3.8 27B
   needs ~15 GB resident (a 24 GB Mac). **Qwen 3.6 35B-A3B — the same quality class —
   runs in ~1.45 GB of RAM and ~20 GB of disk** at 10–14 tok/s even under a verified
   8 GB working set, via mference's SSD expert streaming. The binding constraint
   becomes ~20 GB of disk, and mference's resumable byte-range installer never needs
   2× disk. MoE-with-few-active-params first, quantization second, streaming third.
2. **A local OpenAI-compatible server already exists and matches our daemon.**
   `MferenceServer` (loopback, SSE streaming, tool-call parsing, a single-prefix
   prompt cache that makes agent-loop turns cheap) has exactly the gaps meshd
   already fills for other loopback services: bearer auth, the Host/browser guard,
   fleet reachability. meshd fronts OpenUsage and the cmux bridge today; a model
   server is the third of that species.
3. **Both references agree on the discipline**: stream weights from SSD with explicit
   reads (both measured mmap/page-cache losing badly), gate every trick on
   byte-identical output, and plan memory up front — refuse to start rather than OOM
   an hour into a task.

## What this change delivers

Three seams, each independently shippable, in order:

- **Seam A — `brain.ts`**: a self-contained meshd module (the `wol.ts`/`files.ts`
  pattern) that discovers and health-checks a loopback OpenAI-compatible model server
  (MferenceServer, LM Studio, llama.cpp — the spec is endpoint-agnostic), exposes
  which model is loaded, and adds a `brain` capability string. Plus the wire types
  and a model badge so the phone and watch show which model is answering — the
  release gate the agent-brain spec already demands.
- **Local model on the Mac**: MferenceServer supervised as a service, with
  **Qwen 3.6 35B-A3B as the first local model** (Qwen 3.8 27B + MTP when a 24 GB Mac
  is available). Measured honestly on the owner's machine before any claim.
- **Seam B — long-running tasks**: the harness (per local-brain-and-harness) runs in
  a mux session started via `POST /agents/new`, with its OpenAI adapter pointed at
  the local endpoint. The phone/watch see, steer, and get pushed about it through
  today's plumbing; turns stay cheap because the daemon serializes agent turns and
  sends complete history, exploiting the server's single-prefix prompt cache.

## Target user skill level

Unchanged from the product brief: non-technical people. They will not run a llama.cpp
command or edit an env file. Installing and serving a local model must be one pasted
command (`mesh` CLI) or one button (MeshDesktop), and removal must be as clean.
Choosing a model is choosing from a short named list with disk/RAM requirements shown
up front — never a HuggingFace URL.

## Non-goals

- Making the local model the *default* brain this cycle (local-brain-and-harness
  finding 3 stands; the honesty spec requirement stands with it).
- Building an inference engine, or embedding one in-process in meshd or the apps —
  mference's own Mac app isolates the model in a helper process; we front a server.
- Generic GGUF/any-checkpoint support. First ship is the curated list mference pins.
- Running the coding model on the Jetson (949 s/token measured on kimi-k3-in-c's
  Orin Nano proof-of-life; ~14 tok/s on a 7B — routing/grounding roles only).
- Replacing meshd's session model, or adding a second daemon payload copy.
- DFlash2 speculative decoding (loses on code/prose until its verify-batching lands;
  MTP is the shipped speculation path).

## Open questions for the owner

1. Disk: is ~20 GB for Qwen 3.6 35B-A3B available on the MacBook? If not, Gemma 4
   26B-A4B (~14.3 GB disk, ~2 GB RAM) is the fallback first model.
2. Does the first supervised-server ship go through the `mesh` CLI or MeshDesktop?
   (The CLI is cheaper; MeshDesktop is the non-technical answer. Recommend CLI first,
   button second — same underlying commands.)
3. LM Studio already runs on the Mac. Treat it as a supported endpoint from day one
   (Seam A is endpoint-agnostic anyway), or standardize on MferenceServer for the
   supervised path? Recommend: detect both, supervise only MferenceServer.
