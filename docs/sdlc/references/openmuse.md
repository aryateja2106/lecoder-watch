# Reference review: OpenMuse

Reviewed 2026-09-27 against our branch `sdlc/ai-native-playbook` at `88a1332` and a shallow
clone of OpenMuse at `34b15bc` (2026-09-26), kept at `references/external/repos/openmuse`.
Nothing in the clone was run. A path written as `openmuse:apps/...` is inside that clone. Every
other path is in this repo.

## For Arya

OpenMuse is a personal-agent app from the CopilotKit team. The idea most useful to us is how it
handles the moment when the agent wants to do something and a person must approve it. Every
approval or refusal is stored as a record with a timestamp. It applies only to the exact thing the
person saw, it expires after 30 minutes, and it can be used only once. Today, when you tap Allow on
your phone, our app presses Enter in the agent's terminal and writes nothing down. Afterwards nobody
can show who approved what, or when. Borrowing this idea gives us an approvals log. That is the
"auditability" story a consulting client or a team would ask about, and it matches stage 5 of the
AI-native playbook ("decisions logged"). The first step is small: one new daemon file that writes a
line each time someone answers an agent, plus a check that proves it works. We should not copy the
rest of OpenMuse. It depends on a CopilotKit cloud service, runs its own browser and Docker
computer, and is built on React Native and Postgres. Each of those conflicts with our design, which
is local-first, native and has no accounts. The license (MIT) allows us to adapt its code, but
rewriting the few patterns we want is cheaper than bringing any of its code in.

## What it is

OpenMuse is a self-hosted "personal agent" in alpha. It has a chat that delegates jobs, a durable
task list with plans and progress, and a queue of reviewed actions for Gmail and Calendar writes.
It also has a persistent Chromium browser the person can take over, and an optional locked-down
Docker Linux container with a file browser (`openmuse:README.md`, "Features" table). Each
deployment has one owner, protected by a shared access key (`openmuse:README.md:104`,
`openmuse:SECURITY.md:9`). The project calls itself alpha, and says that live Google, live models
and CopilotKit Rich Threads each need their own configuration (`openmuse:README.md`, the note
under the demo links).

## How it is built

It is a pnpm monorepo, written in TypeScript throughout (`openmuse:README.md`, "Architecture" table).

| Path | What it holds |
|---|---|
| `openmuse:apps/server/src/app.ts` | Hono API. An Origin allowlist runs first (`:47-50`). One auth middleware sets `owner` on every `/api/*` request (`:126-136`). Then come the routes, including `POST /api/actions` and `POST /api/actions/:id/decide` (`:175-188`). |
| `openmuse:apps/server/src/db.ts` | The whole persistence layer: one table, `records(owner, kind, id, data jsonb, updated_at)` (`:139`), on embedded PGlite or on Postgres (`:122-137`). Helpers for compare-and-swap (`:47-59`), insert-if-absent (`:60-70`), the atomic approval claim (`:78-90`) and restart recovery (`:91-95`). |
| `openmuse:apps/server/src/actions.ts` | Reviewed actions: propose, decide, execute, record activity (the whole file, 202 lines). |
| `openmuse:apps/server/src/auth.ts` | Access-key login, hashed session tokens, HMAC-signed short-lived URLs (80 lines). |
| `openmuse:apps/server/src/engine/worker.ts` | The task worker: lease, heartbeat, checkpoint, run-events (249 lines). |
| `openmuse:apps/server/src/engine/service.ts` | Task logic, including the `waiting_approval` and `waiting_input` states (`:240-247`, `:745-755`). |
| `openmuse:apps/server/src/computer.ts` | Docker container runner and saved command receipts: exit code, output, `interrupted` (`:15-48`, `:715-730`). |
| `openmuse:apps/server/src/agent.ts` | CopilotKit runtime wiring. The agent is built per request, with the owner resolved from the bearer token (`:32-40`). |
| `openmuse:apps/mobile/src/` | Expo / React Native client. `agent-workspace.tsx` polls `/api/agent`. `details.tsx` renders the approve and deny buttons (`:545-580`, `:699-711`). |
| `openmuse:packages/domain/src/index.ts` | Shared types, including `ActionProposal` and its eight statuses (`:132-157`). |
| `openmuse:packages/backends/src/openbot.ts` | A disabled adapter for another agent runtime, pinned to an upstream commit (`:3-4`). |
| `openmuse:tests/` | 27 test files, including `actions.test.ts` and `monitor-recovery.test.ts`. |

