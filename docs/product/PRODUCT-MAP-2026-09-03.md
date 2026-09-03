# LeSearch Mesh — product map

Written 2026-09-03 in an unattended session, from four scouting passes over this repo,
the LeSearch-AI org, the archived predecessors, and the machines on this Mac. It answers
one question Arya asked: *what is the whole application, so we can decide whether to
raise and hire or to build it with agents and a factory?*

It is a map, not an authorization. Every "proposed" line below is a proposal. The
decisions it needs are collected in section 9. Nothing here changes public claims;
`launch/BRIEF.md` and `README.md` still govern what the site may say.

Related, and not repeated here: the four OpenSpec changes already in flight
(`openspec/changes/local-brain-and-harness`, `one-session-runtime`, `one-workspace`,
`reach-my-mac-from-anywhere`), the roadmap (`ROADMAP.md`), the launch brief
(`launch/BRIEF.md`), and the quality bar (`CONSTRAINTS.md`, new today).

---

## 1. The thesis in one paragraph

LeSearch Mesh is **your own machines, run by agents, supervised from your wrist, building
software you keep.** Three promises, one product:

| # | Promise | Today |
|---|---|---|
| P1 | **Reach and supervise.** iPhone and Apple Watch control any Mac or Linux machine you own and answer the agents running on it. | Beta. Real, installed on devices, on a public TestFlight link. |
| P2 | **A local brain and a personal software factory.** A local model plus a harness on those machines picks up work, implements it, proves it, and hands you the decision. | A measured spike (PR #119) and a factory that exists on `main` only as prose. |
| P3 | **Apps you own.** From a brief, the factory builds a small app you and your company use daily: a home-screen web app by default, a TestFlight build if you connect your own Apple developer account. | Ingredients only: nothing in this repo builds an app for a user yet. |

And one flow that exercises all three, which is also the first thing Arya needs
personally: **a job posting goes in, a working internal tool for that company comes out,
installed on the phone, with the supervision loop visible on the watch.** Section 5.

The product's structural rule, from `ROADMAP.md` and worth keeping: **every capability is
one daemon module and one `scripts/check-*` that proves it.** This map adds a third clause
as a proposal, not a fact: **and one `mesh` verb.** Today `kb`, `files`, `push`, `wake` and
`input` have no verb in `install/payload/bin/mesh`; the CLI-first stance in
`docs/CLI-FIRST-ROADMAP.md` says they should. No second daemon, no server of ours in the
data path, no account. Pillars 2 and 3 are built by adding modules to the daemon that
already exists, not by starting another product.

---

## 2. What exists today (evidence, not memory)

### P1 — reach and supervise

Shipped and verified against code and docs by the scout: pairing (`pair.ts`), the machine
list, the text terminal on the watch, the WebView terminal on the phone (over a separate
`rmux-bridge` service on port 7820), Mac screen and trackpad, notifications with a risk
classifier shared by all surfaces, the complication, files, clipboard, wake-on-LAN, and
lock/sleep. Telemetry is one anonymized heartbeat a day and nothing else.

Four findings change what to build next:

1. **The reply path has never had a target.** Of the last 312 agent events on this Mac,
   0 were replyable: agents run in bare terminals and Cursor, not inside a multiplexer
   the daemon can type into. Every "answer from the wrist" feature is correct and idle.
   (`TASKS-2026-09-01.md` section A; `openspec/changes/one-session-runtime`.)
2. **Multiplexer support is tmux, rmux and cmux, not the five the docs claim.**
   `server.ts` issues tmux-syntax commands through `MESH_MUX` and carries a cmux path;
   `herdr` appears only as a process name and `zellij` not at all. The deployed daemon on
   this Mac advertises a `herdr` capability the repo's `server.ts` does not have, so the
   deployed lineage is ahead of the repo again (CONTEXT.md, "three lineages have
   drifted").
3. **Three daemon versions disagree.** Repo `server.ts` says `0.5.0`; `mesh-install`'s
   latest release is `v0.5.2` (2026-08-27); the daemon running on this Mac reports
   `0.5.4`. Three machines (this Mac, `dataflow`, `pi`) run whatever was last installed
   on each. An old daemon answers 200 with the old shape. (AGENTS.md rule 6.)
4. **107 issues are open, 17 with a severity label** (2 blocker, 9 high, 5 medium,
   1 low; `gh issue list --limit 300`). The loudest: #80 (an attention banner is raised
   then deleted), #100 (pairing hands out every token verbatim), #101 (reinstall is not
   a reset), #90/#91 (routes answer `ok:true` regardless). Two draft PRs wait on Arya:
   #119 (local inference) and #120 (one Live Activity per event).

