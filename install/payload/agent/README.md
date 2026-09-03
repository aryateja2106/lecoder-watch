# mesh-code — a local coding agent that works through your machine

The brain is whichever OpenAI-compatible endpoint is running locally: our own inference,
or an LM Studio you already use. Commands execute inside a **persistent meshd session**,
so a task stays watchable and steerable from the phone and the watch while it runs, and
survives the CLI being closed.

```sh
mesh-code brain                     # which local model is available, and what it can do
mesh-code run "fix the failing login test" --cwd ~/projects/app
mesh-code runs                      # recent runs
mesh-code show <id>                 # a run's transcript
```

`--endpoint URL` talks to a model directly instead of asking meshd; `--json` for scripts;
`--max-turns N` bounds a run. Every run prints which brain answered, because implying
local while a hosted API does the work is the one thing the specs forbid outright.

## Files

| File | Role |
|---|---|
| `meshd.ts` | Typed client for the daemon routes the agent uses |
| `exec.ts` | Running a command and knowing what happened — read the comment before changing it |
| `model.ts` | Any OpenAI-compatible endpoint; resolves which brain via `GET /brain` |
| `tools.ts` | Six flat tools, sized for a ~3B-active model |
| `mobile.ts` | Test logs and UI dumps digested before the model sees them |
| `loop.ts` | The turn loop and its guardrails |
| `session.ts` | Durable run state under `$MESH_HOME/code/runs` |
| `cli.ts` | Subcommands and output |

## Three things that are counter-intuitive

**1. Commands are redirected to a log, not teed to the pane.** The obvious design —
`cmd | tee log` for a live pane — has two bugs and one of them is fatal. A pipeline runs
in a subshell, so `cd`, `export` and `source` are silently lost (`cd /etc` then `pwd`
printed `/tmp`), which destroys the point of a persistent session; and `$?` after a pipe
is tee's status, always 0, so every failing command looks successful. Using process
substitution fixes both but introduces a worse one: tee writes to the pane
asynchronously, so on a large run the completion marker is buried under the flood behind
it and the run never reports at all (`seq 1 200000` hung). The shipped version redirects
to a log, bounds a tail file for the 64 KB `/fs/read` ceiling, and prints a marker
carrying the exit code and log size. The cost is that the pane no longer streams live
output. Correct exit codes and a working `cd` are not negotiable; live echo is.

**2. A user message mid-run is expensive.** On the Qwen dialect the only prompt-cache path
that can hit is raw token-prefix matching (the structural tool-result path throws for
every dialect except Gemma). The ChatML template scans back to the last user message that
is not wholly a tool response, so appending one re-prefills the entire history. Mid-run
guidance is therefore appended to a tool result the loop is already about to send. A full
run should carry exactly one user message: the task.

**3. Arguments are coerced, never rejected on type.** Qwen's parser opportunistically
types any value starting with `{[-0123456789tfn` that parses as JSON, so
`run_command(command="true")` arrives as boolean `true` and a path like `2024` arrives as
a number. Type-checking these away silently refuses valid calls.

## What is verified, and what is not

Verified by running against a real daemon and a real multiplexer on Linux: command
execution with exact exit codes (0, 2, 7), 200000/200000 lines captured, `cd` persistence,
timeout with interrupt and recovery, malformed-argument and unknown-tool correction, the
repeat guard, durable state, and prompt-cache accounting. `scripts/check-mobile-digest.sh`
covers the digesters.

Not verified: nothing in the iOS or Android command surface has been executed — this
development box has no `adb`, `xcrun`, `xcodebuild` or Android SDK. The digesters are pure
text functions and are tested; the device commands they parse for must be confirmed on the
Mac.
