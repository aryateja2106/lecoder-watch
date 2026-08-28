# The daemon, the bridge, and the `mesh` CLI

`meshd` and `rmux-bridge` are **live, user-facing services** — Arya's phone and watch talk
to them right now. Treat "restart the daemon to test something" as almost always the wrong
move; boot a second instance on a spare port instead (`AGENTS.md` rule 5). This file is
about the parts you legitimately do need to touch: the CLI, the ports, the tokens, and how
to restart the real services when a restart is actually called for.

## Ports — two different "bridge"s, do not confuse them

| Service | Port | What it is |
|---|---|---|
| `meshd` | `:8899` | The daemon. Sessions, agents, screen capture, input, pairing — everything in the API table in `AGENTS.md`. |
| `rmux-bridge` | `:7820` | Part of the **mesh install stack** (`install/payload/rmux-bridge/`) — the live terminal stream a browser-based `/desktop` view attaches to. Installed and supervised alongside `meshd`. |
| `cmux-bridge` | `:8901` | A **separate, local-only** dev tool (`~/.mesh/hooks/cmux-bridge.zsh`, started on every interactive zsh) — not part of the mesh install payload. This is the one that has actually killed `meshd` — see the warning below. |

Do not assume "the bridge" always means the same thing across docs and shell history; check
which port a script is talking about before acting on it.

## The `mesh` CLI — essentials

Config lives in `~/.mesh/hosts.json`. `mesh --help`, `mesh help <cmd>`, `mesh man`, and
`--json` on any command for scripting.

```sh
mesh host add dataflow 100.80.10.95    # register a host (default port 8899)
mesh hosts                             # list hosts + reachability
mesh pair                              # print an address + one-time 8-char code (10 min, one use)
mesh ls -H dataflow                    # sessions on that host
mesh new fix-bug -H dataflow --cmd claude --task "fix the failing test"
mesh peek fix-bug -H dataflow -n 60    # recent pane output
mesh send fix-bug "run the tests" -H dataflow
mesh key  fix-bug enter -H dataflow    # approve a prompt waiting on a keypress
mesh usage -H dataflow                 # limits
mesh kill fix-bug -H dataflow
mesh status                            # every machine: version, uptime, doctor score
mesh upgrade                           # this machine, from the latest release
mesh upgrade -H dataflow               # a remote host — runs in its own tmux session, polls up to 3 min
mesh doctor                            # setup truth for THIS machine — see below
mesh token rotate                      # mint a new bearer token locally, proven before it reports success
```

`-H <name>` selects a host from `hosts.json`; omit it to use the configured default
(`mesh host default <name>`), else localhost. `mesh status` is how you spot a host that got
left behind on an old daemon — see `AGENTS.md` rule 6: an old daemon answers `200` with the
old response shape rather than refusing a new request, which is indistinguishable from the
feature being broken unless you check the version first.

## `/doctor` is setup truth

`GET /doctor` (or `mesh doctor`) is the one place that reports what a machine can *actually
do*, not just whether the process is up. Five checks, always present in this order:
**token, input, screen, mux, push**. `push` is the only one allowed to fail without failing
the machine overall — everything else failing means a real capability gap. Read this before
debugging any "why doesn't X work on this box" — it is faster than guessing from symptoms.

## Tokens — never print, never commit, never hardcode a fallback

Real tokens live in `~/.mesh/token` (0600) and `~/.mesh/hosts.json`. Read them into a shell
variable when a command needs one; never echo, log, or write one into a file, a doc, or a
commit. **There is no such thing as a shared default token any more** — a hardcoded
fallback used to exist, broke every host when the real tokens rotated, and is not written
down anywhere in this repo on purpose. If you find one written down somewhere (a script, a
transcript, a screenshot), that is a leak: `mesh token rotate` the same day.

```sh
mesh token rotate --yes             # local: mint, verify against itself, done
mesh token rotate -H dataflow       # remote: runs in its own tmux session, survives the restart
```

Rotation is one-directional and has no push-to-peers step — after rotating, every other
machine holding the old token gets locked out (401) and must re-pair or
`mesh host add <name> <ip> --token <new>` by hand.

## Restarting `meshd` — the sanctioned path, and why `kickstart -k` alone can lie to you

Use the `svc` skill (`svc status` / `svc restart meshd` / `svc logs meshd`) rather than an
ad hoc `pkill`. Under the hood, `meshd` runs as a LaunchAgent:

```sh
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/ai.lesearch.meshd.plist
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/ai.lesearch.rmux-bridge.plist
launchctl kickstart -k "gui/$(id -u)/ai.lesearch.meshd"     # quick restart, SAME env
```

**`launchctl kickstart -k` does not reload the plist's environment.** launchd caches
`EnvironmentVariables` from the moment the job was bootstrapped, so editing the plist (a
rotated token, a changed port) and then just kickstarting **silently keeps the old values**.
After any plist edit, use the heavier pair instead:

```sh
launchctl bootout "gui/$(id -u)/ai.lesearch.meshd"
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/ai.lesearch.meshd.plist
```

Before bootstrapping from a state where you're not sure the daemon is supervised at all,
confirm the plist's token actually matches `~/.mesh/token` (compare hashes — never print
either) — a mismatch there starts a daemon every client gets 401 from, and it's a harder
bug to spot than "meshd isn't running" because `/health` still answers.

## `lsof -i :PORT` matches BOTH ends — never sweep-kill by port

`lsof -i :PORT` returns anything talking on that port, listener or client. A script that
does `lsof -ti ":$port" | xargs kill -9` to "replace the server" kills the listener **and
every process with an open connection to it** — and `meshd` is a client of `rmux-bridge`
(its `/agents` route asks the bridge for sessions over a kept-alive connection). This has
happened for real: the old `cmux-bridge` starter did exactly this port sweep on `:8901`,
from a hook that runs on **every interactive zsh**, and it took `meshd` down as collateral
each time a terminal opened. `scripts/check-bridge-kill-scope.sh` now asserts nothing
shipped in the payload selects processes by unscoped port; when the intent is genuinely
"replace the server," scope the selector to the listening socket only:

```sh
lsof -ti "tcp:$port" -sTCP:LISTEN
```

Never widen that back to a bare `-ti :$port`, and never assume `kill -TERM` / a bare `kill`
is safe just because it isn't `-9` — the invariant that matters is the *selection*, not the
signal.

## tmux session names — never let a dot into one

tmux does two different things with a literal `.` in a session name, and both bite here:
it silently **rewrites `.` to `_` in the actual session name** it creates, and it
**reads `.` in a target string as `session:window.pane`**. A restart path once used the
session name `ai.lesearch-meshd`: the first `new-session` created `ai_lesearch-meshd` (dot
rewritten), and every later `kill-session -t ai.lesearch-meshd` parsed the dot as a pane
separator and answered `can't find pane: lesearch-meshd` — matching nothing. The practical
effect: `mesh upgrade` installed new files, silently failed to restart into them, and left
the **old** daemon serving, while `mesh version` (which reads files on disk, not the
running process) reported the new one as if the upgrade had worked.

Both `install/payload/bin/mesh` and `install/install.sh` strip dots from any session name
they hand to tmux now. If you add anything that spawns a tmux session by name — a new CLI
subcommand, a new install step — strip dots from that name too, and don't trust a
`kill-session -t` that contains one.