Verified absent, on purpose: accounts, a cloud relay, Android, a Windows daemon, restart
or shutdown from the wrist.

### P2 — local brain and factory

**Factory.** `CLAUDE.md` describes a software factory with a contract, a charter, a gate
script, a merge-blocking hook, and two verifier agents. **None of that is on `main`.**
It was installed in one commit, `cc81c8c` (2026-08-28), on branch
`claude/mesh-install-pair-46f4f1`, and never merged; the 2026-08-31 WIP rescue carried
over only the seven `factory-*` skill texts. There is no `docs/factory/`, no
`.claude/scripts/gates.sh`, no `.claude/hooks/block-merge.sh`, no `.claude/agents/`, and
`docs/factory/runs/` has never held a run. **The factory has run zero times.** CI
(`ci.yml`) is the app's own build and `check-all.sh`; it knows nothing about the factory
and does not run on pushes to `main`.

**Brain.** PR #119 (open, mergeable, verdict "land" in `TASKS-2026-09-01.md`) adds
`install/payload/agent/{exec,loop,meshd,mobile,model,risk,tools}.ts`, a `GET /brain`
route that reports which model server is reachable, and `scripts/brain-eval/` that
grades any OpenAI-compatible endpoint on function calling, terminal actions, browser
sequencing, images, and prefix-cache economics. `loop.ts`, `tools.ts` and `model.ts`
(about 840 lines) duplicate what `dsh` already runs in `~/deepseek-harness`; the rest is
harness-agnostic and worth keeping. The PR is 673 files and 146K lines, 144K of them
vendored under `references/`; the verdict to land it stands, and the vendored tree
should leave the daemon's "reviewable in one sitting" claim untouched because it is
not the daemon. `dsh` itself lives outside this repo and is not installed by
`install.sh`; nothing ships it to a user's machine today.

Measured, on this Mac:

| Engine | Model | brain-eval | Notes |
|---|---|---|---|
| Mference via dsh, `:8080` | Qwen 3.6 35B-A3B, 16 slots | 6 pass / 3 fail (cold), 9 / 0 / 1 at 32 slots | RSS 1.14 GiB at 32K context. **Down as of 2026-09-03 morning.** |
| LM Studio, `:1234` | `ornith-1.5-9b`, `nl2shell-0.8b`, an embedder | 7 / 1 / 2 | Up. No vision model loaded; a 10 GB gemma-4 download landed 2026-09-03. |

**Agents on this machine** (`docs/agent-estate/CORE-STACK-2026-09-02.md`): claude, codex,
agy, pi, omp, dsh, cursor-agent. Seven harnesses, all with the same skill pool. The
recurring failure in the last three days was not capability but **account session
limits**: three workflow runs of 8 to 13 concurrent agents died before producing
anything. Nothing records what a run cost or which subscription it drew on.

### P3 — apps you own

Nothing in this repo builds an app for a user. What exists is every ingredient:

