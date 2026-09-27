# Reference review: agent-git (agit)

Reviewed 2026-09-27 against our tree at `88a1332` (branch `sdlc/ai-native-playbook`) and the
read-only clone at `references/external/repos/agent-git` (commit `718cb6c`, 2026-09-27).
Nothing in the clone was built or run. Paths starting `agit:` are inside the clone; all other
paths are in this repo.

---

## For Arya

agent-git is a well-built Rust tool that does what our `mesh sessions` already does (keep every
agent conversation so it can be found and resumed), plus one thing we deliberately do not: it
publishes conversations to its own hosted website so other people can pick them up. That
publishing needs an account, and on their official hub the usage statistics cannot be switched
off (`agit:docs/telemetry.md:8-22`), which conflicts with our "no account, nothing leaves your
machines" promise (`ROADMAP.md:114-118`). So there is nothing to adopt wholesale, and our own
version is already running on your Mac, Pi and Jetson. It is still worth studying for three
ideas: one shared reader for agent transcripts instead of four separate ones, a streaming
redactor that cannot miss a secret cut in half, and a clean way to ship a native binary per
platform. On Rust: my recommendation is **not to add Rust now**. Nothing we have measured is
slow enough to need it, and when something is, the safe way is a separate helper program that
the daemon talks to (the same way it already talks to `mesh-input`), not code loaded inside the
daemon. The license is MIT, so we may copy or adapt code as long as we keep their copyright
notice.

---

## What it is

`agit` is a command-line program that puts version control on top of agent transcripts
(Claude Code, Codex, OpenCode, Cursor, and several others) so a session can be saved, browsed,
published, shared and resumed (`agit:README.md`).

- **Adoption is explicit.** A session enters version control only when the user runs
  `agit import <id> -n <agent>`; later versions come from `agit commit`
  (`agit:src/lib.rs:8-33`, `agit:docs/02_session_store.md:142-170`). Our daemon instead
  snapshots every transcript automatically (`install/payload/meshd/sessions.ts:230-253`).
- **Recording a version needs a login.** The version's git author and its storage path both
  come from the hub account (`agit:docs/02_session_store.md:6-30`). Only `--link-only` works
  offline.
