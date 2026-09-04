# docs/playbooks/ — Xcode & Apple tooling, for any agent

Internal runbooks for driving this repo's Xcode/Apple tooling correctly — written so any
agent working this repo (Claude Code, Codex, cursor-agent) can regenerate the project,
build, install to a device, run a simulator check, or cut a TestFlight release without
relearning the traps that have already cost real days. Dense and imperative on purpose:
these are instructions to follow, not stories to read, even where a war story is the
fastest way to explain why a rule exists.

**`AGENTS.md` should link here** — add a line pointing at `docs/playbooks/README.md` from
its "Where things are" table. `AGENTS.md` is deny-listed for automated edits in this
worktree, so that link was not made as part of writing these files; a human or a follow-up
pass with write access needs to add it.

## Files

| File | Read it when |
|---|---|
| [xcode-cli.md](xcode-cli.md) | Running `xcodegen`, choosing `DEVELOPER_DIR`, or driving `xcodebuild` from a shell |
| [device-install.md](device-install.md) | Installing to Arya's physical iPhone/Watch, or pulling a crash log or prefs off one |
| [simulator-testing.md](simulator-testing.md) | Writing, debugging, or running a simulator-based check (`check-ios-smoke.sh` and friends) |
| [release-and-asc.md](release-and-asc.md) | Cutting a TestFlight release, or running any `asc` command by hand |
| [daemon-and-mesh.md](daemon-and-mesh.md) | Driving `meshd` / the `mesh` CLI, or restarting a local service |

Each file assumes you have already read [`AGENTS.md`](../../AGENTS.md) — the rules there
(verify by running, worktree hygiene, grep can lie, the one daemon copy, never restart a
live service, the shipped payload lags the repo, zsh word-splitting, `lsof -i` matches
both ends) are the repo-wide ones. What follows is the Apple-tooling-specific layer on top.

## The iron rules

Everything else in this folder is detail under these three. They generalize past this
repo and have each cost days when skipped.

### 1. Verify by running, not by building

A green `xcodebuild` proves the code compiles. It proves nothing about whether the app
opens. 0.5.0 shipped a build where **every screen containing a `TextField` crashed on
appearance** —`UITextField.appearance().smartQuotesType = .no` throws when UIKit replays a
stored appearance invocation onto a text field entering a window — and every check in
`scripts/` was green while it did, because the check meant to guard that area
(`check-phone-input-and-wake.sh`) grepped for the exact crashing line and *required* it
present. The grep proved the crash was still there. It could not, and did not, prove the
app worked.

The fix pattern: something has to actually launch the app and put the risky thing on
screen. `scripts/check-ios-smoke.sh` does exactly that — installs on a simulator, visits
every tab, opens the pairing sheet — and it is now a hard, no-hatch gate inside
`scripts/release-testflight-asc.sh` (see [release-and-asc.md](release-and-asc.md)). Before
trusting any check you add or read, ask: can this only fail at runtime (a UIKit call, a
WatchConnectivity handoff, a daemon response shape)? If a grep cannot see the failure, the
check needs to run the code, not read it.

### 2. A pipeline exits with its LAST command's status — never judge a suite through tail/pager

```sh
sh scripts/check-all.sh | tail -3     # WRONG — you read tail's exit code, not check-all.sh's
```

This read a failing suite as green **twice in the same session**: `check-all.sh` was
returning 1 (a version check was failing), `tail` succeeded regardless of what it printed,
and `$?` reported `tail`'s success. Always redirect to a file and check the real exit
status:

```sh
sh scripts/check-all.sh >/tmp/check.log 2>&1; rc=$?
tail -40 /tmp/check.log
[ "$rc" -eq 0 ] || { echo "FAILED — full log: /tmp/check.log"; exit 1; }
```

The same trap applies to `| grep`, `| head`, `| python3 -m json.tool` — any pipe whose
*first* command is the one that can fail. If you want filtered output, capture the exit
code of the command that matters first, then filter a file — never filter the live pipe.

### 3. `assert` is a no-op under `-O` — Swift checks MUST compile `-Onone`

Every `scripts/check-*.swift` file is built on `assert()`. Swift strips `assert` bodies
entirely from an optimized (`-O`) build, so a check compiled that way exits 0 **even when
the code under test is wrong** — verified directly: breaking `normalizedPreviewPoint` and
building its check with `-O` still exits 0.

`scripts/check-all.sh` gets this right already; copy its invocation rather than inventing
your own:

```sh
DEPS="Shared/Models.swift Shared/LimitHelpers.swift Shared/AgentNotifications.swift \
Shared/WatchGlance.swift Shared/APNsEnvironment.swift Shared/RiskClassifier.swift \
Shared/ScreenZoom.swift Shared/AlertGating.swift Shared/DaemonCapabilities.swift"
/usr/bin/swiftc -Onone -o /tmp/check-x scripts/check-x.swift $DEPS && /tmp/check-x
```

Never add `-O` (or a Release-config build setting) to a Swift check invocation, and never
let a CI default that implies optimization apply to one.