| Ingredient | Where | What it gives P3 |
|---|---|---|
| Static hosting behind the bearer token | `input.ts:436` serves `desktop.html`, `files.ts:92` serves `files.html`; `server.ts` gates both | The daemon already serves HTML to the phone over the tailnet. An app is one more directory. |
| On-device SQLite | `kb.ts` (`bun:sqlite`, FTS5, `~/.mesh/kb.sqlite`) | The storage pattern for a per-app database, no new dependency. |
| Pairing and claim links | `pair.ts`, `qr.ts` | A one-use claim URL is exactly how a home-screen app gets its token without typing. |
| The risk classifier | `Shared/RiskClassifier.swift`, `agent/risk.ts` (parity-checked) | Approval semantics for a build step that publishes or spends. |
| The TestFlight pipeline | `scripts/release-testflight.sh`, `docs/testflight-asc.md`, ASC app 6803438426, team `B5B87F7AXF`, the `asc` CLI | The exact command sequence a "publish to TestFlight" lane has to automate for someone else's app. |
| **10x** | public repo `10x-app-builder/10x`, last commit 2026-04-19; README/roadmap in `docs/agent-estate/10x-*.md` | A working macOS app: prompt to plan to SwiftUI code to XcodeGen to `xcodebuild` to a simulator screenshot, with a Claude tool loop. Its "one-click TestFlight upload" was never built. |
| **Glaze** | `references/glaze-system-instructions/` | An eight-role prompt architecture for an app builder: orchestrator, context gatherer, architects, compliance checker, error investigator. Prompts only, no code. |
| `lesearch-factory` | org repo, last push 2026-07-02 | An earlier "run, watch, gate, remember" factory in TypeScript. Process ancestor, not an app builder. |
| The predecessor `lecoder` | archived tarball only | Had a PWA terminal (`apps/web`) and a Supabase account plane. None of it is in this repo, and CODEBASE-SURVEY.md's verdict stands: take assets, never merge old lineages. |
| Supabase, Vercel | one telemetry table; a static landing project | Both accounts exist. Neither hosts anything of a user's. |

Verified absent: a web-app manifest, a service worker, an app scaffold, a per-app storage
layer, any auth beyond the bearer token, any OpenSpec change for a builder.

---

## 3. Target shape

```
                 ┌──────────── one machine you own (Mac, Mac mini, Linux VPS) ────────────┐
                 │  meshd  (Bun/TS, ~/.mesh/)                                             │
  Watch ─────────┤   sessions · input · screen · files · push · kb · pair · doctor        │
  iPhone ────────┤   + brain   (which model is live; local first)            P2           │
  `mesh` CLI ────┤   + factory (claim → run agent in a mux session → gates → draft PR) P2 │
                 │   + apps    (serve ~/.mesh/apps/<slug>/ ; per-app sqlite ; claim link) P3
                 │                                                                        │
                 │  harnesses in mux sessions: dsh (local model) · claude · codex · agy    │
                 │  models: Mference/qwen36 :8080 · LM Studio :1234                        │
                 └────────────────────────────────────────────────────────────────────────┘
   external, optional, all the user's own: APNs (ours, notifications only) · the user's
   Apple developer account (TestFlight) · the user's Supabase · the user's Vercel
```

The daemon stays what it is. Three modules grow, each behind its own `mesh` verb and its
own check, in the order P2-factory, P1-reply, P3-apps, because each one is what the next
one runs on.

### 3.1 P1 additions (small, and they unblock everything)

- **The reply route is a decision, not a design, and it is open.** The daemon can only
  type into a session it can address, which today means a tmux-compatible multiplexer.
  `TASKS-2026-09-01.md` names two options: run agents under a multiplexer the daemon
  knows and teach the hook about that socket, or accept IDE and bare-terminal sessions
  as view-only. A third, proposed here: **`mesh run <agent> [--cwd]`**, which starts the
  harness inside whatever `MESH_MUX` names, so the sessions the product supervises are
  the sessions the product started, and everything else is honestly view-only. That
  keeps AGENTS.md's "multiplexer-agnostic, the user's choice" principle only if
  `MESH_MUX` really is a choice, and the scout found it is tmux-syntax underneath. The
  `one-session-runtime` change owns this; section 9 asks for the answer.
- **Codex hook installed the same way as the Claude Code hook** (today it prints
  instructions). One backlog item, still open.
- **`mesh upgrade` on every machine** before any daemon-side feature is judged. The
  drift ratchet in `CONSTRAINTS.md` makes the lag visible.