- **Sharing is through a hosted hub** (`agent-git.com`). `agit push` is `git push` to the hub;
  `agit clone owner/repo` picks up someone else's session (`agit:docs/02_session_store.md:629-800`).
  The hub server is a separate repository that is not in this clone (`agit:README.md`, "The server
  (AgentGit) is a separate repository"). Whether its source is public: unverified here.
- **A resident daemon (`agitd`, `agit rc`)** supervises agent processes and streams their
  events to the hub over WebSocket, with SSH and a cloud relay as transports
  (`agit:Cargo.toml` feature `rc`, `agit:crates/agit-tunnel/README.md:14-19`,
  `agit:docs/rfc-rc-cloud-relay.md`).
- **Size.** About 283,500 lines of Rust across `src/` and `crates/` (343 `.rs` files under
  `src/` alone), counted with `wc -l`. Our whole session feature is `sessions.ts` (564 lines) plus
  `chats.ts` (290 lines).

### Side by side with our session snapshots

| | agit | ours (`sessions.ts` + `chats.ts`) |
|---|---|---|
| **What gets kept** | Only sessions the user adopts (`agit:src/lib.rs:8-16`) | Every Claude Code and Codex transcript on the machine, by a sweep every ten minutes and on each Stop/Notification hook event (`sessions.ts:230-253`, `PRODUCT.md:152`) |
| **Runtimes** | Claude Code, Codex, OpenCode, Cursor, Claude Desktop, Hermes, OpenClaw, WorkBuddy adapters (`agit:src/adapter/`) | Claude Code and Codex only (`sessions.ts:64`); subagent `agent-*` files skipped (`sessions.ts:81-90`) |
| **Data model** | One git repository per agent at `~/.agit/repos/<owner>/<name>/`. Each transcript line is wrapped in a 4-key envelope and stored once as a content-addressed event file `events/a/b/c/d/<event-id>`; `LOG` lists every event id in order, `VIEW` lists the ones a resume uses (from the last compaction onward). A version is a git commit, its id is `agit-<commit sha>` and it is a git tag (`agit:docs/02_session_store.md:38-58, 172-195, 329-428`) | Per session, `~/.mesh/sessions/<runtime>/<id>/index.json` plus `v<N>.gz`. A version is either a full **base** or an **append** holding only the new bytes; append is chosen when the first *previous-size* bytes still hash (sha256) to the previous version (`sessions.ts:10-17, 64-66, 133-171`) |
| **Change detection** | Per-line hash of the *parsed* JSON (`_object_hash`, sorted keys), so whitespace or key order is not a change; three verdicts Noop / Append / Diverged (`agit:docs/02_session_store.md:359-392, 434-450`) | Byte-prefix sha256; anything that is not a pure byte append is a new base (`sessions.ts:150-167`) |
| **Compaction** | Identical lines are stored once, so a rewritten transcript reuses existing events (`agit:docs/02_session_store.md:454-456`) | A compaction writes a new full base; bytes shared with the old base are stored again (`sessions.ts:162-167`) |
| **Integrity** | git commit hash covers the whole tree; `agit doctor` checks metadata, prefix continuity and VIEW consistency (`agit:docs/02_session_store.md:807-866`) | Every read rebuilds base + appends and refuses the result if its sha256 differs from the recorded one (`sessions.ts:196-210`) |
| **Search** | Query syntax shared by CLI and hub (`agit:src/lib.rs` `domain::query`) | SQLite FTS5 over user and assistant text only, redacted before storage, federated to `hosts.json` peers (`chats.ts:1-18, 54-65, 226-231, 264-280`) |
| **Resume** | Materialise `VIEW`, rewrite identity keys line by line into the target runtime's own format, mint a new UUID so the original is never overwritten; crossing runtimes goes through a lossy common format; Cursor is refused because writing its transcript does nothing (`agit:src/domain/install/mod.rs:1-60`) | Claude: rebuild the version and rewrite `"sessionId"` to a new id derived from the session and version hash, beside the original, then `claude --resume <new id>` (`sessions.ts:476-521`). Codex: resume by uuid only; a deleted Codex rollout is refused with 410 (`sessions.ts:533-564`, refusal at `sessions.ts:545-546`) |
| **Cross-machine** | Push to the hosted hub; clone from it; the RC daemon reaches machines over WebSocket, SSH or a cloud relay | The always-on machine pulls each peer's new versions every ten minutes over the tailnet, using a **mirror token** that opens only the list, the index and redacted chunks (`sessions.ts:36-45, 305-327, 331-379`) |
| **Account / telemetry** | Login required to record; official-hub usage statistics mandatory, `DO_NOT_TRACK` ignored there (`agit:docs/telemetry.md:8-22`) | No account (`PRODUCT.md:441`); one optional anonymous daily heartbeat, off with `MESHD_TELEMETRY=off` (`AGENTS.md`, Design principle 2) |

---

## How it is built

### Crate layout

`agit:Cargo.toml:1-4` is a Cargo workspace with four members. A *crate* is Rust's unit of
compilation and packaging, roughly one npm package.

| Crate | Path | Job |
|---|---|---|
| `agit` | `agit:src/` | The CLI binary and the library the hub backend also links (`agit:Cargo.toml:30-51`) |
| `agit-tunnel` | `agit:crates/agit-tunnel/` | A worker **process** that holds one connection and moves packets; the parent talks to it over private stdin/stdout pipes with versioned `Open`/`Connected` records; credentials go in the opening record, never in process arguments (`agit:crates/agit-tunnel/README.md:3-12, 27-29`) |
| `agit-controller` | `agit:crates/agit-controller/` | Owns outbound daemon peers and request correlation; builds `agitd-controller`, a "private stdio process for Web adapters" (`agit:crates/agit-controller/README.md:3-11, 37-40`) |
| `agit-peer` | `agit:crates/agit-peer/` | Peer protocol and client, with optional `tunnel` and `cloud-client` features (`agit:crates/agit-peer/Cargo.toml:1-14`) |

### Layers inside the main crate

`agit:src/lib.rs:40-66` states the rule:

```
commands/  parse arguments → call domain → hand to ui
domain/    business logic, no printing, reusable by non-CLI callers
adapter/   each runtime's on-disk format → one common format (IR)
ui/        terminal rendering
hub/       HTTP client + authenticated git subprocesses (cuts across)
```

The hub's web backend links only `adapter` and `domain` by turning features off, so "the web
transcript and `agit show` come from the same source word for word" and there is never a second
parser (`agit:Cargo.toml:58-72`, `agit:src/lib.rs:59-66`). Heavy parts are behind Cargo
features: `cli` (TUI, clap, HTTP), `rc` (tokio, WebSocket, pty), `secret-vault` (OS keyring,
AES-GCM) (`agit:Cargo.toml:53-120`). Every runtime implements one `Adapter` trait
(`agit:src/adapter/mod.rs:541`, lookup at `:798`).

### Packaging a Rust binary through npm

- The main package `@einsia/agent-git` lists five platform packages as
  `optionalDependencies` (`agit:package.json`). Each platform package declares `os` and `cpu`,
  so npm installs only the matching one (`agit:npm/platforms/darwin-arm64/package.json`).
- `agit:npm/shim.js` is the `agit` command. It finds the binary in a fixed order: the
  `AGIT_BINARY` override, a hand-placed `bin/agit`, then the platform package
  (`agit:npm/lib/resolve.js:7-42`), and forwards argv, stdio and exit code unchanged
  (`agit:npm/lib/run.js:9-48`). With no binary for the platform it exits 127 with a
  build-from-source recipe (`agit:npm/lib/run.js:22-38`).
- Under Rosetta it installs the arm64 package, not x64 (`agit:npm/lib/platform.js:35-44`).
- Linux binaries are musl static builds made with `cargo zigbuild`, so there is no glibc floor,
  and the release job fails if a glibc symbol slipped in (`agit:.github/workflows/release.yml:93-113, 139-140, 168-171`;
  reason also at `agit:npm/lib/platform.js:11-13`).
- One version source: `agit:scripts/check-version.js` fails CI when `Cargo.toml` and the npm
  manifests disagree, because the download URL and the artifact name come from different files.
- The `postinstall` hook runs `agit setup` (`agit:package.json` `scripts.postinstall`), which per
  the README "wires skills/hooks/MCP". `agit:docs/02_session_store.md:31-33` says agit "installs
  no hooks". The two documents disagree; which is current is unverified.

---

## Security and audit model

- **Two redaction layers, two purposes.** `domain::secrets` is a *gate*: gitleaks rules
  (vendored as `agit:src/domain/secrets/gitleaks.toml`) stop a push. `domain::redact` is a
  *rewrite*: secrets become `[redacted:<rule>]`, and usernames, home paths, hostnames and public
  IPs become stable stand-ins numbered by first appearance, so re-redacting a grown transcript
  leaves the old prefix byte-identical (`agit:src/domain/redact.rs:1-45`). Private IP ranges and
  email addresses are deliberately left alone (`agit:src/domain/redact.rs:33-45`).
- **Scan at the moment content leaves the machine,** not at commit: commit is local, push is the
  gate, and the server scans again when content becomes readable by a third party, by ref
  difference across every ref (`agit:docs/02_session_store.md:668-695`). This matches our rule
  that redaction happens on the machine that wrote the transcript (`sessions.ts:44-45`).
- **User-registered secrets** (short passphrases no regex can recognise) live in an encrypted
  vault keyed from the OS keychain and are matched with one Aho-Corasick automaton, linear in
  input size (`agit:docs/05_global_secret_filter.md:1-54, 131-146`).
- **Streaming redaction holds back a tail.** A streamed delta can cut a secret across chunks, so
  each stream keeps at least *longest-pattern − 1* bytes unsent until every match that could
  start there is decided (`agit:docs/05_global_secret_filter.md:198-208`). If the vault exists
  but cannot be unlocked, outbound paths fail closed (`agit:docs/05_global_secret_filter.md:231-233`).
- **Tokens never in argv or git config.** Git auth goes through `GIT_CONFIG_COUNT` environment
  variables visible only to that one subprocess (`agit:docs/02_session_store.md:644-666`).
- **State permissions.** State directories 0700, lock files 0600, and authority files must be
  owned by the user with no group/other write (`agit:docs/state-permissions.md:1-38`). Ours
  uses the same modes (`sessions.ts:10, 74-78, 145-147`).
- **Audit trail.** Every version is a signed-author git commit plus an immutable tag, so the
  history is inspectable with plain git (`agit:docs/02_session_store.md:172-195, 459-463`).
  Ours is `index.json` with a sha256 per version (`sessions.ts:181-194`) and no author field;
  the machine is the author.
- **Telemetry.** Mandatory for the official hub; `AGIT_TELEMETRY_DISABLED` and `DO_NOT_TRACK`
  are ignored there; sent to PostHog (`agit:docs/telemetry.md:8-22, 144-160`). A daily
  update check prints to stderr (`agit:README.md`).

**Comparison with ours.** Our redactor is pure regex plus exact-match known secrets
(`install/payload/meshd/redact.ts:10-20, 45-66, 93`), and the ledger records only kind and a
6-hex fingerprint (`redact.ts:11-14`). One gap agit's design exposes, found by reading and not
reproduced against a running daemon: the pty stream redacts each chunk on its own
(`install/payload/meshd/pty.ts:73-84`), although its header says "redacted line-wise"
(`pty.ts:13`). A token printed across two pty chunks would reach the phone unredacted. The
mirror path is safe from this because it batches on newlines (`sessions.ts:284-294`). No
existing check covers a split secret (`scripts/check-redact.sh`, `scripts/check-pty-route.sh`;
see `docs/agents/CHECKS.md:91, 93`).

---

## What to borrow

| Pattern | Where it would live in our repo | Effort | Why |
|---|---|---|---|
| Streaming redaction with a held-back tail (`agit:docs/05_global_secret_filter.md:198-208`) | A `createStreamRedactor()` next to `createLineRedactor()` in `install/payload/meshd/redact.ts:153`; used by `pty.ts:73-84`; proven by a new `scripts/check-redact-stream.sh` | S | Closes the split-chunk gap above. "Nothing leaves the machine unredacted" is a top rule (`PRODUCT.md:459`) |
| One transcript reader for every consumer (`agit:src/lib.rs:59-66`, `agit:src/adapter/mod.rs:541`) | A new `install/payload/meshd/transcript.ts` that turns Claude/Codex lines into `{role, text, ts, meta}` once; `chat.ts`, `chats.ts`, `sessions.ts` and `handoff.ts` call it | M | Today four modules parse the same JSONL separately (`chat.ts:145, 197`; `chats.ts:91, 110-111`; `sessions.ts:93-117`; `handoff.ts:158`). agit's own reasoning: two parsers drift silently. A new runtime (OpenCode) would then be one adapter, not four edits |
| Codex restore, including its index row (`agit:src/domain/install/mod.rs`, `agit:src/adapter/codex_index.rs:9-41`) | `restoreCodex()` in `sessions.ts`, replacing the 410 at `sessions.ts:545-546` | M | Today a Codex rollout the runtime deleted cannot be resumed. agit notes Codex also indexes sessions in a `threads` table in `~/.codex/state_<N>.sqlite`; whether `codex resume <uuid>` needs that row is unverified and must be tested first |
| Credentials in the opening record or env, never argv (`agit:crates/agit-tunnel/README.md:29`, `agit:docs/02_session_store.md:644-666`) | A rule line in `AGENTS.md` (human-owned; propose, do not edit) and any future sidecar protocol | S | `ps` shows argv to every local user. Whether any of our spawns pass a token in argv today: unverified |
| One version source with a check (`agit:scripts/check-version.js`) | A new `scripts/check-*` that a future sidecar's version and protocol number agree with `server.ts`'s `VERSION` | S | Only needed once a second artifact ships; an old daemon answers 200 with an old shape (`AGENTS.md` rule 6) |
| Per-platform prebuilt binary with musl static Linux (`agit:.github/workflows/release.yml:93-171`) | The `mesh-install` release tarball, selected by the arch detection already at `install/install.sh:700-702` | M | Only if we ship a compiled helper. Pi and Jetson are Linux arm64; musl avoids a glibc mismatch on older distros |
| Deterministic stand-ins for paths/usernames (`agit:src/domain/redact.rs:1-30`) | `redact.ts`, used only on a path that sends a transcript to *another person* | M | Not needed for our own-machines mirror. Only relevant if session sharing with other people is ever wanted (open question 2) |
| Content-addressed dedupe across compaction (`agit:docs/02_session_store.md:329-360`) | `sessions.ts` base writer | L | Only if disk use is measured as a problem. First day on the Jetson was 1.3 GB for 234 sessions (`docs/factory/runs/2026-09-23T070000Z-session-snapshots.md`, "Live fleet"); how much of that is duplicated bases is unmeasured |

### Rust next to our Bun daemon: the options

This answers "how do we bring TypeScript and Rust features together and keep modules
compatible". Our daemon is one Bun process the phone depends on, and the roadmap commits to
"dependency-light Bun + TypeScript" (`ROADMAP.md:20`). We already run one native helper as a
separate process: `mesh-input`, compiled on the user's Mac with `swiftc` and spoken to over
stdin (`install/payload/meshd/input.ts:83-107`, `CONTEXT.md` shape section).

| Option | How it works | Good | Bad for us |
|---|---|---|---|
| **Sidecar binary** (agit-tunnel, agitd-controller, our mesh-input) | Separate program; meshd spawns it and exchanges newline-delimited JSON over stdin/stdout | A crash kills the helper, not meshd; any language; testable alone; matches an existing pattern | A per-platform build and release step; a process to supervise |
| **WebAssembly module** | Rust compiled to one `.wasm` file that meshd loads in-process | One file for every platform, no release matrix; memory-isolated; a fault is a JS exception | No direct file, network or OS access; only fits pure computation. Not tried in this repo |
| **N-API addon** (e.g. napi-rs) | A native `.node` library loaded into meshd | Fast calls | A native fault takes down meshd; one build per platform anyway; Bun's Node-API compatibility would need checking (unverified) |
| **`bun:ffi`** | meshd `dlopen`s a Rust `cdylib` | No build glue | Same crash risk as N-API; Bun documents `bun:ffi` as experimental (from Bun's documentation, not verified in this session) |

**Recommendation.**

1. **Now: no Rust.** The measured hot paths are already fine in TypeScript: a 139 MB transcript
   base in 1.6 s, an append in 65 ms, meshd peak 105 MB RSS after streaming
   (`docs/factory/runs/2026-09-23T070000Z-session-snapshots.md`, "Proof" and "Live fleet").
   Adding a toolchain and a release matrix for no measured need is cost without return.
2. **When a pure computation is measured slow** (redaction or parsing over large transcripts):
   a Rust crate compiled to WebAssembly and shipped as one file in the payload. No per-platform
   release, no crash risk to meshd.
3. **When a helper needs the OS, long-lived state or its own crash domain:** a sidecar binary,
   the `mesh-input` pattern. Keep it off anything macOS permission-gated unless it must be,
   because Accessibility trust is per binary (`CONTEXT.md:77`).
4. **Never** N-API or `bun:ffi` inside meshd: one bad pointer and every phone loses the machine.

**How to split modules and keep them compatible,** copied from agit's shape:

- A pure core crate (agit's `adapter` + `domain`, `agit:src/lib.rs:40-66`) with no printing and
  no network, and a thin binary crate around it for the stdio protocol. Put them in one Cargo
  workspace under a single new top-level folder, not inside `install/payload/meshd/` (rule 4 in
  `AGENTS.md`: the daemon has one copy).
- The wire contract is a checked-in JSON schema that both sides test against (agit does this for
  its CLI output: `agit:docs/cli-json-schema.md`, `agit:docs/cli-json-schema-v2.json`).
- The first record is a handshake carrying a protocol number (agit-tunnel's `Open`/`Connected`,
  `agit:crates/agit-tunnel/README.md:7-9`); meshd refuses a helper whose number it does not know
  and reports it in `/doctor`.
- The daemon advertises the feature as a capability string in `/health`, and clients gate on it,
  never on a version (`PRODUCT.md` §11 rule 2).
- One version source, checked by a script (the `check-version.js` pattern).

---

## What not to copy and why

- **License.** `agit:LICENSE` is the **MIT License**, "Copyright (c) 2026 Einsia". Bundling,
  copying and adapting are allowed provided the copyright and permission notice travel with the
  copied portion. The vendored `agit:src/domain/secrets/gitleaks.toml` comes from the gitleaks
  project (its header names the source); gitleaks's own license terms were not checked here and
  would apply to that file.
- **The hosted hub, accounts and sign-in to record a version** (`agit:docs/02_session_store.md:6-30`).
  Our non-goals are a cloud relay and an account system (`ROADMAP.md:114-118`, `PRODUCT.md:437-441`).
- **Mandatory telemetry** (`agit:docs/telemetry.md:8-22`). Ours is optional, one anonymous
  heartbeat, and `web/privacy.html` is a public promise (`AGENTS.md`, Design principle 2).
- **The cloud relay transport for the RC daemon** (`agit:docs/rfc-rc-cloud-relay.md`). Same
  non-goal.
- **git as the storage engine.** Our run record already weighed it: a 139 MB append-only file
  becomes a new blob every commit until a gc
  (`docs/factory/runs/2026-09-23T070000Z-session-snapshots.md`, "Slice B"). agit avoids that by
  storing one file per line event, which is a much larger design than we need.
- **Explicit adoption.** agit's premise is "only the few sessions the user picks"
  (`agit:src/lib.rs:8-16`). Ours is "no conversation is lost" without the user doing anything;
  that is the reason `sessions.ts` exists (`sessions.ts:1-8`).
- **Scale of the codebase.** 283k lines of Rust with a TUI, merge transactions, lineage and
  branch models. Our roadmap wants the daemon "reviewable in one sitting" (`ROADMAP.md:20`).
- **npm as the distribution channel.** Our install contract says no global npm
  (`PRODUCT.md:91`); the equivalent for us is the `mesh-install` release tarball.
- **The retired name.** `lesearch` was already our Rust control plane and is reserved, not to be
  reused (`PRODUCT.md:75`). Any new crate needs a new name.

---

## The first block

**Streaming redaction for the pty.** Add `createStreamRedactor()` to
`install/payload/meshd/redact.ts`: it keeps the trailing run of non-whitespace characters of
each chunk unsent (every rule's secret is whitespace-free except the private key, which the
existing BEGIN/END logic at `redact.ts:153-167` handles, and `Bearer ` keeps its context), emits
the rest redacted, and flushes the held tail after a short idle timer so a shell prompt without
a newline still appears. Then in `install/payload/meshd/pty.ts:73-84` replace the per-chunk
`redact(text)` with that stream redactor, one per connection, flushed on close. Two files
change, about thirty lines. The proof is a new `scripts/check-redact-stream.sh` that feeds a
fixture token for each rule split at every byte offset through the stream redactor and fails if
the raw token appears in the joined output, and also checks a prompt with no newline is flushed.
The existing `scripts/check-redact.sh` and `scripts/check-pty-route.sh` must stay green, and per
`AGENTS.md` rule 1 it is run once against a side-port daemon
(`MESHD_PORT=8898 … bun run install/payload/meshd/server.ts`) with `printf` splitting a fixture
token across two writes in a pane. Whether the split actually happens in live `Bun.Terminal`
output is unverified; the check proves the redactor, the side-port run proves the route.

---

## Open questions for Arya

1. **Rust: which feature did you have in mind?** My recommendation is no Rust until something
   is measured slow. If there is a specific thing you want in Rust (a feature, a learning goal, a
   faster tool), name it and I will say which option above fits.
2. **Sharing sessions with other people.** agit's core is handing a conversation to a teammate.
   Ours only mirrors between your own machines. Is sharing with others ever in scope? If yes, it
   needs path/username stand-ins and a way to share without a server of ours in the path.
3. **Codex restore.** A Codex conversation the Codex CLI already deleted cannot be resumed today
   (`sessions.ts:545-546`). Worth building now, or wait until someone asks, as the run record
   says?
4. **Disk budget on the Jetson.** The mirror was 1.3 GB after its first day. Do you want a
   retention limit (for example keep everything for 90 days, then only the latest version), or
   keep everything forever?
5. **More runtimes.** agit reads OpenCode and Cursor too. Do you use either daily enough that
   `mesh sessions` should keep them?
