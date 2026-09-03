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

The product's only structural rule, already true and worth keeping: **every capability is
one daemon module, one `mesh` verb, and one `scripts/check-*` that proves it.** No second
daemon, no server of ours in the data path, no account. Pillars 2 and 3 are built by
adding modules to the daemon that already exists, not by starting another product.

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
2. **Multiplexer support is tmux and rmux, not the five the docs claim.** `server.ts`
   issues tmux-syntax commands through `MESH_MUX`; `herdr` and `zellij` appear only as
   process names. The deployed daemon on this Mac advertises `herdr` and `cmux`
   capabilities the repo's `server.ts` does not have, so the deployed lineage is ahead of
   the repo again (CONTEXT.md, "three lineages have drifted").
3. **The fleet lags the repo.** Repo daemon says `0.5.0`; `mesh-install` latest is
   `v0.5.2` (2026-08-27); three machines (this Mac, `dataflow`, `pi`) run whatever was
   last installed. An old daemon answers 200 with the old shape. (AGENTS.md rule 6.)
4. **32 confirmed code defects are open** (`gh issue list`), the loudest being #80 (an
   attention banner is raised then deleted), #100 (pairing hands out every token
   verbatim), #101 (reinstall is not a reset), #90/#91 (routes answer `ok:true`
   regardless). Two draft PRs wait on Arya: #119 (local inference) and #120 (one Live
   Activity per event).

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
harness-agnostic and worth keeping.

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
| Static hosting behind the bearer token | `server.ts` routes to `desktop.html`, `files.html` | The daemon already serves HTML to the phone over the tailnet. An app is one more directory. |
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

- **`mesh run <agent> [--cwd]`**: launch a harness *inside* the daemon's multiplexer so
  hooks fire with a session the daemon can type into. This is the reply-route decision
  in `TASKS-2026-09-01.md` made concrete: agents the product supervises are agents the
  product started. IDE and bare-terminal sessions stay view-only, and the app says so.
- **Codex hook installed the same way as the Claude Code hook** (today it prints
  instructions). One backlog item, still open.
- **`mesh upgrade` on every machine** before any daemon-side feature is judged. The
  drift ratchet in `CONSTRAINTS.md` makes the lag visible.
- **Reachability** stays as proposed in `openspec/changes/reach-my-mac-from-anywhere`:
  the tailnet or the user's VPN. No relay of ours.

### 3.2 P2 — brain and factory

**Brain (land, do not rebuild).** Merge #119. Keep `exec.ts`, `meshd.ts`, `mobile.ts`,
`risk.ts`, `brain.ts`, `brain-eval/`; treat `loop.ts`, `tools.ts`, `model.ts` as a
fallback harness and let `dsh` be the primary local runner, since it already runs, is
measured, and is one process. `GET /brain` is the single source of truth for "is a local
model available and what can it do"; the watch shows it next to each machine.

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
  session. One run per machine at a time. Concurrency across the fleet is capped at five
  agents total, the number below which the session-limit deaths stopped.
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
exports the schema and points the API at the user's own project when an app needs to
be shared across people or devices. Front end: served by the daemon by default;
`mesh apps deploy vercel <slug>` when the app must be reachable without the mesh. The two
are coupled and the CLI should refuse the second without the first: a front end on
Vercel talking to a database on a laptop is a promise the product cannot keep.

**The builder.** Glaze's roles, run through the factory loop: context gatherer (the
brief), architect (the spec and screens), builder (the code), compliance checker
(Apple rules for Tier B, the floor for both), error investigator (the retry when
`check.sh` fails). 10x's ideas file already says what the builder UI must have to be
trusted, and two of them transfer directly to a phone: a diff or a screenshot before
apply, and a checkpoint to roll back to. Every app run is a factory run, so it has a
record, a gate, and a stop condition.

**Not Mesh Apps:** hosting of ours, an app store, a drag-and-drop editor, multi-tenant
accounts, Android. The app the user gets is a directory on a machine they own.

---

## 4. In and out

| Include | Because |
|---|---|
| The three modules (`brain`, `factory`, `apps`) as daemon modules with `mesh` verbs | It is the shape everything else already has; one patch to `server.ts` each. |
| `mesh run` so supervised agents are mux-hosted | The reply path has had zero targets in 312 events. |
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
| More than five concurrent agents | Three fleets died at 8 to 13. |
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
| 0. Ship what exists | DNS CNAME for `mesh.lesearch.ai`; submit the newest build for Beta App Review; merge #119; prove #120 on the real phone; `mesh upgrade` all three machines; realign local `main` with `origin/main` | `curl https://mesh.lesearch.ai/install.sh` resolves; `asc testflight distribution view` shows the new external build; `/health` on all three machines reports the same version |
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
- The three failures this week were all the same failure: too many concurrent agents on
  one subscription. That is a scheduling problem, and section 3.2 schedules.
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
The number: **merged pull requests per week that closed a confirmed defect or a phase gate,
with zero regressions in `check-all.sh` and zero merges by an agent**, read from the run
records. Phase 1 gives the first record within days. If by week eight the factory clears
phases 2 to 5, the raise story is "a solo founder with a working factory", which is
stronger than "a founder who needs engineers". If it does not, the run records say
exactly where it stalled, which is a hiring spec.

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
before August 2026 without a newer source agreeing.
