# docs/ — what is in here, and what is still true

Seventeen files, written over three months, and until now nothing said which ones describe
the product as it is versus the product as it was. An agent that opens
`PROJECT-STATE-AND-LEARNINGS-2026-07-07.md` cold is told to work on branch
`backup/2026-07-02` and never push — advice that was correct in July and is wrong now.

So: **read the top table. Treat the bottom table as archaeology.**

The repo-level brief is [AGENTS.md](../AGENTS.md); [CONTEXT.md](../CONTEXT.md) is the map of
the code and [MEMORY.md](../MEMORY.md) is why it is shaped that way. Nothing here replaces
those three.

---

## Current — read these when you work in that area

| Doc | Read it when | Notes |
|---|---|---|
| [PRODUCT-SPEC-V1.md](PRODUCT-SPEC-V1.md) | Deciding what to build or ship next | The consolidated launch spec, 2026-08-28. §1.4 and the open-decision answers record where the owner overrode its recommendations — the DECIDED/RESOLVED markers are the current truth. |
| [playbooks/](playbooks/README.md) | Before touching Xcode, simulators, devices, releases, asc, or the daemon from any agent harness | Six imperative playbooks; every trap in them was paid for at least once here. |
| [mac-remote-control.md](mac-remote-control.md) | Touching pointer, keyboard, media, windows or power | The control surface, end to end. Referenced from CONTEXT.md. |
| [mesh-cli-and-remote-install.md](mesh-cli-and-remote-install.md) | Adding a machine, the `mesh` CLI, upgrade/uninstall | Start here for anything installer-shaped. |
| [local-first-ade.md](local-first-ade.md) | Building or changing the app-building skills, or `mesh apps`/`mesh skills` | The two build routes (native via Xcode+devicectl, PWA via `mesh apps publish`) and the daemon underneath both. |
| [launch-0.6.md](launch-0.6.md) | Writing the TestFlight notes, the launch posts or the demo recording for 0.6 | Launch kit for 0.6: TestFlight notes, X thread, LinkedIn, Show HN, demo script, and the claims not to make. |
| [release-workflow.md](release-workflow.md) | Cutting a release | See the warning below — the fleet lags the repo. |
| [backlog.md](backlog.md) | Asking "do we already have X?" before building it | 75 items graded against the code as done/partial/buried/missing. Generated — edit `.github/backlog.json`, not this. |
| [updating.md](updating.md) | Anyone asks "how do I get the new version?" | Three components, three routes, no cable. Includes the internal-vs-external TestFlight trap. |
| [ci.md](ci.md) | Changing `.github/workflows/ci.yml` | What triggers, what cancels. |
| [app-store-submission.md](app-store-submission.md) | Anything App Review touches | Aug 2026, every rule links to Apple's source. |
| [XCODE-WATCH-DEVICE-RUNBOOK.md](XCODE-WATCH-DEVICE-RUNBOOK.md) | Running on the physical watch | Signing and device traps. |
| [VOICE-INPUT-SPEC.md](VOICE-INPUT-SPEC.md) | Any voice or dictation work | **Read the 2026-08-21 addendum first:** watchOS ships no Speech.framework, so the watch half of the original spec is not buildable as written. |
| [competitive-position.md](competitive-position.md) | Deciding what to build next | Aug 2026 research. Changes what is worth doing. |
| [CLI-FIRST-ROADMAP.md](CLI-FIRST-ROADMAP.md) | Questioning the product shape | 2026-08-21 decision doc: daemon+CLI as the product. |
| [CODEBASE-SURVEY.md](CODEBASE-SURVEY.md) | Tempted to merge code from another LeCoder/LeSearch folder | Verdicts on all 12. The rule it lands on: take assets, never merge old code lineages. |
| [native-limits-recipe-2026-07-07.md](native-limits-recipe-2026-07-07.md) | Working on usage limits | Dated, but the recipe still describes the shipped path. |
| [launch-posts.md](launch-posts.md) | Writing launch copy | Drafts only, nothing posted. Written for 0.3.0, so the version numbers need updating. |

## Dated snapshots — history, not instructions

These were true when written. They are kept because they record *why* decisions were made,
and several contain user feedback that still has not been fully answered. **Do not take
branch names, version numbers or "next steps" from them.**

| Doc | What it captures | Why not to act on it directly |
|---|---|---|
| [PROJECT-STATE-AND-LEARNINGS-2026-07-07.md](PROJECT-STATE-AND-LEARNINGS-2026-07-07.md) | Full resumption context, July | Names `backup/2026-07-02` as the branch to work on. That tree is now months stale — see AGENTS.md rule 2. |
| [GOALS-2026-07-07.md](GOALS-2026-07-07.md) | The July goal statement | Still a good statement of intent; the status attached to each goal is long out of date. |
| [NEXT-AGENT-HANDOFF.md](NEXT-AGENT-HANDOFF.md) | "The mobile terminal is not usable" | The complaint is still live and worth reading. The plan around it has been overtaken. |
| [PRODUCT-CONTEXT-2026-06-05.md](PRODUCT-CONTEXT-2026-06-05.md) | June feedback on the terminal UI | Same: the feedback matters, the surrounding state does not. |
| [IMPECCABLE-SETUP.md](IMPECCABLE-SETUP.md) | A design-quality baseline that was parked | Explicitly says not to install it during handoff-only mode. Nobody has picked it up. |

---

## One thing that will mislead you if nobody says it

**The fleet does not run this repo.** Machines run whatever `mesh-install` last released.
On 2026-08-27 that was **v0.4.1 (21 Aug)** against a **0.5.0** daemon here, which meant
seven capabilities the Swift calls every day were answered by nothing, and an installed
`mesh-hook` 30 lines behind the one in this tree.

That gap has produced at least three multi-day investigations into app code that was
already correct. Before you debug daemon-side behaviour against a real machine, ask the
machine what it is running:

```sh
curl -s http://127.0.0.1:8899/health | python3 -m json.tool | head -20
```

An old daemon does not refuse a new parameter — it answers **200 with the old shape**.
That is indistinguishable from the feature being broken, which is exactly why it costs days.