**How approvals are modelled.** An `ActionProposal` (`openmuse:packages/domain/src/index.ts:132-157`)
carries:

- the content of the action and the account it is bound to;
- a `status`: `awaiting_review`, `executing`, `succeeded`, `failed`, `outcome_unknown`, `denied`,
  `cancelled` or `expired`;
- a `hash`, `createdAt` and `expiresAt`.

`propose()` hashes the input together with the account and the target version (`actions.ts:77-86`),
and sets an expiry 30 minutes out (`actions.ts:88`). `decide()` works in three steps:

1. It refuses if the hash sent by the client does not match, with the message "This proposal
   changed. Open its latest review before deciding." (`actions.ts:110-111`).
2. It refuses an expired review (`actions.ts:121-135`).
3. It claims the proposal with a single SQL `UPDATE ... WHERE status='awaiting_review' AND
   expiresAt > now` (`db.ts:78-90`), so two taps cannot both execute.

**Receipts.** Every change of state writes an `activity` row (`actions.ts:192-201`): "Ready for
your review" (`:99`), then "Approved; execution started" or "Declined; no changes made"
(`:161-165`), then the result or the error (`:189`). Terminal commands in the container get their
own receipt, with exit code and output (`computer.ts:715-730`).

**Honest failure.** On boot, any action still marked `executing` becomes `outcome_unknown`, with
the text "Server restarted during execution. Check the provider before creating another action."
(`db.ts:91-95`, called from `openmuse:apps/server/src/index.ts:11`). The README states the rule:
"No hidden retry occurs after an uncertain external write." (`openmuse:README.md:136`).

**Task leases.** The worker takes one task at a time and holds a time-limited claim, or lease, on
it:

- It scans for due tasks (`worker.ts:75-111`).
- It takes each one with a compare-and-swap that stamps a random `leaseId` and a `leaseUntil`
  60 seconds out by default (`worker.ts:118-128`).
- It renews the lease on a heartbeat every third of the lease period (`worker.ts:166-181`).
- Every checkpoint or event first confirms the worker still holds the lease, and otherwise throws
  `LostLeaseError` (`worker.ts:136-160`).

A task whose lease has lapsed is picked up again (`worker.ts:81`). Several workers can run safely.
Several API instances cannot (`openmuse:README.md:134`).

**How the mobile client gets agent state.** It uses two channels:

- **Chat** streams AG-UI events through CopilotKit's `useAgent` and `agent.subscribe`
  (`openmuse:apps/mobile/src/chat.tsx:182`, `:208-224`).
- **Everything else**, including tasks and pending approvals, comes from a plain poll of
  `/api/agent` every 3 seconds. The poll runs only while the app is visible, and a request counter
  drops responses that arrive out of order (`openmuse:apps/mobile/src/agent-workspace.tsx:30-72`).

There are no push notifications yet: "Device push notifications" is still unchecked in
`openmuse:ROADMAP.md`.

## Security and audit model

- **Identity boundary.** In live mode the server compares the access key in constant time, then
  issues a random 24-hour session token and stores only its SHA-256 hash (`auth.ts:15-29`). Every
  `/api/*` request maps the bearer token back to an owner (`auth.ts:31-41`, `app.ts:126-136`). The
  owner is always the literal `"local-user"` (`auth.ts:26`). The `owner` column is groundwork for a
  future multi-user system and is not a real boundary today. The security policy says so
  (`openmuse:SECURITY.md:9`).
