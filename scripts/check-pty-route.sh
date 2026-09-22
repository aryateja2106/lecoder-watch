#!/bin/sh
# The phone's native terminal streams a session's bytes over GET /agents/:name/pty
# (WebSocket, install/payload/meshd/pty.ts). A polled capture-pane can look right while
# the stream is dead, so this drives the route for real against a throwaway daemon:
#   - the upgrade needs the bearer (401 without it, 404 for a session that is not there)
#   - the attach is sized to the client: `stty size` inside the pane echoes rows cols
#   - typed bytes reach the pane and its output (with SGR colour) comes back
#   - a resize message reaches the mux (SIGWINCH), so the pane really changes size
#   - the pane's scrollback is replayed before the attach draws the screen
#   - closing the socket detaches; the session is still there afterwards
# Everything is throwaway: meshd on :8895 with HOME in a temp dir, tmux on a private
# socket with no user config. The real daemon, tmux server and ~/.mesh are never touched.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-pty-route: SKIP (no bun)"; exit 0; }
command -v tmux >/dev/null 2>&1 || { echo "check-pty-route: SKIP (no tmux)"; exit 0; }
bun -e 'if (!("Terminal" in Bun)) process.exit(3)' || { echo "check-pty-route: SKIP (this bun has no Bun.Terminal)"; exit 0; }

PORT=8895
if curl -sf -o /dev/null --max-time 2 "http://127.0.0.1:$PORT/health" 2>/dev/null; then
  echo "check-pty-route: SKIP (something already listens on :$PORT — not killing it)"
  exit 0
fi

TMP="$(mktemp -d)"
SOCK="mesh-pty-$$"
DAEMON_PID=""
cleanup() {
  if [ -n "$DAEMON_PID" ]; then kill "$DAEMON_PID" 2>/dev/null || true; wait "$DAEMON_PID" 2>/dev/null || true; fi
  tmux -L "$SOCK" kill-server 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

mkdir -p "$TMP/.mesh"
head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$TMP/.mesh/token"
chmod 600 "$TMP/.mesh/token"

# Private tmux server, no user config, no login shell (see check-daemon-050.sh for why).
tmux -L "$SOCK" -f /dev/null new-session -d -s mesh-boot "exec cat"
tmux -L "$SOCK" set-option -g default-shell /bin/sh \; set-option -g default-command 'exec /bin/sh'
tmux -L "$SOCK" new-session -d -s pty-probe -x 80 -y 24
# Fill the pane's scrollback so the attach has history to replay: 60 lines on a 24-row
# pane leaves HISTMARK-1 well above the visible screen.
tmux -L "$SOCK" send-keys -t pty-probe 'i=1; while [ $i -le 60 ]; do echo HISTMARK-$i; i=$((i+1)); done' Enter
sleep 0.5

MESHD_TOKEN="$(cat "$TMP/.mesh/token")" \
HOME="$TMP" MESHD_HOST=127.0.0.1 MESHD_PORT="$PORT" \
MESHD_EVENTS_PATH="$TMP/events.jsonl" MESH_MUX="tmux -L $SOCK" \
MESHD_TELEMETRY=off MESHD_TRUST_LOOPBACK=0 \
  bun "$ROOT/install/payload/meshd/server.ts" >"$TMP/meshd.log" 2>&1 &
DAEMON_PID=$!
i=0
until curl -sf -o /dev/null "http://127.0.0.1:$PORT/health" 2>/dev/null; do
  i=$((i+1)); [ $i -lt 50 ] || { echo "FAIL: meshd never came up"; cat "$TMP/meshd.log"; exit 1; }
  sleep 0.2
done

# The client half runs in bun: a WebSocket with the bearer on the upgrade, exactly as
# the phone does it. Prints one line per assertion; the token never appears.
MESHD_TOKEN="$(cat "$TMP/.mesh/token")" PORT="$PORT" SOCK="$SOCK" bun -e '
const port = process.env.PORT, token = process.env.MESHD_TOKEN, sock = process.env.SOCK;
const fail = (m) => { console.log("FAIL: " + m); process.exit(1); };
const tmux = (...a) => Bun.spawnSync(["tmux", "-L", sock, ...a]).stdout.toString().trim();

let r = await fetch(`http://127.0.0.1:${port}/agents/pty-probe/pty`, { headers: { Upgrade: "websocket", Connection: "Upgrade", "Sec-WebSocket-Key": "x", "Sec-WebSocket-Version": "13" } });
if (r.status !== 401) fail(`tokenless upgrade answered ${r.status}, want 401`);
console.log("ok: upgrade without bearer is 401");
r = await fetch(`http://127.0.0.1:${port}/agents/no-such-session/pty`, { headers: { authorization: `Bearer ${token}` } });
if (r.status !== 404) fail(`unknown session answered ${r.status}, want 404`);
console.log("ok: unknown session is 404");

const chunks = [];
const ws = new WebSocket(`ws://127.0.0.1:${port}/agents/pty-probe/pty?cols=61&rows=17`, { headers: { authorization: `Bearer ${token}` } });
ws.binaryType = "arraybuffer";
const control = [];
ws.onmessage = (e) => { if (typeof e.data === "string") control.push(JSON.parse(e.data)); else chunks.push(new Uint8Array(e.data)); };
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error("socket error")); setTimeout(() => rej(new Error("open timeout")), 5000); });
console.log("ok: socket open with bearer");
const text = () => new TextDecoder().decode(Buffer.concat(chunks));
const waitFor = async (pred, what) => { for (let i = 0; i < 50; i++) { if (pred()) return; await Bun.sleep(100); } fail(`timed out waiting for ${what}; last bytes: ${JSON.stringify(text().slice(-300))}`); };

