# references/ — vendored reference codebases

Third-party codebases vendored for study, not for building. They inform the
local-native-inference work (see
[openspec/changes/local-brain-and-harness/](../openspec/changes/local-brain-and-harness/)
and the analysis in [docs/local-inference-references.md](../docs/local-inference-references.md)).
Nothing in this repo compiles against them; treat them as read-only source material.
Each keeps its own LICENSE — they are not under this repo's license.

| Directory | Upstream | Pinned commit | License |
|---|---|---|---|
| `kimi-k3-in-c/` | [FareedKhan-dev/kimi-k3-in-c](https://github.com/FareedKhan-dev/kimi-k3-in-c) | `117e9d29bde14db9742f54fb66a191fd0bf03903` (2026-08-26) | see its LICENSE/NOTICE |
| `mference/` | [NeelM0906/Mference](https://github.com/NeelM0906/Mference) | `297c0080947d8be0ddc65f973217c0d14d1d68fd` (2026-08-28) | see its LICENSE / LICENSE-APACHE / LICENSE-MLX |

## What each one is

- **kimi-k3-in-c** — a pure-C99 CPU inference engine that runs Moonshot's 1.56 TB
  Kimi K3 checkpoint in 8 GB of RAM with byte-identical output, by streaming weights
  from SSD (pinned-prefix + ring, page-cache bypassed). Interesting for the
  *byte-placement discipline*, not the kernels: weight streaming, memory
  plan-then-refuse, session state snapshots.
- **mference** — a from-scratch Swift + Metal inference engine for Apple Silicon
  ("big MoE models in 'small' GB of RAM"): SSD expert streaming, paged KV with SSD
  spill, byte-identical speculative decoding (MTP + a DFlash2 drafter), a resumable
  streaming installer, and an OpenAI-compatible loopback server. The candidate
  local-model sidecar for `meshd`. Not built on MLX — it consumes MLX-community
  checkpoints with its own kernels.

## Pruned from the vendored copies

To keep the repo small, the copies are source-complete but asset-pruned. Fetch the
pinned commit from upstream if you need any of this:

- both: `.git/` history (shallow clones to begin with)
- `kimi-k3-in-c/tests/fixtures/` (~24 MB of golden tensors and model binaries — unit
  tests will not run without them)
- `kimi-k3-in-c/docs/images/` (~17 MB) and `docs/kimi-k3-tech-report.pdf` (~2.4 MB)

Re-vendor by cloning upstream at a newer commit, applying the same prunes, and
updating the pinned commit in the table above.
