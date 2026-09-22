#!/bin/sh
# An alert you cannot clear is worse than no alert: it teaches you to ignore the badge.
#
# Dismissal used to be @State private to MonitorView, applied only to that screen's list,
# while the bell's badge (`sessionsNeedingAttention`) and the Machines tab's "Needs you"
# rows were recomputed from the UNFILTERED event array on every poll. Swiping a row away
# cleared one of the three places it appeared, and the machine's own reply never posts a
# calmer event, so the other two stood forever. Reported 2026-09-22 from the iPhone as
# "a false alert I am unable to clear".
#
# The rule this pins: exactly one owner of the dismissal set, and every surface reads the
# filtered list.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STORE="$ROOT/iOS/MeshStore.swift"
VIEW="$ROOT/iOS/ContentView.swift"
fail=0
note() { echo "check-event-dismissal: $1"; }
bad() { echo "FAIL: $1"; fail=1; }
for f in "$STORE" "$VIEW"; do [ -f "$f" ] || { bad "missing $f"; }; done
[ "$fail" = 0 ] || exit 1

grep -q '@Published var dismissedEventIDs' "$STORE" \
  || bad "the store no longer owns the dismissal set"
grep -q 'var visibleEvents' "$STORE" \
  || bad "the store no longer exposes visibleEvents"
# The snapshot is what the bell, the attention rows, the watch mirror and the Live Activity
# all read. If it is built from the raw array again, a dismissal stops meaning anything.
if grep -qE '^\s+events: events,' "$STORE"; then
  bad "a snapshot is still built from the unfiltered events array — the badge would outlive the swipe"
else
  note "every snapshot is built from visibleEvents ($(grep -c 'events: visibleEvents,' "$STORE") site(s))"
fi
grep -q 'UserDefaults.standard.stringArray(forKey: "mesh.dismissedEventIDs.v1")' "$VIEW" \
  && bad "MonitorView keeps its own copy of the dismissal set again — two owners, one of them stale"
grep -q 'store.dismissEvent' "$VIEW" || bad "MonitorView's swipe no longer routes through the store"
grep -q 'store.dismissAllVisibleEvents' "$VIEW" || bad "Clear all no longer routes through the store"

[ "$fail" = 0 ] && echo "check-event-dismissal: OK" || exit 1
