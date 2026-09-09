# Run meshd with Docker

Docker is an alternative to the curl installer for **Linux hosts and VPS boxes** —
a headless daemon only. The iPhone, Apple Watch, and Mac menu-bar apps are not
containerized; they still pair to `meshd` over your LAN or VPN.

## What you get

Same HTTP API as a bare-metal install: stats, terminal sessions (tmux inside the
container), agent events, pairing, and push registration. Honest limits still apply:

- **No screen capture on Linux** — same as the curl install; `/health` advertises
  what the daemon can actually do.
- **No desktop input inside a default container** — keyboard/mouse via `xdotool`
  needs an X11 display on the host; a plain Docker box is for terminal + alerts,
  not remote GUI control.
- **Your phone must reach the host** — bind `8899` on a network you trust
  (Tailscale, a private VPC, your LAN). There is no cloud relay.

## Network checklist (read before exposing a port)

meshd is **plain HTTP with a bearer token** — security is the token plus Host/Origin
gates, not TLS. The trust model is a home LAN or Tailscale tailnet, not the public
internet.

| Check | Why |
| --- | --- |
| **Prefer Tailscale** | Install Tailscale on the host; pair with the machine's `100.x` address. Your phone never needs a public IP open. |
| **Docker publish defaults to loopback** | `docker compose` maps `127.0.0.1:8899` on the host unless you set `MESHD_PUBLISH=0.0.0.0`. A VPS public IP with `0.0.0.0:8899` is **not** the same as Tailscale — anyone who can reach that port can attempt auth. |
| **Firewall when publishing publicly** | If you must expose a port on `0.0.0.0`, restrict source IPs in your cloud firewall or `ufw` to your tailnet or office CIDR. meshd has no rate limiting on `/pair/claim`. |
| **Never reverse-proxy to loopback without Bearer** | If nginx or Caddy on the same host proxies to `127.0.0.1:8899`, meshd sees a loopback peer and may skip the bearer token. Terminate TLS in front of meshd only with Bearer required, or proxy to a non-loopback bind. |
| **`MESHD_TRUST_LOOPBACK=0`** | Disables the loopback bearer exemption entirely — use when a local proxy makes loopback peers untrustworthy. Pairing still mints codes from the real socket peer inside the container. |

## Quick start

From a checkout of this repo (or after cloning):

```sh
docker compose up -d --build
curl -fsS http://127.0.0.1:8899/health | python3 -m json.tool
```

The entrypoint persists state under a Docker volume at `/data/.mesh` (token,
`hosts.json`, knowledge base, push tokens, event log). On first boot it mints a
bearer token when `MESHD_TOKEN` is not set.

The image is Debian bookworm-slim with the bun binary copied in (not Alpine)
and runs as uid **1000** (`mesh`), not root.
A named volume created by compose inherits that ownership. If you bind-mount a
host directory onto `/data`, it must be writable by uid 1000. Compose also
limits the container to 256&nbsp;MB of RAM and half a CPU — enough for the daemon
and a few tmux sessions, not a compile farm.

`meshd` writes to `homedir()/.mesh` and **ignores `MESH_HOME`**. The image sets
`HOME=/data` so that path is `/data/.mesh` on the volume. Keep `HOME=/data` if
you override environment.

Terminal sessions live in tmux inside the container and **do not survive**
`docker compose restart`. Token, hosts, and the knowledge base do.

### Publishing on all host interfaces

Default compose binds the host side to loopback only. To publish on every interface
(for example so a phone on the same LAN can reach the host's Ethernet IP):

```sh
MESHD_PUBLISH=0.0.0.0 docker compose up -d
```

On bare metal (curl install), `MESHD_HOST` still defaults to `0.0.0.0` so phones on
the LAN keep working; meshd logs a startup warning unless you set `MESHD_PUBLISH=0.0.0.0`
to acknowledge intentional exposure.

## Pair your phone

Pairing still uses the same eight-character code and QR as `mesh pair` on a normal
install. Run it **inside** the running container:

```sh
docker compose exec meshd mesh pair --address <tailscale-or-lan-ip>
```

Use an address your iPhone can actually reach — a Tailscale IP, the VPS public IP
(only if you have put the host on a trusted network and restricted the firewall),
or the machine's LAN address. Scan the QR with the Camera app, or enter the address
and code in LeSearch Mesh.

`mesh pair` talks to meshd on loopback inside the container; no token is needed for
that step.

## Environment

| Variable | Default | Purpose |
| --- | --- | --- |
| `MESHD_PORT` | `8899` | Host port mapped to the container (compose file) |
| `MESHD_PUBLISH` | `127.0.0.1` (compose) | Host bind address for the published port; set to `0.0.0.0` to expose on all interfaces |
| `MESHD_HOST` | `0.0.0.0` | Bind address inside the container |
| `MESHD_TOKEN` | *(minted on first boot)* | Bearer token; persisted to the volume when set |
| `MESHD_TRUST_LOOPBACK` | `1` | Set to `0` to require Bearer even from loopback peers |
| `MESHD_TELEMETRY` | `on` | Set to `off` to disable the daily anonymized heartbeat |
| `MESH_MUX` | `tmux` | Multiplexer binary inside the container |
| `MESHD_CONTAINER` | `1` (set by the image) | Marks a container so `/health` does not advertise screen peek or desktop input |

See the README [Telemetry](../README.md#telemetry) section for what the heartbeat
contains.

`/health` advertises only what works in this environment: no `screenPeek` or `input`
in a default container (no X11 display, no macOS screen capture). Terminal sessions,
events, pairing, and files still work.

## Uninstall

```sh
docker compose down -v
```

That stops the container and deletes the `mesh-data` volume (token, paired hosts,
and local state). It does not remove images you built locally; `docker image rm
meshd:local` if you want those gone too.

The phone app keeps its entry for this machine until you remove it there — same as
`mesh uninstall` on a bare install.

## Maintainer smoke test

```sh
sh scripts/check-docker-meshd.sh
```

Builds the image, starts a throwaway container on a spare port, waits until
`/health` answers, and tears down. Skips when Docker is not available.