- **Reachability** stays as proposed in `openspec/changes/reach-my-mac-from-anywhere`:
  the tailnet or the user's VPN. No relay of ours.

### 3.2 P2 — brain and factory

**Brain (land, do not rebuild).** Merge #119. Keep `exec.ts`, `meshd.ts`, `mobile.ts`,
`risk.ts`, `brain.ts`, `brain-eval/`. Then pick **one** local runner to ship, which is a
decision for Arya (section 9): the in-repo loop from #119 (840 lines, measured 9/0/1 with
Qwen 3.6, shipped by `install.sh` like everything else) or `dsh` (already running here,
measured, but outside the repo and unpackaged). Do not write a third. `GET /brain` is the
single source of truth for "is a local model available and what can it do"; the watch
shows it next to each machine.

Model routing, by cost not by ideology: local models take the cheap, frequent steps
(triage an issue, digest a build log, classify a command's risk, summarize a session
for the watch, draft the research brief in section 5); cloud subscriptions take
implement and review. The `/brain` probe decides per machine, and brain-eval scores,
not vibes, decide which local model is trusted for which step.

**Factory (restore, then run it once).** The installation in `cc81c8c` is the design;
merge it rather than re-deriving it: `docs/factory/CONTRACT.md` and `CHARTER.md`,
`.claude/scripts/gates.sh` mapped onto `check-all.sh`, `.claude/hooks/block-merge.sh`,
the `factory-verifier` and `factory-critic` agents, `docs/factory/runs/`. Add to the
charter's gates the floor in `CONSTRAINTS.md` (already runs inside `check-all.sh` as
`scripts/check-floor.sh`).

Then the one thing the factory lacks that "always-on" requires, proposed as a daemon
module because that is where always-on already lives:

- **`mesh factory run`** (module `factory.ts`): claim exactly one `factory:ready` issue,
  open a mux session named for it, run the chosen harness with the `factory-implement`
  skill, run the gates, open a draft PR, write the immutable run record, close the
  session. One run per machine at a time.
- **Multi-machine means routing, and the queue is GitHub.** Issues are the queue
  (`factory:*` labels, per `docs/agents/issue-tracker.md`). Each machine's `/doctor` and
  `/brain` say what it can do: Xcode present, a local model live, Linux, free memory.
  A run claims only issues whose needs it meets (`needs:xcode`, `needs:local-model`,
  `needs:linux`, added at triage), so the Mac takes app builds and `dataflow` takes
  daemon and Linux work. The watch lists runs on every machine because they are
  sessions. Cross-machine *resumption* of one run is epic #114 and stays there.
- **Concurrency starts at five across the fleet and is written down, not measured.**
  The three fleet deaths this week were OMC subagent fleets of 8 to 13 inside one
  session, and a 3-to-5-agent workflow completed; nothing established a threshold. A
  launchd timer does not cap subagents, so two knobs, both recorded in the run record:
  the workflow size guideline for in-session fleets, and one factory run per machine.
- **Scheduling**: a launchd interval on macOS and a systemd timer on Linux, installed by
  `install.sh` next to the daemon it already installs, off by default, on with
  `mesh factory enable`.
- **The run record carries cost**: harness, model, wall time, tokens if the harness
  reports them, which subscription, and whether the limit was hit. This is the number
  the raise-or-build decision in section 8 needs and nobody has.
- **The watch sees factory runs as sessions.** They are sessions. `sessionsNeedingAttention`
  already decides what reaches the wrist; a factory run that hits a stop condition is one
  more thing that needs you. No new surface.

### 3.3 P3 — Mesh Apps (proposed name; "LeSearch Mesh" stays the product)

**The unit is an app bundle on the user's machine:**

```
~/.mesh/apps/<slug>/
  spec.md          what it is for, who uses it, the three screens (OpenSpec shape)
  web/             static files: index.html, manifest.webmanifest, sw.js, app.js
  data.sqlite      the app's own database, bun:sqlite, kb.ts pattern
  check.sh         the smoke test the factory gate runs: page loads, API round-trips
  RUN.md           the run record that built it
```

