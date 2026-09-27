# Reference review: security-audit-skill (Cloudflare)

Reviewed 2026-09-27 against this repo at `88a1332` (branch `sdlc/ai-native-playbook`).
Clone: `references/external/repos/security-audit-skill` (gitignored by `.gitignore:53`),
upstream `https://github.com/cloudflare/security-audit-skill`, commit `c1c8a8c`
(2026-09-14, "Clarify guidance and full audit modes"). Nothing in the clone was executed.
Paths below that start with `skills/` or `README.md` are inside the clone; every other
path is in this repo.

## For Arya

This is a free, MIT-licensed "security auditor" instruction set from Cloudflare that any
of our coding agents (Claude Code, Codex, Cursor) can follow to look for real security
holes in our code, then prove or disprove each one with a second, independent agent. It
leaves a written record of what was checked, what was found, and what was ruled out.
Every audit can be re-run later and picks up where the last one stopped, which is the
auditability you asked for. We can put it into this repo as-is (the license allows that
as long as we keep Cloudflare's license file). Two things need your decision first. This
repository is **public** (GitHub reports `aryateja2106/lecoder-watch` as PUBLIC), so the
audit's results must stay on your Mac, not in git, until each problem is fixed. And the
first run can only read code; to let it safely *run* our daemon, we need a locked-down
test box, and Docker Desktop is installed on this Mac but not running. The first step
costs no product code: install the skill, add one check that proves it is intact, then
run one read-only audit of the daemon, installer and terminal bridges.

## What it is

A coding-agent skill (`skills/security-audit/SKILL.md:1-4`, name `security-audit`) with
two modes (`SKILL.md:10-17`):

- **Guidance mode** (the default): answer security questions or review one area. It
  writes no files.
- **Full audit mode**: six phases, run only when someone explicitly asks for an audit
  (`SKILL.md:168-179`, `README.md:9-16`):
  1. Reconnaissance: map the code, trust boundaries and entry points, and write a
     coverage ledger.
  2. Coverage-led hunting: one agent per ledger unit, then "coverage critics" that look
     for gaps.
  3. Candidate validation: a fresh agent tries to refute every candidate.
  4. Structured output: `findings.json`, checked against `report-schema.json`.
  5. Record verification: a fresh agent checks each final record again.
  6. Reports: `REPORT.md`, `FINDINGS-DETAIL.md`, `NEEDS-VALIDATION.md`.

It is agent-neutral. "Parent", "`research` agent" and "`general` agent" are roles, not
product names (`SKILL.md:19-29`).

## How it is built

| Path in clone | Lines | Role |
|---|---|---|
| `skills/security-audit/SKILL.md` | 192 | Modes, execution safety, setup, write isolation, profiles (`quick`/`standard`/`deep`), budget, severity anchors, anti-patterns |
| `skills/security-audit/RECONNAISSANCE.md` | 156 | Phase 1: four parallel recon prompts (1a–1d, lines 9-55), prior-run input (59-71), `architecture.md` cap (75-88), the deterministic ledger (90-156) |
| `skills/security-audit/HUNTING.md` | 251 | Phase 2: required hunter prompt parts (11-25), hunting method (27-97), candidate gate (138-157), structured hunter result (168-213), critic waves (221-251) |
| `skills/security-audit/VALIDATION-AND-REPORTING.md` | 186 | Phases 3–6: candidate verifier prompt (9-46), `findings.json` contract (95-118), fresh-eyes verification (120-149), reports (151-186) |
| `skills/security-audit/ATTACK-CLASSES.md` | 130 | Core classes (injection, access control, files, crypto, business logic, feature abuse, chains), Wildcard (92-109), Obvious things (111-130), and which companion file to use (9-27) |
| 10 companion files (`WEB-PROTOCOL-AND-AUTH.md`, `DESKTOP-MOBILE-AND-LOCAL-IPC.md`, `SUPPLY-CHAIN-AND-RELEASE.md`, `AI-AND-LLM.md`, `RESOURCE-EXHAUSTION-AND-AVAILABILITY.md`, `CLIENT-SIDE.md`, `DATA-ISOLATION-AND-LIFECYCLE.md`, `PROTOCOLS-RPC-AND-MESSAGING.md`, `CLOUD-AND-DEPLOYMENT.md`, `MEMORY-SAFETY-AND-BINARY.md`) | 73–105 each | Each one has the same parts: "When to use this file", "Core discipline", the attack classes, "Universal moves" and "Validation rules" |
| `skills/security-audit/report-schema.json` | 461 | JSON schema for the three verdicts `confirmed`, `needs_validation` and `rejected` |
| `skills/security-audit/validate-findings.cjs`, `validate-coverage-ledger.cjs` | 773, 872 | Validators with no dependencies. They use only Node's `fs`, `path` and `util` (`validate-findings.cjs:11-13`, `validate-coverage-ledger.cjs:8-10`) |
| `*.test.cjs` | 652, 740 | Validator tests on `node:test` (`validate-findings.test.cjs:6`). Run with `node --test` (not run by this review) |

Requirements (`README.md:86-90`): an agent that can run parallel subagents, Node for the
validators, and an OS-enforced sandbox for any execution of target code.

## Security and audit model

- **Only boundary failures count.** Each candidate must name a lower-trust principal,
  the accepted input, the control that should have stopped it, the boundary crossed, and
  a concrete result (`SKILL.md:138-140`). A missing best practice is a hardening note,
  not a finding (`HUNTING.md:151-152`).
- **Three verdicts** (`README.md:20`, `VALIDATION-AND-REPORTING.md:103-107`):
  - `confirmed` has a full source trace plus an observed local result, and a severity.
  - `needs_validation` names the exact unknown fact and a safe way to check it. It has
    no severity.
  - `rejected` is kept, so later runs do not re-argue the same claim.
- **Adversarial validation.** The agent that finds a candidate never validates it
  (`VALIDATION-AND-REPORTING.md:5`, `:12`). A record that is promoted or materially
  changed goes to yet another fresh verifier (`:145`).
- **The ledger is the coverage claim.** A prose line such as "auth reviewed" is not
  evidence (`RECONNAISSANCE.md:154`). Each unit is keyed by surface, boundary,
  subsystem and attack class, with a deterministic ID (`RECONNAISSANCE.md:96-102`).
  Units move through a strict state table (`:141-150`).
- **Runs are additive.** Earlier ledgers and findings are read, changed code is
  re-checked, and unchanged confirmed findings are carried forward
  (`SKILL.md:92-105`). The authors found that one run finds about half of what repeated
  runs find (`README.md:98`).
- **Execution safety.** Target code runs only in a sandbox with all of these controls
  (`SKILL.md:31-40`):
  - no external network;
  - an empty, allowlisted environment;
  - a read-only target and toolchain;
  - writes allowed only to scratch;
  - CPU, memory, process, file-size, disk and wall-clock limits.

  If any control is missing, nothing runs, and the lead stays `needs_validation`
  (`SKILL.md:40`). Evidence files move from scratch into `artifacts/` only through an
  11-step, race-safe copy that trusted parent code performs (`SKILL.md:68-81`).
- **Output lives outside the target by default**, in
  `~/security-audit-skill/<repo>/run-<N>` (`SKILL.md:51`, `README.md:84`).
- **Severity anchors** run from critical to informational (`SKILL.md:154-162`).
  Severity can never exceed the impact that was actually demonstrated.

## Installing it here

**Where the files go.** In this repo, `.claude/skills/<name>/` holds real, tracked
directories (for example, `git ls-files` lists
`.claude/skills/security-and-hardening/SKILL.md`). `.cursor/skills/<name>` entries are
symlinks to `../../.claude/skills/<name>`; `.cursor/skills/api-and-interface-design`
was checked. `.agents/skills/*` is gitignored except `factory-*` (`.gitignore:46-50`).
So:

1. Copy `skills/security-audit/*` (20 files) and the root `LICENSE` from the clone,
   unmodified, into `.claude/skills/security-audit/`. Keeping them pristine means an
   upstream update is a clean diff.
2. Put everything adapted to this repo in **one extra file**,
   `.claude/skills/security-audit/MESH.md`. It holds the recon seeds, the principals and
   the priority units below, plus these rules:
   - output only under `~/security-audit-skill/lecoder-watch/run-<N>`;
   - never `curl :8899`;
   - at most 5 concurrent agents.

   The 5-agent cap comes from past sessions: 8–13 concurrent workflow agents hit the
   session limit.
3. `ln -s ../../.claude/skills/security-audit .cursor/skills/security-audit` (tracked,
   like its siblings).
4. For Codex, create `.agents/skills/security-audit` as a symlink to the same folder. It
   stays per-machine because of `.gitignore:49`. Tracking it needs a
   `!.agents/skills/security-audit` line, which is an Open question below.

Do not use the upstream `npx skills add` install (`README.md:51-66`). It fetches from
the network at install time and does not pin a version.

### Recon prompts, adapted to this codebase

Give each recon agent its upstream prompt verbatim (`RECONNAISSANCE.md:9-55`), plus these
starting files. `docs/agents/CONTRACTS.md` is a generated index. Agents may use it to
find routes, but must re-read the source line it cites.

- **1a Product and stack.** Start with `AGENTS.md`, `CONTEXT.md`,
  `docs/product/PRODUCT.md` (§1–§6 and §10) and `docs/agents/CODEMAP.md`. The code comes
  in three runtimes:
  - Bun/TypeScript: `install/payload/meshd/` and `install/payload/rmux-bridge/src/server.ts`.
  - Swift: `iOS/`, `Watch/`, `Shared/`, `MeshDesktop/` and
    `install/payload/bin/mesh-input.swift`.
  - POSIX sh: `install/install.sh` and `install/payload/bin/mesh`.

  Commands to mark **prohibited** during the audit:
  - `xcodebuild`;
  - `bun add` (it fetches packages; `AGENTS.md:146`);
  - `scripts/check-fleet.sh` (it touches every machine in `~/.mesh/hosts.json`);
  - `scripts/release-mesh-install.sh` and `scripts/serve-installer.sh`;
  - anything that talks to the owner's live daemon on :8899 (`AGENTS.md:52-58`).
- **1b Principals.** Seed these; the upstream prompt asks for exactly this list.
  - **Owner / token holder.** Full shell by design: `install/payload/meshd/auth.ts`
    describes itself as the only gate "between a request and RCE" (`CODEMAP.md:126`).
    Fail-closed at `auth.ts:21-25`. Paired phone and watch hold the same token
    (`pair.ts:126-128`).
  - **Mirror-token peer.** A second credential scoped to session reads
    (`sessions.ts:305-327`).
  - **Unauthenticated tailnet or LAN peer.** The daemon binds `0.0.0.0` by default
    (`server.ts:28`). The rmux bridge does too (`rmux-bridge/src/server.ts:44`).
  - **Any local process, including another Unix user or a `--user` sandboxed agent**
    (`install.sh:42-44`). The loopback exemption is on by default
    (`loopback-trust.ts:23-39`, `PRODUCT.md:184`).
  - **A browser page on the Mac.** Guarded at `server.ts:1196-1212`.
  - **Content of an agent-built web app, served token-free from the daemon's own
    origin.** See `apps.ts:4-5` and `server.ts:1343-1349`.
  - **Text an AI agent prints.** It reaches notifications, and "Approve" presses Enter
    (`Shared/AgentNotifications.swift:47-63`).
  - **Whoever controls the install payload URL** (`install.sh:474-482`).
- **1c Entry surfaces.** Start from the route table in `docs/agents/CONTRACTS.md:9-90`.
  The unauthenticated routes are `/health`, `/pair/new`, `/pair/claim` and `/a/*`, and
  the dispatch order is at `server.ts:1333-1363`. Then cover the surfaces the table does
  not show:
  - the pty WebSocket (`server.ts:1366`, `pty.ts:59`);
  - `cmux-bridge.ts` `/cmux`, which runs `cmux` with caller-supplied arguments on
    loopback without a token (`cmux-bridge.ts:5`, `:39-52`);
  - the rmux bridge token and cookie check (`rmux-bridge/src/server.ts:223-225`);
  - the pairing deep link `meshwatch://pair` (`PRODUCT.md:144`, `qr.ts`);
  - the watch-to-phone commands (`CONTRACTS.md:131-156`);
  - agent hook input (`install/payload/bin/mesh-hook` → `POST /events`);
  - transcript files read by `chat.ts`, `sessions.ts` and `chats.ts`;
  - `HANDOFF.md`, written into a working directory and then pointed at by a typed
    instruction (`handoff.ts:35`, `:224`);
  - the file routes (`files.ts:113-185`).
- **1d Local execution.** These fixtures already exist, and all would need to run
  inside the sandbox below:
  - `bun loopback-trust.ts --check` (`loopback-trust.ts:41-42`);
  - `scripts/check-mesh-csrf.sh`, which boots a daemon on a throwaway `HOME` over
    loopback (`check-mesh-csrf.sh:18-21`);
  - `check-pair-auth.sh`, `check-bridge-auth.sh`, `check-mesh-auth.sh` and
    `check-redact.sh`.

  Swift, TCC, Keychain and watch behaviour cannot run in a sandbox here, so they stay
  source-only or become `needs_validation` handed to Arya (AGENTS.md "What an agent
  cannot verify").

### Priority ledger seeds: hypotheses, not findings

None of these has been validated. They are places where the source shows a boundary that
a first run should settle, one way or the other.

| # | Hypothesis to settle | Source | Companion class |
|---|---|---|---|
| 1 | Can a `--user` sandboxed agent, or another local user, reach the owner's daemon through the default loopback exemption, with no token? | `loopback-trust.ts:23-39`, `install.sh:42-44` | LOCAL-IPC "IPC peer-authentication gaps" |
| 2 | An agent-built web app is served from the daemon's origin with no CSP (`apps.ts:217`). The Origin guard assumes "A page can only carry THIS origin if meshd served it" (`server.ts:1204-1206`). Can such a page, opened at `127.0.0.1:8899`, call token routes? | `apps.ts:4-5,217`, `server.ts:1196-1212,1346` | CLIENT-SIDE; ATTACK-CLASSES "Chained vulnerabilities" |
| 3 | The cmux bridge runs `cmux` with arbitrary arguments for any loopback caller that is not a browser | `cmux-bridge.ts:5,21,41-52` | LOCAL-IPC "IPC peer-authentication gaps" |
| 4 | The install payload is downloaded over HTTPS (`install.sh:475`) and extracted with no checksum or signature check. A text search of `install.sh` for sha256, shasum, checksum, signature, gpg and minisign found none; the file has 815 non-empty lines, so it is not being skipped. | `install.sh:474-482` | SUPPLY-CHAIN "Update metadata and rollback confusion" |
| 5 | One pairing claim returns every fleet token (`pair.ts:18`, `:126-128`). Five wrong guesses burn the code (`pair.ts:31`, `:117`) | `pair.ts` | WEB "API-key exposure"; LOCAL-IPC "App and account handoff confusion" |
| 6 | Does the mirror token open only list, index and chunk? | `sessions.ts:321-327` | WEB "API-key scope and resource binding" |
| 7 | "Approve" presses Enter on whatever option is highlighted *now*, not on what the notification showed | `AgentNotifications.swift:47-63` | AI "Action-confirmation and approval binding"; LOCAL-IPC "Pending-action and user-presence confusion" |
| 8 | Does redaction cover every outbound path, including the pty byte stream? | `PRODUCT.md:151,154`, `redact.ts` | AI "Sensitive context extraction"; DATA-ISOLATION |

## Which attack-class files apply

The companion files are chosen per boundary (`RECONNAISSANCE.md:88`). Our non-goals
(`PRODUCT.md:435-443`) remove whole families: no cloud relay, no account system for
access, text-only brain.

| File | Select? | Why, in this codebase |
|---|---|---|
| `WEB-PROTOCOL-AND-AUTH.md` | **Yes** | See below |
| `DESKTOP-MOBILE-AND-LOCAL-IPC.md` | **Yes, core** | See below |
| `SUPPLY-CHAIN-AND-RELEASE.md` | **Yes** | See below |
| `AI-AND-LLM.md` | **Yes, partial** | See below |
| `RESOURCE-EXHAUSTION-AND-AVAILABILITY.md` | **Selective** | See below |
| `CLIENT-SIDE.md` | Yes | Browser surfaces: `desktop.html`, `files.html`, the rmux-bridge xterm page, and agent-built web apps (seed 2) |
| `DATA-ISOLATION-AND-LIFECYCLE.md` | Yes | Session mirror copies, exposures, restore (`PRODUCT.md:152`), and whether `mesh uninstall` really deletes everything (`AGENTS.md:211-212`) |
| `PROTOCOLS-RPC-AND-MESSAGING.md` | Partial | The pty WebSocket framing (`PRODUCT.md:151`) and watch-to-phone commands (`CONTRACTS.md:133`) |
| `CLOUD-AND-DEPLOYMENT.md` | Narrow | Only telemetry's Supabase call (`telemetry.ts:22-23`, `:103`). A publishable key is not a secret, but whether row-level security exists is not in the repo, so that is `needs_validation`. Skip the rest: no cloud relay |
| `MEMORY-SAFETY-AND-BINARY.md` | No (for now) | No C/C++ or unsafe parsers found in `CODEMAP.md`. `mesh-input.swift` is Swift; revisit if that changes |

**`WEB-PROTOCOL-AND-AUTH.md`.** The daemon is a custom HTTP server that uses:

- bearer tokens compared in constant time (`auth.ts:8-25`);
- a Host guard (`server.ts:1260`, `:1333`);
- an Origin and Sec-Fetch-Site guard (`server.ts:1196-1212`);
- short-lived codes as credentials (`pair.ts:30-31`);
- a scoped second token (`sessions.ts:321`);
- a key in the URL path (`apps.ts:4-5`);
- a token cookie on the bridge (`rmux-bridge/src/server.ts:225`).

Use the classes "Host and forwarded-header trust", "API-key scope", "API-key exposure"
and "Cookie scope". Exclude JWT, OAuth/OIDC, SAML, MFA and WebAuthn: there is no account
system (`PRODUCT.md:441`), and APNs JWTs are only *signed* by the daemon (`push.ts`),
never verified.

**`DESKTOP-MOBILE-AND-LOCAL-IPC.md`.** Its "When to use" text names local daemons,
deep links, helpers and local IPC. This product is all of those:

- two loopback listeners, one with no token;
- the loopback exemption;
- `--user` agent sandboxes;
- `mesh-input` with the Accessibility grant (`CONTEXT.md:43-44`);
- the `meshwatch://` deep link;
- notification actions;
- Keychain storage (`SecureStore.swift:32`, `AfterFirstUnlockThisDeviceOnly`);
- files under `~/.mesh` with 0600 permissions.

**`SUPPLY-CHAIN-AND-RELEASE.md`.**

- The `curl | sh` installer and its payload download (seed 4).
- The Bun installer fetched at install time (`install.sh:131`).
- Upgrades that keep the token (`PRODUCT.md:91-92`).
- Wireless app installs (`apps.ts` manifest).
- Skills shipped into users' agents (`AGENTS.md:124`). This is the "Plugin and extension
  trust expansion" class.

**`AI-AND-LLM.md`.** The product relays AI agents. Approve binding (seed 7), `HANDOFF.md`
written and then fed to a fresh agent (`handoff.ts:35`, `:224`), transcript reading
(`chat.ts`), and redaction (seed 8) are live today.

The local-brain tool catalogue `intent/mesh-tools.json` lists 16 tools, including
`send_text`, `power`, `open_url` and `kill_session`. Today, `git grep` finds only docs
and `scripts/check-intent.sh` referring to it. No shipping code dispatches those tools,
so "tool-argument injection" and "excessive agency" become primary only when
`PRODUCT.md` §9 ships.

**`RESOURCE-EXHAUSTION-AND-AVAILABILITY.md`.** Only for lower-trust principals: the
pre-auth routes, the mirror peer, and content an agent writes. A token holder slowing
their own daemon is self-impact and is excluded (`RESOURCE-EXHAUSTION…md:12`). The class
is real here: the session-snapshot work once measured 1.36 GB RSS from whole-file reads.
That comes from the memory note; it has not been re-measured.

## How output flows into the playbook loop

The playbook puts recurring security scans in Stage 6. Each finding is validated, each
dismissal is reasoned, fixes go through the PR gate, and each fixed class becomes an eval
(PLAYBOOK 6.2).

1. **Run output stays outside git.** It goes to
   `~/security-audit-skill/lecoder-watch/run-<N>/`, which is the skill's own default
   (`SKILL.md:51`). The repo is public, so a committed `findings.json` or `REPORT.md`
   would publish unfixed holes. This also matches the base policy of keeping sensitive
   material on local disk only.
2. **`confirmed` (fix is one file):**
   - Write a new `scripts/check-sec-<slug>.sh` from the record's `execution.payloads`
     and `observed_result`. It must fail before the fix.
   - Fix the code in the same draft PR, and commit the check **together with** the fix,
     never before.
   - `scripts/check-all.sh:29` runs every `check-*.sh`, so the check becomes a
     permanent eval with no new machinery.
   - Precedents: `check-mesh-csrf.sh` (DNS rebinding) and `check-bridge-auth.sh` (the
     0.6 bridge).
3. **`confirmed` (fix touches more than one file) or `needs_validation`:**
   - Write a draft intent `intents/YYYY-MM-DD-sec-<slug>.md` with `source: security-scan`
     (the value already exists at `intents/TEMPLATE.md:4`), as `intents/README.md:55-57`
     requires.
   - Describe the outcome only ("a sandboxed agent cannot reach the owner's daemon"),
     with no reproduction steps, until the fix ships.
   - Each `needs_validation` blocker that needs the owner goes on Arya's list. An
     example is "does the tailnet ACL allow peers to reach :8899?".
4. **`rejected`** stays in that run's `findings.json`. Its `reason` field is the reasoned
   dismissal the playbook asks for, and it stops the next run from re-arguing the claim
   (`VALIDATION-AND-REPORTING.md:101`).
5. **Cadence.**
   - After each daemon release, run a scoped audit of the diff between two source refs
     (`SKILL.md:115`).
   - Now and then, run a full `standard` pass.
   - Each run reads the previous ledger, so coverage adds up (`SKILL.md:96-105`).
6. **Severity to triage:** critical and high are fixed now, medium is scheduled, and
   `needs_validation` goes to Arya. Arya decides each one; no agent marks an intent
   `accepted` (`intents/README.md:54`).

## The sandbox requirement on this Mac

The skill needs all of these controls before it runs target code (`SKILL.md:33-38`):

- no external network;
- an empty, allowlisted environment;
- a read-only target and toolchain;
- writes only to scratch;
- CPU, memory, process, file-size, disk and wall-clock limits.

What this Mac has, measured 2026-09-27:

- `/usr/bin/sandbox-exec` (macOS Seatbelt). It can deny network and restrict writes.
- `/opt/homebrew/bin/timeout`, for wall-clock limits.
- `/usr/bin/hdiutil`. A fixed-size disk image mounted as scratch gives a disk limit.
- `env -i`, for an empty environment.
- Docker CLI at `/usr/local/bin/docker`, but its daemon is **not running**
  (`docker info` could not connect).
- No `bwrap` and no `firejail`.
- Node v26.0.0 and Bun 1.3.14.

The gap is the **memory limit**. As far as I know, macOS does not reliably enforce a
per-process memory limit (`ulimit -v`); this is unverified on this machine. Seatbelt
alone therefore does not meet the bar.

Plan:

1. **Run 1: source-only.** Execute no target code. The skill supports this directly: a
   lead that needs execution stays `needs_validation`, with the blocker
   "sandbox cannot enforce memory limit" (`SKILL.md:40`, `HUNTING.md:77-78`). Nothing
   can reach `confirmed` in this run, and the report must say so.
2. **Later runs: daemon code in Docker.** This covers the Linux-compatible, Bun-side
   code, run with:

   ```sh
   timeout 120 docker run --rm --network none --read-only --memory 512m --cpus 1 \
     --pids-limit 64 --tmpfs /scratch:size=256m -e HOME=/scratch/home \
     -v "$PWD":/target:ro <pre-pulled bun image> ...
   ```

   `--network none` still has loopback, so a daemon plus its client works. Arya chooses
   and pulls the image beforehand; the audit itself never fetches.
3. **Swift, TCC, Keychain, device paths:** stay source-only or `needs_validation` for
   Arya. This matches the charter's physical-device stop rule.
4. **Promoting evidence** into `artifacts/` needs a small trusted copy script that
   follows the 11 steps (`SKILL.md:68-81`), for example Python `os.open` with
   `O_NOFOLLOW` and `dir_fd`. Until that script exists, local evidence cannot back a
   `confirmed` record (`SKILL.md:80`). Effort: M.

### First run, command sequence

These steps assume the first block below has landed.

```sh
cd /Users/aryateja/Projects/lecoder-watch
git log -1 --date=short --format='%h %cd %s'      # AGENTS.md rule 2
git status --short                                # a dirty tree is recorded as dirty
sh scripts/check-security-audit-skill.sh          # vendored skill intact, validators' tests pass
mkdir -p ~/security-audit-skill/lecoder-watch     # the skill creates run-1 inside it
```

Then, in a fresh Claude Code session at the repo root, give this prompt:

> Full security audit of this codebase using the security-audit skill. Profile `quick`,
> scoped to `install/payload/meshd`, `install/payload/rmux-bridge`, `install/install.sh`,
> `install/payload/bin`, `Shared/SecureStore.swift`, `Shared/AgentNotifications.swift`,
> `Shared/MeshClient.swift`. Budget 20 agent invocations, at most 5 at once. Output to
> `~/security-audit-skill/lecoder-watch/run-1`. Source-only: execute no target code; this
> Mac cannot enforce a memory limit. Read `.claude/skills/security-audit/MESH.md` for recon
> seeds. Never contact :8899 or any fleet machine.

When it finishes:

```sh
R=~/security-audit-skill/lecoder-watch/run-1
node .claude/skills/security-audit/validate-findings.cjs "$R/findings.json"
node .claude/skills/security-audit/validate-coverage-ledger.cjs "$R/coverage-ledger.json"
```

Then read `REPORT.md` and triage it as described in the playbook loop above.

## What to borrow

| Pattern | Where it would live in our repo | Effort | Why |
|---|---|---|---|
| The whole skill, vendored and pinned | `.claude/skills/security-audit/` + `MESH.md` + `.cursor` symlink | S | Arya asked for auditable security; this is a finished, MIT-licensed method |
| Three verdicts; `needs_validation` has no severity | `REVIEW.md` (Stage 5, not yet written) and `.claude/agents/factory-verifier.md` wording | S | Stops "might be a problem" from being filed as a bug, or dropped |
| Candidate gate: principal, input, control, boundary, result (`SKILL.md:138-140`) | `REVIEW.md` "Do not report" | S | This is the playbook's "cap the nits" in security terms |
| Severity anchors (`SKILL.md:154-162`) | `REVIEW.md` "What Important means" | S | A shared scale for human and agent reviewers |
| Refute-it verifier prompt (`VALIDATION-AND-REPORTING.md:11-45`) | Reused inside the vendored skill; adapt for `factory-verifier` only if Arya asks | S | Same rule as CLAUDE.md rule 4 (the writer never grades) |
| A fixed class becomes a `scripts/check-sec-*` | `scripts/` (picked up by `check-all.sh:29`) | S per finding | The playbook's "each fixed class becomes an eval", with no new eval harness |
| Stable fingerprints across runs | `fingerprint:` in a security intent's front matter (a template change is Arya's call) | S | Dedupes intents across runs |
| Scoped diff audits per release (`SKILL.md:115`) | A step in the release checklist, after `release-mesh-install.sh` | M | Audits exactly what changed in the daemon |
| Trusted evidence-promotion script (`SKILL.md:68-81`) | `.claude/skills/security-audit/MESH.md` + one small script | M | Needed before anything can be `confirmed` |
| Docker sandbox profile | `MESH.md`, used from run 2 | M | Meets `SKILL.md:33-38` for Bun code |
| "Obvious things" checklist (`ATTACK-CLASSES.md:111-130`) | Covered by the vendored skill; many items already have checks (secrets, `check-mesh-csrf.sh`, `check-host-guard.sh`) | S | Cheap first pass |

## What not to copy and why

- **Do not commit run output.** The repo is public, and `findings.json`, `REPORT.md` and
  `NEEDS-VALIDATION.md` would disclose unfixed issues. The skill already defaults outside
  the target (`SKILL.md:51`).
- **Do not use `npx skills add`.** It is unpinned and fetches at install time. Vendor a
  known commit (`c1c8a8c`).
- **Do not edit the upstream files in place.** Put the adaptation in `MESH.md`, so an
  update is a copy plus a diff review.
- **Do not replace `.claude/skills/security-and-hardening`.** That skill is writing-time
  advice (Stage 2/3); this one is an audit (Stage 6). Different jobs.
- **Do not treat token-holder actions as findings.** The bearer token grants a shell by
  design (`auth.ts`; `/agents/new` runs commands). For example, "`/fs/move` can rename
  any file" (`files.ts:175-185`) is intended authority. That is anti-pattern 5
  (`SKILL.md:187`).
- **Do not select the families our non-goals remove:** OAuth, SAML, MFA and WebAuthn
  (no account system), cloud relay and IAM, and vision-model classes
  (`PRODUCT.md:435-443`). Selecting them wastes hunter budget.
- **Do not start with the `deep` profile or large fan-out.** Concurrency above about 5
  agents has hit the session limit here before.
- **Do not run target code before the sandbox exists.** Our own checks boot daemons on
  the host (`check-mesh-csrf.sh:21`). That is fine for `check-all.sh`, but it does not
  meet the skill's bar.
- **License.** The license is the **MIT License**, "Copyright (c) 2025-2026 Cloudflare,
  Inc." (`LICENSE:1-3`). Bundling, modifying and redistributing are allowed if the
  copyright and permission notice are included in all copies or substantial portions
  (`LICENSE:5-13`). So vendor `LICENSE` into `.claude/skills/security-audit/`. MIT grants
  no trademark rights, so the Cloudflare name belongs only in attribution, never in our
  product copy.

## The first block

Vendor the skill, pinned and unmodified, with one adaptation file and one new check. No
product code changes. It touches:

- `.claude/skills/security-audit/`: the 20 files from the clone's `skills/security-audit/`
  at `c1c8a8c`, plus its `LICENSE`.
- `.claude/skills/security-audit/MESH.md`: the recon seeds, principals, priority units,
  output location, the no-:8899 rule and the 5-agent cap, all from this document.
- `.cursor/skills/security-audit`: a symlink to `../../.claude/skills/security-audit`.
- A per-machine `.agents/skills/security-audit` symlink (untracked).
- A new `scripts/check-security-audit-skill.sh`. It:
  1. fails if `LICENSE` is missing or does not carry the Cloudflare copyright line;
  2. compares the sha256 of every vendored upstream file against a list pinned in the
     script, which catches local edits and partial updates;
  3. runs `node --test` on both `*.test.cjs` files, and reports MISCONFIGURED (not
     green) if `node` is absent.

`scripts/check-all.sh:29` runs the new check automatically. Run `sh scripts/codemap.sh`
afterwards so `check-codemap.sh` stays green. Prove it with
`sh scripts/check-security-audit-skill.sh` and `./.claude/scripts/gates.sh fast`, and
quote the `FACTORY_GATES:` line. The source-only run above is the next step and needs
Arya's go-ahead.

## Open questions for Arya

1. **Where do findings live until they are fixed?** Options: this Mac only
   (recommended, the skill's default), GitHub private security advisories on the public
   repo, or a private backup repo.
2. **Should security intents be committed before the fix ships?** They would be
   outcome-only and public, or they could stay local until the fix merges.
3. **Codex access:** track `.agents/skills/security-audit` by adding
   `!.agents/skills/security-audit` to `.gitignore`, or keep it a per-machine symlink?
4. **Budget and cadence:** how many agent invocations per run (20 is proposed for the
   first), and should runs follow each daemon release, happen weekly, or both?
5. **Sandbox for run 2:** may Docker Desktop be started, and which Bun image should be
   pre-pulled? Or do we stay source-only?
6. **First-run scope:** daemon, installer and bridges (proposed), or the Swift apps too?
7. **Loopback exemption:** flipping the default is already open (`PRODUCT.md:184`).
   Seeds 1 and 2 will produce evidence for or against it. Should the audit's answer
   decide it?
