#!/bin/sh
# The watch terminal was "clean but unusable" for one boring reason: meshd accepted
# fourteen keys, the phone sent thirteen, and the watch sent six. Nothing was broken —
# the capability simply was not wired to a button, which compiles green forever and is
# the same class of defect that already shipped twice in this repo.
#
# So this check compares the daemon's capabilities against what the clients actually
# reach, and pins the two other fixes that are invisible to a build: the watch's
# single-flight refresh, and a screen width that survives having no display named.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER="$ROOT/install/payload/meshd/server.ts"
WATCH_VIEWS="$ROOT/Watch/WatchViews.swift"
WATCH_STORE="$ROOT/Watch/WatchMeshStore.swift"
PHONE_TERM="$ROOT/iOS/TerminalView.swift"
CLIENT="$ROOT/Shared/MeshClient.swift"
MODELS="$ROOT/Shared/Models.swift"
fail=0

note() { echo "check-watch-terminal-wiring: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

# A file that greps as binary is skipped SILENTLY by grep -I, so every assertion below
# would pass vacuously. Refuse to run rather than lie. (server.ts really did carry raw
# NUL bytes once, which hid all 861 of its lines from every search.)
for f in "$SERVER" "$WATCH_VIEWS" "$WATCH_STORE" "$PHONE_TERM" "$CLIENT" "$MODELS"; do
  [ -f "$f" ] || { bad "missing $f"; continue; }
  if [ "$(grep -c . "$f" 2>/dev/null || echo 0)" = "0" ]; then
    bad "$f is being skipped by grep (binary?) — assertions would pass vacuously"
  fi
done
[ "$fail" = "0" ] || { echo "check-watch-terminal-wiring: FAILED"; exit 1; }

# ---- 1. every key the daemon accepts is reachable from the watch ----
# KEY_SEND_KEYS is the daemon's whole vocabulary; anything in it that no watch button
# sends is a key the wrist cannot press.
KEYS=$(awk '/^const KEY_SEND_KEYS/,/^};/' "$SERVER" \
       | sed -n 's/^[[:space:]]*"\{0,1\}\([a-z-]\{1,\}\)"\{0,1\}:[[:space:]]*".*",\{0,1\}$/\1/p')
[ -n "$KEYS" ] || bad "could not parse KEY_SEND_KEYS out of server.ts"

missing_watch=""
for k in $KEYS; do
  grep -q "send(key: \"$k\")" "$WATCH_VIEWS" || missing_watch="$missing_watch $k"
done
# ctrl-d aside, the delete key has no sensible wrist affordance; allow that one gap
# explicitly rather than pretending the set is complete.
allowed_gap=" delete"
if [ "$missing_watch" != "" ] && [ "$missing_watch" != "$allowed_gap" ]; then
  bad "watch cannot send:$missing_watch (meshd accepts them; wire them in terminalKeyBar)"
else
  note "watch reaches every key meshd accepts$( [ -n "$missing_watch" ] && echo " (except:$missing_watch, allowed)")"
fi

# ---- 2. a working directory can reach the daemon on BOTH routes ----
# Off the tailnet the phone runs the command, so a cwd that cannot be relayed is a
# workspace the watch cannot choose — which is what "open an agent inside a workspace"
# actually needs.
ok=1
grep -q "var cwd: String?" "$MODELS" \
  || { bad "WatchCommand has no cwd — the relay route cannot carry a working directory"; ok=0; }
grep -q "cwd: cwd" "$WATCH_STORE" \
  || { bad "WatchMeshStore.newSession does not forward cwd to MeshClient"; ok=0; }
grep -q "cwd: command.cwd" "$ROOT/iOS/MeshStore.swift" \
  || { bad "the phone's .newAgent relay handler drops cwd"; ok=0; }
[ "$ok" = "1" ] && note "cwd travels on the direct route and the phone relay"

# ---- 3. an arbitrary command can be launched from the watch ----
if grep -q "showCustom" "$WATCH_VIEWS"; then
  note "the watch can launch an arbitrary command"
else
  bad "the watch has no free-text command entry — herdr/tmux/anything is unreachable"
fi

# ---- 4. there is a help affordance ----
if grep -q "questionmark.circle" "$WATCH_VIEWS"; then
  note "the watch has a help affordance"
else
  bad "no '?' affordance on the watch — nothing tells the user what anything does"
fi

# ---- 5. screen width survives having no display named ----
# The client only names a display when a Mac has several, so a width that is honoured
# only alongside ?display= is a width that a single-display Mac can never use.
ok=1
awk '/func screenImage/,/^    }/' "$CLIENT" | grep -q 'guard let display else' \
  && { bad "MeshClient.screenImage still returns early without a display — width is dropped"; ok=0; }
awk '/func screenImage/,/^    }/' "$CLIENT" | grep -q 'width=' \
  || { bad "MeshClient.screenImage never sends a width"; ok=0; }
grep -q 'searchParams.get("width")' "$SERVER" \
  || { bad "the plain /screen.jpg route ignores &width"; ok=0; }
[ "$ok" = "1" ] && note "width reaches the daemon with or without a display"

# ---- 6. the watch's refresh is single flight ----
# adoptConfigs fires refresh() from inside pullFromPhone(), which runs inside refresh().
# Without a guard, reconnecting races three passes and the oldest one wins.
if awk '/func refresh\(\) async/,/async let phone/' "$WATCH_STORE" | grep -q "guard !refreshing"; then
  note "the watch's refresh is single flight"
else
  bad "WatchMeshStore.refresh() is not single flight — reconnect will flap again"
fi

if [ "$fail" = "0" ]; then
  echo "check-watch-terminal-wiring: OK"
else
  echo "check-watch-terminal-wiring: FAILED"
  exit 1
fi
