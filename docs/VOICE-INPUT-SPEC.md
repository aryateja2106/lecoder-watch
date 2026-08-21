# Project: Voice-First Input for Watch-Controlled Mac

You are building the voice-input subsystem for an existing watchOS + macOS product. The watch app already renders a zoomable remote view of the Mac's screen and provides a trackpad-style mouse. Typing on this surface is impractical — voice is the keyboard. Users dictate to control agents, terminals, and apps on their Mac, and they must be able to **review and edit the transcript before anything is sent**.

## Product principles (non-negotiable)

1. **Local-first.** No cloud STT. All speech recognition runs on the user's devices (Watch, Mac) or their own LAN hardware (Jetson). Audio never leaves the user's machines.
2. **Native experience.** Swift/SwiftUI on watchOS and macOS. No Electron, no Python processes in the user-facing path on-device (a C++/ggml local server is acceptable on the Mac as a background service).
3. **Fidelity.** Always store the raw verbatim transcript alongside any cleaned/corrected version. Every correction is visible inline and reversible. Never silently rewrite what the user said — users dictate file paths, shell commands, and project names where a confident wrong "fix" breaks things.
4. **Review before dispatch.** Transcript appears in an editable preview; nothing reaches an agent/app/terminal until the user confirms.

## User profile driving design decisions

- Primary dictation language: **English with a thick Indian accent (en-IN)**. Occasional Telugu loanwords mid-sentence when the user is comfortable; no full Hindi/Telugu dictation in v1.
- Critical failure mode to solve: **rare named entities** — project names, framework/library names, file paths, domains (e.g. "aryateja.com"), terminal commands. Stock ASR misspells these, and downstream agents then hallucinate on the wrong entity.
- Users speak in flow state: fillers ("hmm", "um"), repetitions, self-corrections ("open Bom— I mean Delhi"). The system needs an optional cleanup pass, toggleable per dispatch target (verbatim for commands/paths; cleaned for prose delegation).

## Existing assets (build on these, do not reinvent)

| Asset | What it provides |
|---|---|
| **macparakeet fork** — github.com/moona3k/macparakeet (GPL-3.0, Swift 6, SwiftUI) | macOS dictation app: Parakeet TDT 0.6B-v3 via FluidAudio CoreML on Neural Engine (~66MB working memory, ~155x realtime, ~2.5% WER), optional WhisperKit engine, **Vocabulary panel with Raw/Clean dual-transcript pipeline** (filler removal → custom word replacement → snippet expansion → whitespace cleanup, deterministic, <1ms), CLI (`brew install moona3k/tap/macparakeet-cli`), SQLite history storing raw+clean |
| **watchOS remote-control app** | Existing Control UI (zoomable screen, mouse/trackpad, routes "via phone"). Add push-to-talk voice capture here |
| **MacBook (Apple Silicon)** | Runs macparakeet fork + will host the ASR server lane |
| **Apple Watch Series 9** (S9 SiP, ~1GB RAM, watchOS 26) | Capture + light on-device recognition only |
| **Jetson Orin Nano (8GB)** | Fine-tuning jobs + optional LAN ASR server |

## Hard constraints

- **Do NOT attempt Parakeet/Nemotron 0.6B on the Watch.** Even at q4 (~460MB) it exceeds usable watchOS app memory with streaming caches. The Watch lane uses Apple Speech framework or a sub-100MB CoreML model.
- **MLX does not run on watchOS** (mlx-audio / mlx-audio-swift support macOS/iOS/visionOS only). MLX tooling is Mac-side only.
- Parakeet TDT 0.6B-v3 covers **25 European languages only** — no Telugu/Hindi. Nemotron 3.5 ASR covers 40 locales **including Hindi but not Telugu**. For v1, handle Telugu loanwords via the vocabulary/biasing system, not a dedicated Telugu ASR model.

## Target architecture (three lanes)

```
WATCH LANE (light, on-device)              MAC LANE (heavy, on-device)
┌──────────────────────────────┐          ┌─────────────────────────────────────┐
│ Push-to-talk capture         │          │ ASR server: parakeet.cpp            │
│ AVAudioEngine → 16kHz mono   │  PCM/    │ Nemotron 3.5 ASR q4k-q8 GGUF        │
│ Fast path: Apple Speech      │  Opus ──►│ (~460MB, Metal/CUDA/CPU)            │
│ framework on-device en-IN    │  LAN/    │ cache-aware streaming, <EOU> events │
│ + contextualStrings          │  phone   │ Fallback: FluidAudio Parakeet v3    │
│ (SFSpeechRecognizer /        │  relay   │ CoreML via macparakeet runtime      │
│ SpeechAnalyzer)              │          ├─────────────────────────────────────┤
│ Experiment (Phase 4):        │          │ CORRECTION LAYER                    │
│ Moonshine tiny CoreML (34M)  │          │ 1. Project-context bias list        │
│                              │          │ 2. Phonetic fuzzy-match on user     │
│ Editable transcript preview ─┼─────────►│    vocab (confidence-gated,         │
│ → user confirms → dispatch   │          │    inline accept/reject)            │
└──────────────────────────────┘          │ 3. Optional cleanup (fillers,       │
                                          │    disfluencies) — toggleable       │
DISPATCH: keystroke injection /           │ ALWAYS: store raw + clean;          │
macparakeet-cli / agent CLI / Messages    │ corrections reversible              │
                                          └─────────────────────────────────────┘
JETSON LANE (offline/training): NeMo fine-tunes, per-user LoRA from voice samples,
Svarah evaluation, optional parakeet.cpp LAN server (CUDA or CPU)
```

