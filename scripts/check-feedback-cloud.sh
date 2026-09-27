#!/bin/sh
# check-feedback-cloud.sh — the in-app feedback client talks to the live contract and nothing
# more: the anon key is the daemon's (one source of truth), rows go to /rest/v1/feedback with
# Prefer: return=minimal (the phone mints the id; anon can never read), attachments go to the
# private bucket, the auto-attached facts (version, build, device, os, source) are all sent,
# the attachment is opt-in (PhotosPicker), the report view never touches the Keychain, and
# the account session lives in SecureStore, never UserDefaults.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

failed=0
fail() { echo "FAIL: check-feedback-cloud: $1"; failed=1; }
cloud="$ROOT/iOS/LeSearchCloud.swift"
feedback="$ROOT/iOS/FeedbackView.swift"
telemetry="$ROOT/install/payload/meshd/telemetry.ts"

swift_key=$(sed -n 's/.*SUPABASE_ANON_KEY = "\([^"]*\)".*/\1/p' "$cloud" | head -1)
daemon_key=$(sed -n '/const SUPABASE_ANON_KEY =/{n;s/[[:space:]]*"\([^"]*\)";.*/\1/p;}' "$telemetry" | head -1)
[ -n "$swift_key" ] && [ "$swift_key" = "$daemon_key" ] || fail "iOS and daemon Supabase anon keys differ"

grep -q '/rest/v1/feedback' "$cloud" || fail "feedback REST endpoint missing"
grep -q 'setValue("return=minimal", forHTTPHeaderField: "Prefer")' "$cloud" || fail "Prefer: return=minimal missing"
grep -q '/storage/v1/object/feedback-attachments/' "$cloud" || fail "attachment endpoint missing"
for key in app_version app_build device os source; do
    grep -q "\"$key\"" "$cloud" || fail "feedback JSON key $key missing"
done

grep -q 'PhotosPicker' "$feedback" || fail "opt-in PhotosPicker missing"
[ "$(grep -c 'SecureStore' "$feedback")" -eq 0 ] || fail "FeedbackView must not read SecureStore"
grep -q 'SecureStore.save' "$cloud" || fail "cloud session is not saved through SecureStore"
grep -q 'SecureStore.load' "$cloud" || fail "cloud session is not loaded through SecureStore"
grep -q 'SecureStore.delete' "$cloud" || fail "cloud session is not deleted through SecureStore"
if grep -q 'UserDefaults' "$cloud"; then fail "LeSearchCloud must not use UserDefaults"; fi

[ "$failed" -eq 0 ] || exit 1
echo "check-feedback-cloud: OK — endpoints, metadata, opt-in attachment, and Keychain session storage"