await Bun.sleep(400);
await waitFor(() => text().includes("HISTMARK-1\u001b[0m\r\n"), "scrollback replay (HISTMARK-1 is above the visible screen)");
console.log("ok: scrollback replayed before the attach");
ws.send(new TextEncoder().encode("stty size; printf \"\\033[31mPTYRED\\033[0m\\n\"\r"));
// tmux keeps one row for its status line: a 17-row client is a 16-row pane.
await waitFor(() => /16 61/.test(text()), "stty size 16 61 (got: " + JSON.stringify(text().slice(-200)) + ")");
console.log("ok: pane sized to the client (16x61 under the status line) and typed bytes reached it");
await waitFor(() => text().includes("[31mPTYRED"), "SGR colour bytes");
console.log("ok: colour escapes come back unstripped");

ws.send(JSON.stringify({ t: "resize", cols: 45, rows: 12 }));
await waitFor(() => tmux("display-message", "-p", "-t", "pty-probe", "#{pane_width}") === "45", "pane width 45 after resize");
console.log("ok: resize reaches tmux (pane now " + tmux("display-message", "-p", "-t", "pty-probe", "#{pane_width}x#{pane_height}") + ")");

ws.send(JSON.stringify({ t: "ping" }));
await waitFor(() => control.some((m) => m.t === "pong"), "pong");
console.log("ok: ping answered");

ws.close();
await Bun.sleep(400);
if (tmux("has-session", "-t", "pty-probe") !== "" && Bun.spawnSync(["tmux", "-L", sock, "has-session", "-t", "pty-probe"]).exitCode !== 0) fail("closing the socket killed the session");
if (tmux("list-clients", "-t", "pty-probe") !== "") fail("client still attached after close: " + tmux("list-clients"));
console.log("ok: close detaches, session survives");
process.exit(0);
' || { echo "check-pty-route: FAILED"; tail -5 "$TMP/meshd.log"; exit 1; }

grep -q '"pty"' "$ROOT/install/payload/meshd/server.ts" || { echo "FAIL: pty capability not advertised"; exit 1; }
echo "check-pty-route: ok"