Transport note: the existing app already relays via the paired iPhone ("via phone"). Prefer direct Watch→Mac over local WiFi when reachable; fall back to WatchConnectivity (phone relay). Stream 16kHz mono PCM (Opus if bandwidth-constrained). Latency budget: partial transcript visible on watch < 500ms after speech onset; final + corrections < 1s after end-of-utterance.

## The vocabulary system — bias first, fine-tune last

This is the core differentiator. Three tiers, cheapest to strongest:

**Tier 0 — zero-training biasing (build first):**
- Apple Speech: `SFSpeechRecognitionRequest.contextualStrings` for user vocabulary on the Watch lane.
- macparakeet Vocabulary pipeline already does custom word replacement ("aye pee eye" → "API") — extend, don't replace.
- **Project-context injection (our unfair advantage):** since users delegate to agents on their own machines, index the actual workspace — file/folder names, package.json/pyproject dependencies, git remotes and branch names, recent shell history — into the bias list. "kubectl" stops being a rare word when it came from the user's own history. (RAG-context ASR shows 17–24% relative WER reduction: aclanthology.org/2025.findings-emnlp.768.pdf)
- Trie/phonetic-variant decode-time biasing cuts biased-word WER ~42–43% without touching normal words; Apple's class-LM word-mapping research shows 57% entity-WER reduction via pronunciation-similar mapping.

**Tier 1 — phonetic correction pass:**
- Post-ASR pass that revises ONLY named entities sounding similar to user-vocab entries (g2p phonemization + phonetic fuzzy match; an LLM revision variant shows ~30% relative entity-WER reduction: arxiv.org/html/2506.10779v1). Confidence-gated; every correction shown inline with accept/reject. Log decisions as training pairs.

**Tier 2 — per-user fine-tuning (Jetson, periodic):**
- Users can add vocabulary as text AND upload (voice sample + exact spelling) pairs.
- Accumulate pairs → LoRA fine-tune whisper-tiny.en / Moonshine on AI4Bharat Svarah (9.6h Indic-accented English, 117 speakers: github.com/AI4Bharat/Svarah) + user samples → convert to CoreML (watch lane) or GGUF via parakeet.cpp's conversion pipeline (server lane).
- When fine-tuning, perturb reference transcripts with similar-sounding wrong spellings so the model learns to prefer bias context (up to 60% relative rare-word error reduction).
- NVIDIA's official Nemotron fine-tuning guide is linked from huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b.

## Disfluency cleanup

- Whisper's English normalizer already strips `\b(hmm|mm|mhm|uh|um)\b`; the "fluent-whisper" adapter approach (huggingface.co/blog/pradachan/fluent-whisper, Apache-2.0) handles all four disfluency types (filled pauses, discourse markers, repetitions, self-repairs) — 9.4%→3.4% WER on disfluent speech.
- Implement as a toggleable layer over the verbatim transcript. Two modes exposed in UI: **Verbatim** (commands, paths, commit messages) and **Clean** (prose delegation).

## Build phases (in order — do not skip ahead)

**Phase 1 — Watch capture + Apple Speech + review UI**
- Push-to-talk in existing Control UI; AVAudioEngine 16kHz mono capture.
- `SFSpeechRecognizer` (locale en-IN) with `requiresOnDeviceRecognition = true` and `contextualStrings` loaded from a shared vocabulary store. On watchOS 26 evaluate the newer `SpeechAnalyzer`/`SpeechTranscriber` Swift API as the primary path.
- Editable transcript preview on watch; confirm → dispatch via existing remote-control channel (keystroke injection on Mac).
- Acceptance: dictate "open terminal and run kubectl get pods" → editable preview → injects correctly; works fully offline on watch.

