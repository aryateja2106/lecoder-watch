# Mesh Installer

Serve `install.sh` next to the vendored `payload/` directory, then run:

```sh
curl -fsSL <host>/install.sh -o /tmp/mesh-install.sh && sh /tmp/mesh-install.sh --token MYTOKEN
```

What gets installed:

- `~/.mesh/meshd` and `~/.mesh/rmux-bridge` copied from `payload/`
- Two detached `tmux` sessions: `meshd` and `rmux-bridge`
- HTTP services on `8899` (`meshd`) and `7820` (`rmux-bridge`) by default

Environment variables:

| Variable | Purpose |
| --- | --- |
| `MESHD_TOKEN` | Auth token for `meshd` when `--token` is not passed |
| `MESHD_PORT` | `meshd` listen port (default `8899`) |
| `PORT` | `rmux-bridge` listen port (default `7820`) |
| `BRIDGE_HOST` | `rmux-bridge` bind host (default `0.0.0.0`) |
| `MESH_MUX` | Override the mux binary used inside `meshd` |
| `MUX` | Override the mux binary used inside `rmux-bridge` |
| `MESH_HOME` | Install location (default `~/.mesh`) |

Uninstall:

```sh
sh install.sh --uninstall
```
