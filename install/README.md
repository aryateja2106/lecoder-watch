# Mesh Installer

One command to install or uninstall the mesh stack (meshd, rmux-bridge, agent
hook tools) on any macOS or Linux machine. Detects OS, architecture, and
multiplexer; nothing is hardcoded.

## Install (single curl command)

Once `install.sh` + `mesh-install.tgz` are hosted together (see Hosting):

```sh
curl -fsSL <host>/install.sh | sh
curl -fsSL <host>/install.sh | sh -s -- --only meshd --token MYTOKEN
```

Or point at the payload explicitly — no hosting setup needed:

```sh
curl -fsSL <host>/install.sh | sh -s -- --src <host>/mesh-install.tgz
sh install.sh --src /path/to/mesh-install.tgz   # from a local tarball
sh install.sh                                   # from a repo checkout (uses ./payload)
```

## Options

| Flag | Purpose |
| --- | --- |
| `--token V` | meshd auth token (default: `$MESHD_TOKEN` or generated) |
| `--src SRC` | payload base URL, direct `.tgz` URL, or local tarball path |
| `--only LIST` | install only these components (`meshd,bridge,tools`) |
| `--without LIST` | install all except these |
| `--prefix DIR` | install location (default `~/.mesh`) |
| `--no-start` | install without launching services |
| `--list` | show what is installed under the prefix |
| `--uninstall` (`--purge`) | stop + remove components; `--purge` also drops the token + prefix |

Components: **meshd** (`:8899`), **bridge** (`:7820`), **tools** (hook helpers).

## Hosting (build the single-curl bundle)

```sh
sh scripts/package-mesh-install.sh /out/mesh-install.tgz https://<host>/dl
```

This writes `mesh-install.tgz` and a standalone `install.sh` with the source URL
baked in. Host both at `https://<host>/dl/` and share:

```sh
curl -fsSL https://<host>/dl/install.sh | sh
```

Privacy-first option: serve `/dl` from a machine already on your Tailscale mesh,
so new nodes install over the tailnet with no public host.

What gets installed:

- `~/.mesh/meshd` and `~/.mesh/rmux-bridge` copied from `payload/`
- `~/.mesh/bin/mesh-event` for Claude/Codex/Pi hooks to notify the phone/watch
- `~/.mesh/bin/mesh-hook` for hook systems that pass JSON on stdin
- `~/.mesh/bin/mesh-agent-run` to wrap interactive agents with start/done/fail events
- `~/.mesh/bin/mesh-codex-notify` for Codex `notify = [...]` chaining
- `~/.mesh/bin/mesh-self-check` to verify `meshd`, sessions, events, Tailnet, terminal bridge, and hook posting
- `~/.mesh/hooks/` examples for Claude hooks, Codex notify, and agent wrappers
- `~/.mesh/token` saved for local hook helpers
- A **reboot-persistent service** per OS that supervises `meshd` and `rmux-bridge`:
  launchd agent on macOS (`~/Library/LaunchAgents/ai.lesearch.{meshd,rmux-bridge}.plist`),
  systemd `--user` unit on Linux/WSL (`~/.config/systemd/user/ai.lesearch-*.service`,
  with `loginctl enable-linger` so it runs headless), or a detached `tmux` session
  where neither exists. Services restart on crash and come back after reboot.
- HTTP services on `8899` (`meshd`) and `7820` (`rmux-bridge`) by default

Update an existing machine by running the installer again with the same token.
This reinstalls the service with the current payload and restarts it.

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
| `MESH_SERVICE` | Force supervisor: `launchd`, `systemd`, or `tmux` (default: auto-detect) |
| `MESH_LABEL_PREFIX` | Service label/unit base name (default `ai.lesearch`) |

Uninstall:

```sh
sh install.sh --uninstall            # stop services + remove components, keep token
sh install.sh --uninstall --purge    # also remove the token and the whole prefix
sh install.sh --only tools --uninstall   # remove just one component
```
