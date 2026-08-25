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
# Since 0.5.0 the /screen.jpg route (and its one param parser) lives in input.ts —
# handleInput claims the path before any server.ts route matches it.
INPUT="$ROOT/install/payload/meshd/input.ts"
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
for f in "$SERVER" "$INPUT" "$WATCH_VIEWS" "$WATCH_STORE" "$PHONE_TERM" "$CLIENT" "$MODELS"; do
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
grep -q 'sp.get("width")' "$INPUT" \
  || { bad "the plain /screen.jpg route ignores &width"; ok=0; }
# The width must be parsed by the ONE parser both routes share, not re-derived per
# route — a second copy is how the region and full-frame paths disagreed before.
awk '/function parseCaptureParams/,/^}/' "$INPUT" | grep -q 'sp.get("width")' \
  || { bad "&width is not read by the shared /screen.jpg param parser"; ok=0; }
[ "$ok" = "1" ] && note "width reaches the daemon with or without a display"

# ---- 6. the watch's refresh is single flight ----
# adoptConfigs fires refresh() from inside pullFromPhone(), which runs inside refresh().
# Without a guard, reconnecting races three passes and the oldest one wins.
if awk '/func refresh\(\) async/,/async let phone/' "$WATCH_STORE" | grep -q "guard !refreshing"; then
  note "the watch's refresh is single flight"
else
  bad "WatchMeshStore.refresh() is not single flight — reconnect will flap again"
fi

# ---- 7. dictation opens the microphone, and picks its controller at TAP time ----
# The whole defect class here is invisible to a build: the button compiles, renders and
# taps, it just opens Scribble (or nothing). Two separate things have to hold.
#
#   a) nil suggestions + .plain is the ONLY call that goes straight to the mic.
#      WatchKit says so in its own header, on the sibling overload: "will never go
#      straight to dictation because allows for switching input language".
#   b) the controller is resolved inside the action. `body` runs while the sheet
#      holding the button is still presenting, when visibleInterfaceController is nil —
#      so branching on it there froze the button into the TextFieldLink picker for the
#      life of that sheet, which is exactly the reported "it still expects me to
#      scribble".
WATCH_LINK="$ROOT/Watch/WatchLink.swift"
WATCH_NOTIFS="$ROOT/Watch/WatchNotifications.swift"
WATCH_REMOTE="$ROOT/Watch/RemoteView.swift"
for f in "$WATCH_LINK" "$WATCH_NOTIFS" "$WATCH_REMOTE"; do
  [ -f "$f" ] || bad "missing $f"
done

DICT="$(awk '/^struct DictateLink/,/^}/' "$WATCH_VIEWS")"
ok=1
[ -n "$DICT" ] || { bad "could not find struct DictateLink in WatchViews.swift"; ok=0; }
printf '%s\n' "$DICT" | grep -q 'presentTextInputController(withSuggestions: nil' \
  || { bad "DictateLink does not pass nil suggestions — watchOS opens the input picker, not the mic"; ok=0; }
printf '%s\n' "$DICT" | grep -q 'allowedInputMode: .plain' \
  || { bad "DictateLink does not request .plain input mode"; ok=0; }
if printf '%s\n' "$DICT" | awk '/var body: some View/,/^    }/' | grep -q 'InterfaceController'; then
  bad "DictateLink resolves an interface controller in body — resolve it inside the action, or the button freezes into the picker"
  ok=0
fi
DICT_ACTION="$(printf '%s\n' "$DICT" | awk '/private func dictate\(\)/,/^    }/')"
printf '%s\n' "$DICT_ACTION" | grep -q 'visibleInterfaceController' \
  || { bad "DictateLink.dictate() never asks for visibleInterfaceController at tap time"; ok=0; }
printf '%s\n' "$DICT_ACTION" | grep -q 'rootInterfaceController' \
  || { bad "DictateLink.dictate() has no fallback controller — a nil visible controller makes the button dead"; ok=0; }
printf '%s\n' "$DICT_ACTION" | grep -q 'play(.failure)' \
  || { bad "DictateLink.dictate() can return without speech and without a haptic — a silent tap reads as broken"; ok=0; }
[ "$ok" = "1" ] && note "dictation goes to the mic and resolves its controller at tap time"

# ---- 8. the terminal has both a wrapping and a non-wrapping view ----
# Wrapping is right for prose and wrong for diffs/tables; one view cannot serve both on
# a 21-column screen. Reader additionally asks the daemon to un-wrap and de-glyph, but
# ONLY when it advertises captureJoin — an old daemon must still get today's request.
ok=1
grep -q 'store.readerOutput.toggle()' "$WATCH_VIEWS" \
  || { bad "no Raw/Reader toggle in the watch terminal"; ok=0; }
grep -q 'ScrollView(\[.horizontal, .vertical\])' "$WATCH_VIEWS" \
  || { bad "the Raw view does not scroll in both axes — a long line cannot be reached"; ok=0; }
grep -q 'fixedSize(horizontal: true, vertical: true)' "$WATCH_VIEWS" \
  || { bad "the Raw view still lets Text wrap — that is the Reader view with extra steps"; ok=0; }
grep -q 'supports("captureJoin")' "$WATCH_STORE" \
  || { bad "reader mode is not gated on the captureJoin capability — a 0.4.1 daemon would be sent join/plain"; ok=0; }
[ "$ok" = "1" ] && note "the terminal offers Reader and Raw, and gates the daemon flags on captureJoin"

# ---- 9. key chips are big enough to hit ----
# 28x28 at 6pt spacing put Escape and Up within a thumb's width of each other, on
# controls that send real keystrokes to a real shell.
ok=1
grep -Eq 'static let minWidth: CGFloat = (4[2-9]|[5-9][0-9])' "$WATCH_VIEWS" \
  || { bad "WatchTouch.minWidth is under 42pt — key chips are too small to aim at"; ok=0; }
