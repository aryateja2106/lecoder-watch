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

## Quick start

From a checkout of this repo (or after cloning):

```sh
docker compose up -d --build
curl -fsS http://127.0.0.1:8899/health | python3 -m json.tool
```

The entrypoint persists state under a Docker volume at `/data/.mesh` (token,
`hosts.json`, knowledge base, push tokens, event log). On first boot it mints a
bearer token when `MESHD_TOKEN` is not set.

## Pair your phone

Pairing still uses the same eight-character code and QR as `mesh pair` on a normal
install. Run it **inside** the running container:

```sh
docker compose exec meshd mesh pair --address <tailscale-or-lan-ip>
```

Use an address your iPhone can actually reach — a Tailscale IP, the VPS public IP
(if you have put the host on a trusted network), or the machine's LAN address. Scan
the QR with the Camera app, or enter the address and code in LeSearch Mesh.

`mesh pair` talks to meshd on loopback inside the container; no token is needed for
that step.

## Environment

| Variable | Default | Purpose |
| --- | --- | --- |
| `MESHD_PORT` | `8899` | Host port mapped to the container (compose file) |
| `MESHD_HOST` | `0.0.0.0` | Bind address inside the container |
| `MESHD_TOKEN` | *(minted on first boot)* | Bearer token; persisted to the volume when set |
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

Builds the image, starts a throwaway container on a spare port, hits `/health`, and
tears it down.

## Multi-architecture images

The Dockerfile targets `linux/amd64` and `linux/arm64` via Buildx:

```sh
docker buildx build --platform linux/amd64,linux/arm64 -t your-registry/meshd:latest --push .
```

## curl installer still works

Nothing here replaces `curl -fsSL https://mesh.lesearch.ai/install.sh | sh`. Use
Docker when you already run containers, want an isolated VPS daemon, or prefer
`compose up` over systemd user units.
