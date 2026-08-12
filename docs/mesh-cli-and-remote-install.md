# mesh CLI + one-curl remote install (2026-07-07)

Add any tailnet machine to the mesh with one curl, drive it from the shell, upgrade/remove cleanly.

## Add a new host (on the target machine)

The public one-liner — nothing needs to be running on your Mac for this to work:

```sh
curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh | sh
```

Over SSH, when no sudo prompt is needed:
```sh
ssh <user>@<host-ip> 'curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh | sh'
```

Installs meshd + rmux-bridge + tools + the `mesh` CLI under `~/.mesh`, starts meshd
(systemd --user on Linux, launchd on macOS), and **prints a generated token**. Copy
the whole summary block and use **Paste installer output** in the iPhone app — it
extracts the address and token for you.

- **Upgrade to latest:** append `-s -- --upgrade` (token preserved)
- **Uninstall:** append `-s -- --uninstall --purge`
- **Pin a token the phone already has:** append `-s -- --token <token>`

Set `MESH_FALLBACK_SRC` to install from a fork or a private mirror instead.

## Serve the installer yourself (dev / air-gapped)

For testing an unreleased working tree, or a tailnet with no GitHub access:

```sh
sh scripts/serve-installer.sh          # repackages this checkout + serves on tailnet :8890
```
Prints a tailscale URL; install with `--src <that-url>`. This only lives as long as
the script runs, so it is a development convenience, not the install story.

## mesh CLI

Config: `~/.mesh/hosts.json`. `mesh --help`, `mesh help <cmd>`, `mesh man`. `--json` for agents.

```sh
mesh host add dataflow 100.80.10.95        # register a host (uses this machine's ~/.mesh/token unless --token)
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
- The installer generates a per-machine token (`openssl rand -hex 16`) into `~/.mesh/token` and preserves it across upgrades. `mesh host add` reads that file, so there is no shared literal to leak. Rotate with `--token <new>` and update the app's host entry.
- `testtoken` remains only on the maintainer's dogfood fleet (Settings ▸ Developer ▸ Load dogfood fleet). It is not a default anywhere in the app or the CLI.
- For a Linux remote, cmux/cmux-bridge is inert (macOS-only); it installs meshd core + rmux-bridge + tools.
- "Latest only": the serve script repackages this checkout each run; `--upgrade` on any host pulls it. One source of truth.