**Phase 2 — Mac ASR server (parakeet.cpp + Nemotron 3.5)**
- Build parakeet.cpp (github.com/mudler/parakeet.cpp) for macOS arm64/Metal; download Nemotron 3.5 q4k-q8 GGUF (~460MB, e.g. huggingface.co/kashif3314/nemotron-3.5-asr-streaming-0.6b-gguf or cstr/nemotron-3.5-asr-streaming-GGUF — both validated WER-0 vs NeMo).
- Local HTTP/WebSocket server (OpenAI-compatible endpoint available via LocalAI's parakeet-cpp backend if preferred); streaming with `<EOU>` end-of-utterance events.
- Watch streams audio → server → partials back. Acceptance: <500ms first partial, transcript parity with NeMo reference, per-utterance language detection tags (40 locales, auto via prompt_index=101 in sherpa-onnx builds).

**Phase 3 — Vocabulary + correction layer**
- Shared vocabulary store (text entries + audio/spelling sample uploads) synced watch↔Mac.
- Workspace indexer (file names, deps, git, shell history) → bias list.
- Phonetic fuzzy-match correction pass, confidence-gated, inline accept/reject UI on both watch preview and Mac. Acceptance: a user-added project name spoken once with audio sample is recognized correctly in subsequent dictations without any model retraining.

**Phase 4 — Moonshine on Watch + fine-tune pipeline**
- Convert moonshine-streaming-tiny (34M, huggingface.co/moonshine-ai/moonshine-streaming-tiny; repo github.com/moonshine-ai/moonshine) to CoreML via coremltools; benchmark vs Apple Speech on-device for latency/WER/battery on Series 9. Ship only if it beats Apple Speech on en-IN-accented command dictation.
- Jetson: LoRA fine-tune recipe on Svarah + user samples; CoreML/GGUF export; OTA model update channel.
- Optional: Supertonic (github.com/supertone-inc/supertonic, 99M-param ONNX TTS with Swift/iOS SDK) for the return lane — agents speaking short confirmations back to the watch.

## Explicit non-goals for v1

- No Parakeet/Nemotron on Watch. No MLX on Watch.
- No full Telugu/Hindi ASR pipeline (loanword biasing covers the actual usage pattern).
- No cloud STT or cloud LLM in the transcription path (local-only correction; LLM rescoring, if used, must be a local model).

## Key references (read these before writing code)

**Runtimes & models**
- parakeet.cpp: github.com/mudler/parakeet.cpp — conversion pipeline, GGUF, benchmarks (deepwiki.com/mudler/parakeet.cpp)
- Benchmarks + design rationale: localai.io/blog/parakeet-cpp-asr-on-cpu/ (27x whisper.cpp turbo on CPU at equal accuracy; streaming EOU details)
- Nemotron 3.5 ASR model card + official fine-tune guide: huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b
- GGUF builds: huggingface.co/kashif3314/nemotron-3.5-asr-streaming-0.6b-gguf (q4k-q8 0.46GB, WER-0 parity), huggingface.co/cstr/nemotron-3.5-asr-streaming-GGUF, huggingface.co/memoravox/nemotron-3.5-asr-streaming-0.6b-gguf
- sherpa-onnx NeMo transducer (ONNX alternative, chunk-size variants, language prompt_index table): csukuangfj.github.io/sherpa/onnx/nemo/nemotron-streaming.html + pantinor/nemotron-3.5-asr-streaming-0.6b-onnx
- FluidAudio (Parakeet CoreML Swift SDK, ANE): github.com/FluidInference/FluidAudio — model FluidInference/parakeet-tdt-0.6b-v3-coreml
- macparakeet (fork base): github.com/moona3k/macparakeet — read spec/ directory and CLAUDE.md first
- mlx-audio (Mac-side experimentation: Nemotron 3.5 MLX, Moonshine, Qwen3-ASR, Whisper turbo): github.com/Blaizzy/mlx-audio
- Moonshine: github.com/moonshine-ai/moonshine, huggingface.co/moonshine-ai/moonshine-streaming-tiny, Flavors paper arxiv.org/html/2509.02523v1
- WhisperKit: github.com/argmaxinc/WhisperKit

**Apple platform APIs**
- SFSpeechRecognizer on-device recognition (`requiresOnDeviceRecognition`, `contextualStrings`): developer.apple.com/documentation/speech
- 2026 landscape (WhisperKit vs SpeechAnalyzer on iOS/watchOS): forasoft.com/blog/article/speech-recognition-with-neural-networks-on-ios-1621
- watchOS 26 feature availability (on-device dictation locales incl. en-IN): apple.com/watchos/feature-availability/

**Accuracy research**
- Svarah Indic-accented English dataset/benchmark: github.com/AI4Bharat/Svarah
- LLM named-entity revision: arxiv.org/html/2506.10779v1
- RAG context discovery for ASR: aclanthology.org/2025.findings-emnlp.768.pdf
- BR-ASR bias retrieval (200k-entry lists, FAISS ~20ms): isca-archive.org/interspeech_2025/gong25_interspeech.pdf
- Contextual biasing training w/ phonetically perturbed references: isca-archive.org/interspeech_2024/huang24f_interspeech.pdf
- Apple class-LM + pronunciation word mapping: machinelearning.apple.com/research/class-lm-and-word-mapping
- Fluent-Whisper disfluency cleanup: huggingface.co/blog/pradachan/fluent-whisper

**TTS return lane (optional, Phase 4)**
- Supertonic: github.com/supertone-inc/supertonic (ONNX, Swift/iOS examples, `pip install supertonic`, local `supertonic serve` OpenAI-compatible endpoint)

## Working agreements

- Swift 6 + SwiftUI everywhere user-facing; follow macparakeet's existing patterns (GRDB for storage, its Raw/Clean pipeline for text processing).
- Every phase ends with a measurable acceptance criterion above; benchmark on the user's own command corpus plus Svarah samples before/after each accuracy change.
- Prefer reading upstream docs/repos over guessing APIs — all links above are load-bearing.
