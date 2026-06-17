#!/usr/bin/env bash
# Deploy + start meshd on every mesh machine. Idempotent.
# Usage: MESHD_TOKEN=yourtoken ./deploy.sh
set -euo pipefail

TOKEN="${MESHD_TOKEN:?set MESHD_TOKEN to a strong shared secret}"
PORT="${MESHD_PORT:-8899}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# Your Tailscale hosts (ssh alias -> tailscale ip). Mac runs locally.
# Edit these for your own tailnet, or export them before running.
LINUX_HOSTS=(pi-ts dataflow)
declare -A IPS=( [pi-ts]=100.x.y.z [dataflow]=100.x.y.z )
MAC_IP=100.x.y.z

echo "== Mac (local) =="
pkill -f "meshd/server.ts" 2>/dev/null || true
( cd "$HERE" && MESHD_TOKEN="$TOKEN" MESHD_PORT="$PORT" nohup bun run server.ts >/tmp/meshd.log 2>&1 & )
sleep 1; echo "  http://$MAC_IP:$PORT  ($(curl -s -m3 localhost:$PORT/health >/dev/null && echo up || echo DOWN))"

for h in "${LINUX_HOSTS[@]}"; do
  echo "== $h =="
  ssh -o ConnectTimeout=8 "$h" 'command -v ~/.bun/bin/bun >/dev/null || (curl -fsSL https://bun.sh/install -o /tmp/bun.sh && bash /tmp/bun.sh)' 2>/dev/null || true
  ssh -o ConnectTimeout=8 "$h" 'mkdir -p ~/meshd'
  scp -q "$HERE/server.ts" "$HERE/package.json" "$HERE/mesh-self-check" "$h":~/meshd/
  ssh -o ConnectTimeout=8 "$h" "tmux kill-session -t meshd 2>/dev/null || true; \
    tmux new-session -d -s meshd 'cd ~/meshd && MESHD_TOKEN=$TOKEN MESHD_PORT=$PORT ~/.bun/bin/bun run server.ts 2>&1 | tee ~/meshd/meshd.log'"
  sleep 2
  echo "  http://${IPS[$h]}:$PORT  ($(curl -s -m5 -H "Authorization: Bearer $TOKEN" http://${IPS[$h]}:$PORT/health >/dev/null && echo up || echo DOWN))"
done
echo "Done. Point the MeshWatch iPhone app's machine tokens at: $TOKEN"