- **Signed links.** Files and browser consoles use URLs signed with an HMAC over the owner, the
  path and a 15-minute expiry, checked in constant time (`auth.ts:42-66`). The signing key is
  created once, with file mode 0600 (`auth.ts:68-79`).
- **Origin check.** A request whose `Origin` header is not on the allowlist is refused before
  anything else runs (`app.ts:47-50`). This is the same idea as our Origin/Host guard
  (`docs/product/PRODUCT.md` §5.4).
- **Approval binding.** "A proposal is bound to the account, reviewed content, and applicable
  provider version" (`openmuse:SECURITY.md:29`). The hash and connection checks in
  `actions.ts:110-149` enforce this.
- **Untrusted content.** The last line of the README treats web, email and document content as
  evidence only, never as permission to act (`openmuse:README.md:200`).
- **Container.** It runs as a non-root user on a read-only root filesystem, with no network, no
  host mounts, a 30-second limit per command and a 128 KB output cap (`openmuse:SECURITY.md`,
  "Linux computer boundary").
- **What it does not have.**
  - No identity per device: one owner, one key.
  - No tamper-evident log: the `activity` rows are ordinary rows in the same table, and `put`
    can overwrite them (`db.ts:33-39`).
  - No export. "Retention/export controls" is on its roadmap (`openmuse:ROADMAP.md`, last bullet).

**How ours compares.**

- An agent event arrives at `POST /events` (`install/payload/meshd/server.ts:1425-1437`). It is
  redacted and appended to `~/.mesh/agent-events.jsonl` with file mode 0600 (`server.ts:58`,
  `:1079-1107`). `GET /events` returns the last 100 (`server.ts:868-879`).
- The daemon keeps only the last event for each session, in memory (`server.ts:887-888`). It
  treats a session as "waiting" for up to an hour after that event (`server.ts:1050-1058`).
- On the phone, Allow sends the key `enter` and Deny sends `escape`, through the ordinary send
  route (`iOS/AgentChatView.swift:369-373`, `iOS/MeshStore.swift:861-878`, `server.ts:1490-1494`,
  `server.ts:706`). Answers from the watch reach the same route through the phone relay
  (`.agentSend`, `iOS/MeshStore.swift:1098`).
- "Already answered" exists only as UI state on the phone (`iOS/AgentChatView.swift:153-155`,
  `:192-200`). The daemon never learns that a keystroke was an approval, and it keeps no record
  of the decision.
- Identity is one long-lived bearer token per machine, checked in constant time
  (`install/payload/meshd/auth.ts:8-21`). Every paired phone holds the same token, so the daemon
  cannot tell which device answered. Our one scoped credential is the read-only mirror token
  (`docs/product/PRODUCT.md` §5.2, the `sessions.ts` row).

In short: for every approval, OpenMuse can show what was shown, when it was shown, what was
decided and what happened next. We can show that an agent asked, and nothing after that.

## What to borrow