**Tier A — no Apple account (the default, and the one to build first).** The daemon
serves `web/` at `/apps/<slug>/` and a small JSON API at `/apps/<slug>/api/*` backed by
`data.sqlite`, both behind the bearer token. The phone opens it over the tailnet or LAN,
Safari's "Add to Home Screen" gives it an icon, and it runs standalone. Auth for the
home-screen app: `mesh apps open <slug>` prints a one-use claim link (the `pair.ts`
mechanism), the page exchanges it for a cookie scoped to that app. Data never leaves
the machine. Offline: the shell is cached by the service worker; the data is on the
machine, so "offline" means "machine unreachable", and the app says that, the way the
machine list does.

Two limits to state honestly and verify on the real phone before claiming them: an
iOS home-screen web app keeps its own cookie jar, so the claim exchange must happen
*inside* the installed app, not in Safari; and web push to a home-screen app needs the
user's permission and iOS 16.4 or later. Neither blocks v0.

**Tier A+ — the second person, which is what "your company" means.** An internal tool
has a team, not a user. Without accounts of ours: the app's owner issues each colleague
their own claim link (`mesh apps share <slug> --to <name>`), each link becomes a cookie
bound to that name, and `mesh apps revoke` ends it. The app's `data.sqlite` gains one
`identities` table the daemon writes on claim, so every row an app stores can carry who
wrote it. Reachability is the company's own tailnet, which Tailscale already lets an
admin share machines on. The enterprise shape is therefore **single-tenant per machine,
many people per app**: a company's Mac mini runs `meshd`, the tool lives on it, the
team reaches it over the company network. What this costs: one table, two verbs, and
the same claim mechanism `pair.ts` already has. What it is not: multi-tenant accounts
run by us, which stays in the "not" list below.

**Tier B — the user's own Apple developer account.** `mesh apple connect` stores the
user's App Store Connect API key in their Keychain (the way `release-testflight.sh`
already expects `ASC_KEY_ID` and `ASC_ISSUER_ID`). The build lane is 10x's pipeline,
restored from the archive and run headless by the factory: SwiftUI from the same
`spec.md`, XcodeGen, `xcodebuild archive`, `xcodebuild -exportArchive` upload, `asc`
to add testers. Beta App Review stays a human wait, and the app says so. This tier
needs a Mac with Xcode in the mesh; the Mac mini that runs the factory is that Mac.
Apple's rules (`docs/app-store-submission.md`) apply to every generated app, which is
what Glaze's compliance-checker role is for.

**The ladders.** Storage: `data.sqlite` by default; `mesh apps connect supabase <slug>`
exports the schema and points the API at the user's own project when an app's data
must outlive one machine. Identity does not change on that rung: the daemon stays the
app's only client of Supabase, so the user's project holds data, not accounts, and no
row-level policy has to know who a person is. Front end: served by the daemon by
default; `mesh apps deploy vercel <slug>` when the app must be reachable without the
mesh. The two are coupled and the CLI should refuse the second without the first: a
front end on Vercel talking to a database on a laptop is a promise the product cannot
keep. And the second rung changes identity for real: an app reachable without the
mesh cannot use the daemon's claim cookies, so it uses the user's own Supabase Auth,
which is their account system, not ours. `ROADMAP.md` lists an account system as a
non-goal, and this keeps it one.

**The builder.** Glaze's roles, run through the factory loop: context gatherer (the
brief), architect (the spec and screens), builder (the code), compliance checker
(Apple rules for Tier B, the floor for both), error investigator (the retry when
`check.sh` fails). 10x's ideas file already says what the builder UI must have to be
trusted, and two of them transfer directly to a phone: a diff or a screenshot before
apply, and a checkpoint to roll back to. Every app run is a factory run, so it has a
record, a gate, and a stop condition.

**Not Mesh Apps:** hosting of ours, an app store, a drag-and-drop editor, multi-tenant
accounts run by us, Android. The app the user gets is a directory on a machine they own,
shared with the people they hand a link to.

