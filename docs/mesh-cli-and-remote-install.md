# mesh CLI + one-curl remote install (2026-07-07)

Add any tailnet machine to the mesh with one curl, drive it from the shell, upgrade/remove cleanly.

## Serve the installer (on the Mac, always-latest)

```sh
sh scripts/serve-installer.sh          # repackages this checkout + serves on tailnet :8890
```
Prints the Mac's tailscale URL (e.g. `http://100.94.221.115:8890`). Re-run any time to publish the latest.
For always-on, wrap it in a launchd service (LaunchAgent running `serve-installer.sh`).

## Add a new host (on the target machine)

Connect, then one curl:
```sh
ssh <user>@<host-ip>
curl -fsSL http://100.94.221.115:8890/install.sh | sh -s -- --token testtoken
```
Or one line (works when no sudo prompt is needed):
```sh
ssh <user>@<host-ip> 'curl -fsSL http://100.94.221.115:8890/install.sh | sh -s -- --token testtoken'
```
Installs meshd + rmux-bridge + tools + the `mesh` CLI under `~/.mesh`, starts meshd
(systemd --user on Linux, launchd on macOS). If it reports tmux missing:
`sudo apt install -y tmux` then re-run with `--upgrade`.

- **Upgrade to latest:** `curl -fsSL http://100.94.221.115:8890/install.sh | sh -s -- --upgrade` (token preserved)
- **Uninstall:** `curl -fsSL http://100.94.221.115:8890/install.sh | sh -s -- --uninstall --purge`

Then add it in the app (Settings → add machine: ip, port 8899, token testtoken) or the CLI below.

## mesh CLI

Config: `~/.mesh/hosts.json`. `mesh --help`, `mesh help <cmd>`, `mesh man`. `--json` for agents.

```sh
mesh host add dataflow 100.80.10.95        # register a host (default port 8899, token testtoken)
mesh hosts                                 # list hosts + reachability
mesh ls -H dataflow                        # sessions on that host
mesh new fix-bug -H dataflow --cmd claude --task "fix the failing test"
mesh peek fix-bug -H dataflow -n 60        # recent output
mesh send fix-bug "run the tests" -H dataflow
mesh key  fix-bug enter -H dataflow        # approve a prompt
mesh usage -H dataflow                     # limits
mesh kill fix-bug -H dataflow
```
`-H` selects the host; omit it to use the default (`mesh host default <name>`), else localhost.

## Notes
- `testtoken` is the dogfood token on the private tailnet; rotate with `--token <new>` + update the app/CLI host if you want a stronger one.
- For a Linux remote, cmux/cmux-bridge is inert (macOS-only); it installs meshd core + rmux-bridge + tools.
- "Latest only": the serve script repackages this checkout each run; `--upgrade` on any host pulls it. One source of truth.
