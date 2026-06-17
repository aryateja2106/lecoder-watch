# Mesh Installer

Serve `install.sh` next to the vendored `payload/` directory, then run:

```sh
curl -fsSL <host>/install.sh -o /tmp/mesh-install.sh && sh /tmp/mesh-install.sh --token MYTOKEN
```

Package the installer from this repo:

```sh
sh scripts/package-mesh-install.sh /tmp/mesh-install.tgz
```

What gets installed:

- `~/.mesh/meshd` and `~/.mesh/rmux-bridge` copied from `payload/`
- `~/.mesh/bin/mesh-event` for Claude/Codex/Pi hooks to notify the phone/watch
- `~/.mesh/bin/mesh-hook` for hook systems that pass JSON on stdin
- `~/.mesh/bin/mesh-agent-run` to wrap interactive agents with start/done/fail events
- `~/.mesh/bin/mesh-codex-notify` for Codex `notify = [...]` chaining
- `~/.mesh/bin/mesh-self-check` to verify `meshd`, sessions, events, Tailnet, terminal bridge, and hook posting
- `~/.mesh/hooks/` examples for Claude hooks, Codex notify, and agent wrappers
- `~/.mesh/token` saved for local hook helpers
- Two detached `tmux` sessions: `meshd` and `rmux-bridge`
- HTTP services on `8899` (`meshd`) and `7820` (`rmux-bridge`) by default

Update an existing machine by running the installer again with the same token.
This restarts both `tmux` service sessions with the current payload.

Hook smoke test after install:

```sh
~/.mesh/bin/mesh-event codex "Needs input" "Check the active terminal"
printf '{"hook_event_name":"Stop","message":"session done"}' | ~/.mesh/bin/mesh-hook --source claude
printf '{"title":"Codex waiting","body":"approval requested"}' | ~/.mesh/bin/mesh-hook --source codex
~/.mesh/bin/mesh-agent-run codex codex
~/.mesh/bin/mesh-agent-run claude claude
~/.mesh/bin/mesh-self-check
```

Check hook parsing without posting:

```sh
~/.mesh/bin/mesh-event --dry-run pi "Thermal warning" "hot"
~/.mesh/bin/mesh-codex-notify --dry-run turn-ended
~/.mesh/bin/mesh-agent-run --dry-run claude claude
printf '{"hook_event_name":"Notification","message":"needs input"}' | ~/.mesh/bin/mesh-hook --source claude --dry-run
printf '{"event":"turn-ended","title":"Codex waiting"}' | ~/.mesh/bin/mesh-hook --source codex --dry-run
```

`mesh-self-check` treats `meshd`, `/agents`, `/events`, `/tailnet`, `rmux-bridge`, and hook posting as required. VNC is reported separately as `active` or `not configured`; set `MESH_VNC_URL` if your noVNC endpoint is not `http://127.0.0.1:6080/vnc.html`.

Hook examples are copied to `~/.mesh/hooks/` during install.

Codex notify example:

```toml
notify = ["/Users/you/.mesh/bin/mesh-codex-notify", "/path/to/existing/notify-command", "turn-ended"]
```

Environment variables:

| Variable | Purpose |
| --- | --- |
| `MESHD_TOKEN` | Auth token for `meshd` when `--token` is not passed |
| `MESHD_PORT` | `meshd` listen port (default `8899`) |
| `MESHD_HOST` | `meshd` bind host (default `0.0.0.0`; use `127.0.0.1` for simulator-only dogfood) |
| `PORT` | `rmux-bridge` listen port (default `7820`) |
| `BRIDGE_HOST` | `rmux-bridge` bind host (default `0.0.0.0`) |
| `MESH_MUX` | Override the mux binary used inside `meshd` |
| `MUX` | Override the mux binary used inside `rmux-bridge` |
| `MESH_HOME` | Install location (default `~/.mesh`) |

Uninstall:

```sh
sh install.sh --uninstall
```