---

## 4. In and out

| Include | Because |
|---|---|
| The three modules (`brain`, `factory`, `apps`) as daemon modules with `mesh` verbs | It is the shape everything else already has; one patch to `server.ts` each. |
| A decided reply route before any more notification work | The reply path has had zero targets in 312 events; every option needs a yes from Arya first. |
| Restoring `cc81c8c` before any new factory code | It is designed and written; it is just not on `main`. |
| Local model for the cheap steps, cloud for implement and review | Measured: local tool calls at 12 to 21 s are fine for triage and unbearable for a 200-step build. |
| Tier A apps before Tier B | Tier A needs nothing from Apple and is the tier a non-developer can use on day one. |
| The job-to-tool flow as the first end-to-end proof | It is the only flow that needs all three pillars and it has a user (Arya) this week. |
| A run record with cost | The build-versus-hire question is unanswerable without it. |

| Exclude | Because |
|---|---|
| A relay, accounts, hosting user apps | Local-first is the moat and `reach-my-mac-from-anywhere` already frames the reachability decision. |
| A second daemon, a monorepo migration, merging `lecoder`/`lesearch-factory` code | `one-workspace` covers consolidation; CODEBASE-SURVEY says take assets, never lineages. |
| A visual builder, Android, Windows, a TUI | Later or never, per `ROADMAP.md`. |
| Building the harness loop again | `dsh` and #119 both exist; pick, do not write a third. |
| Unrecorded concurrency | Three fleets died at 8 to 13; start at five and write every run down. |
| Any Tier B work before one Tier A app is installed on a phone | Tier B needs Apple, a Mac with Xcode, and review waits; it proves nothing Tier A does not. |

---

## 5. The first end-to-end flow: a job posting becomes an internal tool

The use Arya described: for a role he is applying to, understand the company, find an
internal workflow worth a tool, build the tool, and use it in the interview as the
product-skills, forward-deployed and AI-native proof in one artifact.

Proposed as `mesh` verbs so it is scriptable from day one and each step is a factory run
with a record:

1. **`mesh apps scout <job-url or company>`** on the always-on Mac. The local brain
   fetches the posting and the company's public pages, writes
   `~/.mesh/apps/<slug>/brief.md`: industry, product or service, the teams and workflows
   named in the posting, and **three candidate internal tools** ranked by how much of the
   role they demonstrate. Cheap step, local model, minutes.
2. **The watch asks.** "3 tool ideas for `<company>` — pick one." This is the attention
   handoff the launch brief is built around, with a real payload. Pick on the wrist or
   the phone; the choice is written to `spec.md`.
3. **`mesh apps build <slug>`** runs the builder (section 3.3) as a factory run: spec,
   screens, `web/`, `data.sqlite` seeded with plausible sample data, `check.sh`. Cloud
   harness for the build, local for log digests and risk. The run stops for the user
   only on a stop condition or a spend.
4. **The phone gets the link.** The factory sends the claim link as a notification; tap,
   add to Home Screen, use it. A screenshot set and a 30-second screen recording of
   the simulator are attached to the run record for the portfolio.
5. **`mesh apps export <slug>`** writes the brief, the spec, the screenshots and the
   redacted run record to a folder Arya can push to the portfolio site. The app and its
   data stay on the machine; the story is what gets published.

Proof of the flow, and the acceptance test for pillars 2 and 3 together: **one posting
in, one working home-screen app out, unattended, under two hours of wall clock, with
every human decision made from the watch.** The first three runs will not be unattended.
That is what the run records are for.

---

## 6. Sequence, by gate

No dates. Each phase ends with a command that proves it and a thing Arya can touch.