| Pattern | Where it would live in our repo | Effort | Why |
|---|---|---|---|
| An append-only decision receipt: one line per answer, with the event it answered, the key sent, the result and a timestamp (`openmuse:apps/server/src/actions.ts:192-201`) | A new `install/payload/meshd/decisions.ts`, writing `~/.mesh/decisions.jsonl` (mode 0600), called from the send route in `server.ts` | S | Today an answer leaves no trace (`iOS/AgentChatView.swift:369-373`). This is the audit trail, and stage 5.2 of the playbook asks for exactly this. |
| Bind the answer to what the person saw. The client sends the id of the event it showed, and the daemon refuses if a newer event has arrived for that session (`actions.ts:110-111`) | `POST /agents/:x/decide` in `decisions.ts`, called from `Shared/MeshClient.swift` and `iOS/AgentChatView.swift` | M | Our Allow presses Enter into whatever prompt is on screen now, which may not be the one the person read. It touches two serialized files, so it is a slice of its own. |
| One decision per prompt: the first answer wins, and a second answer gets "already answered" (`openmuse:apps/server/src/db.ts:78-90`) | An in-memory map in `decisions.ts`, keyed by event id. The daemon is a single process, so no SQL is needed | S | Today the phone and the watch can both answer the same prompt. Only UI state on the phone prevents a double answer. |
| Expiry on a pending question (30 minutes, `actions.ts:88`, `:121-135`) | The same `decide` route. Reuse the one-hour "waiting" window already in `server.ts:1050-1058` rather than adding a second number | S | An Allow tapped from a notification hours later should be refused with a reason, not typed into whatever is on screen by then. |
| Keep "keystroke delivered" separate from "agent obeyed", and never retry silently (`db.ts:91-95`, `openmuse:README.md:136`) | The wording of the receipt, and of the phone's "Sent" line (`iOS/AgentChatView.swift:746-760`) | S | Our "Sent" means the multiplexer accepted a key, and nothing more. The receipt should claim no more than that, in the spirit of AGENTS.md rule 1. |
| Poll only while the app is visible, and drop responses that arrive out of order (`openmuse:apps/mobile/src/agent-workspace.tsx:30-72`) | The `SessionPeekScreen` poll (`iOS/AgentChatView.swift:111-112`) | S | Whether our poll already drops out-of-order responses is unverified. Check this before building anything new. |
| Short-lived signed links: an HMAC over the path and an expiry (`openmuse:apps/server/src/auth.ts:42-66`) | The `apps.ts` links at `/a/<slug>-<key>` (`docs/agents/CONTRACTS.md`, `GET /a/*`) | M | The key in our app-install links never expires. Worth doing only if you want install links to stop working after a while. Not urgent. |
| Store only a hash of each token the server issues (`auth.ts:23-28`, `:33-37`) | Per-device tokens issued at pairing (`pair.ts`, a serialized file) | L | This is what would let a receipt say *which* device approved. It changes pairing, so it needs your decision first (see the open questions). |

## What not to copy and why

- **License.** `MIT License`, "Copyright (c) 2026 OpenMuse contributors" (`openmuse:LICENSE`).
  - The license allows copying and adapting the code, including in a commercial product. The
    condition is that the copyright and permission notice go with any substantial part that is
    copied.
  - It does not cover CopilotKit Intelligence: "Intelligence is a separate service and is not
    included in this repository's MIT license." (`openmuse:README.md:142`).
  - Recommendation: rewrite the handful of patterns above in our own code, since each is under 40
    lines, rather than vendoring their files. That keeps the daemon dependency-light and avoids
    tracking license notices.
- **CopilotKit Intelligence and AG-UI.** Intelligence is required in every mode, for conversation
  persistence (`openmuse:README.md`, "CopilotKit Rich Threads"). A hosted service in the data path
  conflicts with our first non-goal, "A cloud relay" (`ROADMAP.md`, "Non-goals";
  `docs/product/PRODUCT.md` §10). Our chat already reads the agent's own transcript locally
  (`install/payload/meshd/chat.ts:1-15`).
- **Postgres or PGlite, and the generic `records` table.** Our daemon runs on Bun and stores data
  in JSONL files, using `bun:sqlite` where it needs a search index (`docs/product/PRODUCT.md`
  §5.2, the `chats.ts` row). A second database engine would break our "dependency-light" rule
  (`ROADMAP.md`, "Stance").
- **The task worker and SQL leases.** OpenMuse runs the agent's plan itself, so it has to recover
  steps that were interrupted. We do not run plans. Claude Code, Codex and the other agent CLIs
  run their own loops inside a multiplexer session, and our daemon is one process per machine.
  Leases solve a problem we do not have. If the factory queue ever needs one, GitHub labels
  already do that job (`CLAUDE.md`, "Factory").