grep -Eq 'static let minHeight: CGFloat = (3[89]|[4-9][0-9])' "$WATCH_VIEWS" \
  || { bad "WatchTouch.minHeight is under 38pt — key chips are too short to aim at"; ok=0; }
KEYBAR="$(awk '/private var terminalKeyBar/,/^    }/' "$WATCH_VIEWS")"
printf '%s\n' "$KEYBAR" | grep -q 'HStack(spacing: 8)' \
  || { bad "the key bar does not use 8pt spacing between chips"; ok=0; }
# Font size is set once; Enter is pressed all day. The two text-size chips belong in
# the overflow page, not competing for width with the keys.
if printf '%s\n' "$KEYBAR" | grep -q 'textformat.size'; then
  bad "the text-size chips are still in the key bar — move them to the overflow page"
  ok=0
fi
grep -q 'textformat.size.larger' "$WATCH_VIEWS" \
  || { bad "the text-size controls disappeared entirely instead of moving to overflow"; ok=0; }
[ "$ok" = "1" ] && note "key chips are >=42x38 at 8pt spacing, with the font chips in overflow"

# ---- 10. every relayed WRITE is acknowledged ----
# WatchLink.send returns void whether the phone took the command, was asleep, or is a
# build that cannot decode it. On a wrist there is no console and no second screen, so
# "I pressed Enter and nothing happened" and "Enter went through" looked identical.
ok=1
grep -q 'func acknowledge(' "$WATCH_LINK" \
  || { bad "WatchLink has no acknowledge() — relayed writes cannot be confirmed"; ok=0; }
if grep -q 'WatchLink.shared.send(WatchCommand(kind: .agentSend' "$WATCH_STORE"; then
  bad "an agentSend still goes out fire-and-forget — use WatchLink.acknowledge so a lost keystroke is visible"
  ok=0
fi
grep -q 'WatchLink.shared.acknowledge' "$WATCH_STORE" \
  || { bad "WatchMeshStore never awaits an acknowledgement"; ok=0; }
[ "$ok" = "1" ] && note "relayed sends are acknowledged, with a haptic and an honest failure line"

# ---- 11. the machine's route and the watch's link are different sentences ----
# routeLabel used to answer "how am I reaching this Mac" with facts about the phone
# link: a Mac the phone had reported as down read "reconnecting", and a live Mac we
# simply had no word about read "offline".
grep -q 'no link to iPhone' "$WATCH_STORE" \
  || bad "routeLabel still says 'offline' for a dead watch->phone link — that is a sentence about the wrong machine"
grep -q 'connectionBanner' "$WATCH_VIEWS" \
  || bad "no connection banner on the machines list — a stale list looks exactly like a live one"

# ---- 12. gated features are actually gated, and capabilities actually reach them ----
# MeshClient.capabilities defaults to nil = "assume 0.4.1", so a client built without
# it silently disables every 0.5.0 feature. That is the correct default and a silent
# bug at the same time: the gate only works if somebody fills it in.
ok=1
grep -q 'client.capabilities = ' "$WATCH_STORE" \
  || { bad "WatchMeshStore builds MeshClients without capabilities — every 0.5.0 feature stays off"; ok=0; }
grep -q 'client.capabilities = capabilities' "$WATCH_REMOTE" \
  || { bad "RemoteControl builds its MeshClient without capabilities — region capture and honest /system stay off"; ok=0; }
grep -q 'supports("openUrl", host:' "$WATCH_STORE" \
  || { bad "'Open on Mac' is not gated on the openUrl capability — it would 404 on a 0.4.1 daemon"; ok=0; }
grep -q 'systemAction(' "$WATCH_REMOTE" \
  || { bad "RemoteView still uses system(_:) and assumes {ok:true} — a failed pmset renders as success"; ok=0; }
[ "$ok" = "1" ] && note "0.5.0 features are capability-gated and the capabilities are wired in"

# ---- 13. the iPhone's clipboard reaches the session ----
ok=1
grep -q 'kind: .readPhoneClipboard' "$WATCH_STORE" \
  || { bad "nothing asks the phone for its own clipboard"; ok=0; }
grep -q 'Insert iPhone clipboard' "$WATCH_VIEWS" \
  || { bad "no 'Insert iPhone clipboard' affordance in the agent actions"; ok=0; }
grep -q 'clipboardErrorPrefix' "$WATCH_STORE" \
  || { bad "the phone's clipboard error marker is not handled — a blocked read would look like an empty clipboard"; ok=0; }
[ "$ok" = "1" ] && note "the iPhone's clipboard can be typed into a session, and its refusal is reported"

# ---- 14. notification buttons route through the same send path ----
ok=1
grep -q 'AgentNotification.registerCategories()' "$WATCH_NOTIFS" \
  || { bad "the watch does not register the notification categories — forwarded alerts lose their buttons"; ok=0; }
grep -q 'AgentNotification.pane(from:' "$WATCH_NOTIFS" \
  || { bad "the watch drops the event's pane — a reply lands in whichever pane happens to be active"; ok=0; }
grep -q 'respondToAgent(host: host, session: session, pane: pane' "$WATCH_VIEWS" \
  || { bad "notification actions do not route through respondToAgent with the pane"; ok=0; }
[ "$ok" = "1" ] && note "Approve/Decline/Reply/Stop route through respondToAgent, pane and all"

if [ "$fail" = "0" ]; then
  echo "check-watch-terminal-wiring: OK"
else
  echo "check-watch-terminal-wiring: FAILED"
  exit 1
fi