| Phase | Work | Proof |
|---|---|---|
| 0. Ship what exists | Confirm `mesh.lesearch.ai` serves (the CNAME resolved to Vercel on 2026-09-03; the install script was not reachable from this session's network, so nobody has proven it end to end); submit the newest build for Beta App Review; merge #119; prove #120 on the real phone; `mesh upgrade` all three machines; realign local `main` with `origin/main` | `curl -fsSL https://mesh.lesearch.ai/install.sh \| head -3` prints the installer; `asc testflight distribution view` shows the new external build; `/health` on all three machines reports the same version |
| 1. Factory restored | Merge `cc81c8c` (contract, charter, gates, hook, agents, runs); add `CONSTRAINTS.md` floor to the gates; run the factory **once** by hand on one small `factory:ready` issue | `docs/factory/runs/` holds one record; the draft PR exists; the merge hook refused a merge when tried |
| 2. Reply path real | `mesh run` lands agents in the mux; Codex hook installs; one permission prompt reaches the watch and its answer reaches the agent | one event in `agent-events.jsonl` with `replyable:true` and the agent's transcript showing the wrist's answer |
| 3. Always-on | `mesh factory run` module, launchd timer, cost fields in the run record; five runs unattended on the Mac, one on `dataflow` | five run records with cost; zero merges by an agent; concurrency never above five |
| 4. Mesh Apps v0 (Tier A) | `apps.ts`: static + sqlite API + claim-link cookie; one **hand-written** app installed to Arya's Home Screen and used for a week | the app on the Home Screen; `check.sh` green; the two iOS limits in 3.3 verified or corrected on the real phone |
| 5. The builder | Glaze roles as factory skills; `mesh apps scout / build / export`; first job-to-tool run for a posting Arya picks | section 5's proof, with the run record attached |
| 6. Tier B | `mesh apple connect`; 10x pipeline restored and run headless; one generated app on Arya's own TestFlight | `asc builds list` shows it; Beta App Review submitted |
| 7. Ladders | Supabase and Vercel connectors, only when a real app needs sharing or reach | the first app that needed them, and no earlier |

Phases 0 and 1 are days. Phases 2 to 4 are each a small number of factory runs once
phase 1 works, which is the point of doing phase 1 first.

---

## 7. What is not the product's job

The sprawl is real (`one-workspace`: 106 repos, 183 on GitHub, 7 deployments) and it is
a workspace problem, not a product problem. This map assumes `lecoder-watch` stays the
one product repo and everything else is an asset to import file by file, which is the
verdict `CODEBASE-SURVEY.md` already reached. The per-session token overhead measured in
`docs/agent-estate/AGENT-ESTATE-2026-09-01.md` (35 to 45 thousand tokens before the first
word, mostly skill listings) is a cost the factory pays on every run and belongs in the
run record too.

---

## 8. Build it with agents, or raise and hire

The honest inputs:

- The factory has run zero times. Its design exists and was never merged. Until phase 1
  is done, "the agents will build it" is a plan without a single data point.
- The three failures this week were all the same failure: too many concurrent subagents
  in one session on one subscription. A factory that runs one job per machine from a
  timer does not have that failure; in-session fleets still can, which is why the
  workflow size guideline is a knob in section 3.2 and not an afterthought.
- Two kinds of work cannot be delegated: **verification on the physical iPhone and
  Watch** (AGENTS.md says so, and three features shipped dead because it was skipped) and
  **anything Apple reviews**. Both are hours a week, not a hire.
- Arya is the only merge authority and the only reviewer. Review time, not agent time,
  is the throughput ceiling. A factory that opens more draft PRs than he can read in an
  hour a day is a factory that should throttle, and the charter's stop condition
  ("more than two awaiting review") already says so.
- The deck's raise is scoped to proving retention and demand, not to building. Hiring
  engineers before the factory has a throughput number means hiring to do what has not
  yet been shown to need people.

**Recommendation.** Run the agent route for eight weeks with a number on it, then decide.
The number: **merged pull requests per week that closed a severity-labelled issue or a
phase gate, with zero regressions in `check-all.sh` and zero merges by an agent**, read
from the run records.

The baseline, measured today so the experiment has one: **3 merged pull requests in the
trailing four weeks**, all on 2026-08-27, all by Arya, all release work. Call it under
one a week. The ceiling is review time, not agent time: if an hour a day reviews about
two draft PRs, the factory cannot usefully produce more than ten a week whatever it
costs, and the charter's "more than two awaiting review" stop already throttles at that
point. So the pass line is modest and the rule is explicit:

- **Pass:** four or more qualifying merges a week by week six, sustained to week eight,
  and phases 2 to 5 cleared. The raise story becomes "a solo founder with a working
  factory", which is stronger than "a founder who needs engineers".
- **Fail:** fewer than two a week by week six, or a run-record cost per qualifying merge
  above the number Arya sets before week one (a subscription-month divided by the
  merges it produced is the honest unit; no number is offered here because none was
  measured). Then the run records say where it stalled, which is a hiring spec.
- **Middle:** phases 2 and 3 clear and 4 stalls. That is the case the records are for;
  decide on what stalled, not on the count.

Price the counterfactual before week one, not after: one contractor for eight weeks on
the same phase list, against the subscription spend the run records will show. That
comparison is what this recommendation is actually making, and it cannot be made yet.

Spend money first on the two things agents provably cannot do: a few hours a week of
physical-device QA, and design-partner conversations for the launch brief. Not engineers.

What the always-on setup costs, concretely: this Mac or a Mac mini on the tailnet with
Xcode, `dataflow` as the Linux runner, one launchd timer, and the subscriptions already
paid for, scheduled instead of stampeded.

---

## 9. Decisions this map needs from Arya

1. **Land #119** (mark ready and merge; agents never merge).
2. **Restore the factory from `cc81c8c`.** It edits `AGENTS.md`, `CLAUDE.md` and adds
   policy files; that is human-owned by the factory's own rules, so it needs a yes.
3. **The reply route:** supervised agents are agents started by `mesh run` inside the
   mux; everything else is view-only. Yes, or a different answer.
4. **Mesh Apps Tier A as described** (daemon-served home-screen web app, per-app SQLite,
   claim-link cookie), and the name "Mesh Apps" for the lane in internal docs. Public
   naming stays with the brand kit.
5. **The first company** for the job-to-tool run in section 5.
6. **Realign local `main`** (ahead 1, behind 12; the extra commit equals
   `origin/backup/2026-09-01`). Needs `git reset --hard origin/main`, which drops
   snapshot-only files from the tree, all of which are in `backup/2026-09-03`.
7. **`CONSTRAINTS.md`**: read the four defaults it took and the two exceptions it
   recorded; change any number you disagree with, and add its one-line pointer to
   `AGENTS.md`.
8. **The local runner to ship:** #119's in-repo loop, or `dsh` packaged into
   `install.sh`. One, not both.
9. **The pass and fail numbers for section 8**, and the cost per merge you will stop at.

---

## 10. Sources

Scouting passes on 2026-09-03 over: `AGENTS.md`, `CONTEXT.md`, `ROADMAP.md`,
`CHANGELOG.md`, `PROGRESS.md`, `docs/backlog.md`, `docs/mac-remote-control.md`,
`docs/CLI-FIRST-ROADMAP.md`, `docs/competitive-position.md`, `docs/release-workflow.md`,
`docs/testflight-asc.md`, `docs/agent-estate/*`, `launch/*`, `TASKS-2026-09-01.md`
(untracked working notes), the four `openspec/changes/*`, `install/payload/meshd/*.ts`,
`Shared/*.swift`, `iOS/*.swift`, `Watch/*.swift`, `.github/workflows/ci.yml`,
`scripts/check-all.sh`, `gh issue list`, `gh pr view 119`, `gh repo list LeSearch-AI`,
`git log --all` for `cc81c8c`, `~/deepseek-harness/AGENTS.md`, and live probes of
`127.0.0.1:8899`, `:8080`, `:1234`. Nothing in this file was taken from a document dated
before August 2026 without a newer source agreeing. Two sources are untracked on `main`
(`TASKS-2026-09-01.md`, `references/glaze-system-instructions/`); both are committed on
`backup/2026-09-03`, so realigning `main` (decision 6) does not lose them. An
independent critic re-measured this map on 2026-09-03 and its corrections are in.