- **The Expo / React Native client.** Our clients are native SwiftUI on iPhone, Watch and Mac, and
  the watch is the product (`CONTEXT.md`, "What this is").
- **The Docker Linux computer and the Playwright browser worker.** The point of our product is
  the person's own real machine, not a sandboxed copy. Isolating an agent is already planned
  through a separate Unix user (`ROADMAP.md`, "Later").
- **Access-key login and the owner model.** "An account system for access" is a non-goal
  (`docs/product/PRODUCT.md` §10). Pairing codes stay.
- **The Gmail and Calendar adapters.** These are outside our scope entirely.

## The first block

Add `install/payload/meshd/decisions.ts`, a new module that records each time someone answers an
agent.

- **When it writes.** It appends one JSON line to `~/.mesh/decisions.jsonl` whenever the send
  route delivers `enter` or `escape` to a session whose status is `waiting`. The file has mode
  0600, and `MESHD_DECISIONS_PATH` overrides its path for tests.
- **What each line holds.** The time, the session, the pane, and the key. The title and time of
  the last event for that session, which `lastEventBySession` already holds in redacted form
  (`server.ts:887-888`). Whether the send succeeded, or the error it returned.
- **How to read it.** `GET /decisions?since=` returns the last 100 lines.
- **The `server.ts` change.** It follows the one-module rule: one import, one route line, and one
  call in the send route at `server.ts:1490-1494`.
- **Why no app change is needed.** Answers from the phone, the watch relay and notifications all
  reach the daemon through that one route. So every existing Allow and Deny produces a receipt,
  with no app change and no edit to `Shared/Models.swift` or `Shared/MeshClient.swift`.
- **Out of scope.** Recording which device sent the answer. Every device shares one token, so the
  daemon cannot tell them apart.

**Proof.** A new `scripts/check-decisions.sh`, modelled on `scripts/check-approve-path.sh`.
`scripts/check-all.sh` picks it up automatically through its `check-*.sh` glob
(`scripts/check-all.sh:29`). The check boots a throwaway meshd on a spare port, with a private
tmux socket and scratch paths for `MESHD_EVENTS_PATH` and `MESHD_DECISIONS_PATH`. It then:

1. posts a `needs-input` event, sends `enter`, and asserts one receipt line with `ok: true`;
2. sends to a pane that does not exist, and asserts a receipt with `ok: false`;
3. sends `enter` to a session that is not waiting, and asserts that no line is added;
4. asserts that the file mode is 0600.

The existing `scripts/check-approve-path.sh` and `scripts/check-redact.sh` must stay green, and
`./.claude/scripts/gates.sh fast` must report GREEN.

**Caution for the builder.** `server.ts` is a serialized file (AGENTS.md, "Must be serialized"),
so no other slice may touch it while this one is in progress.

## Open questions for Arya

1. **Is an approvals log something you want to sell?** Suppose a CloudAGI client asks to see every
   time an agent was allowed to do something. Should the answer be a file on each machine (local
   only, as proposed), a view on the phone, or both?
2. **Should we know which device approved?** That needs a separate token for each paired phone or
   watch, instead of today's one shared token. It changes pairing, which is the most sensitive code
   we have. Should we do it now, later, or not at all?
3. **How long should a question stay answerable?** OpenMuse uses 30 minutes. We already stop
   showing a question as waiting after one hour. After that, should an Allow be refused outright,
   or only come with a warning?
4. **How long should receipts be kept?** Every receipt forever, or a capped file (for example, the
   last 90 days), the way `/events` serves only the last 100?
5. **Should a receipt include the question text?** The text is already redacted, but it can still
   contain file paths and commands. Including it makes the log more useful. Leaving it out keeps
   the log smaller and safer.
