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

- **Upgrade to latest:** `mesh upgrade` (see below). The raw
  `curl … | sh -s -- --upgrade` still works and preserves the token, but it is the blunt
  version: it reinstalls without ever proving the new daemon boots.
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

## Keeping the fleet current

```sh
mesh status                                # every machine: version, uptime, doctor score
mesh upgrade                               # this machine, from the latest release
mesh upgrade --src ~/Projects/lecoder-watch/install   # from a checkout (unreleased build)
mesh upgrade -H dataflow                   # a remote host, and wait for it to flip
```
`mesh status` is how you spot a host left behind. `mesh upgrade` stages the new payload,
boots it on a scratch port and makes it report its own version *before* anything moves,
swaps by rename, restarts the real service, and rolls back to the previous meshd if the
restarted daemon does not come up. Token, `hosts.json`, push tokens, KB and event log are
never touched. `-H` runs the installer in the host's own tmux session (so it survives the
restart it causes) and polls for up to 3 minutes.

## Notes
- `testtoken` is the dogfood token on the private tailnet; rotate with `--token <new>` + update the app/CLI host if you want a stronger one.
- For a Linux remote, cmux/cmux-bridge is inert (macOS-only); it installs meshd core + rmux-bridge + tools.
- "Latest only": the serve script repackages this checkout each run; `mesh upgrade -H <host>` (or `--upgrade`) on any host pulls it. One source of truth.
- On Linux, `systemctl --user enable --now` is a no-op on an already-running unit, so upgrades used to copy files and leave the old daemon serving from memory. `install.sh` now restarts explicitly, and `mesh status` shows you the version each host is actually running.
