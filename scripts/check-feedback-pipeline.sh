#!/bin/sh
# check-feedback-pipeline.sh — the feedback worker files the right issues: a report that
# matches an open from-users issue becomes a comment (duplicate), a new one is filed, a
# secret in the report body is redacted before it can reach GitHub, the contact e-mail
# never appears (only its hash does), and rows are processed in order.
#
# Structural, offline: drives scripts/feedback-to-issues.ts with --fixture (no Supabase,
# no gh). The live half is the published proof in PUBLISHED.md (a real row, a real issue).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-feedback-pipeline: SKIP (bun not installed)"; exit 0; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
SECRET="ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"
cat >"$TMP/fixture.json" <<EOF
{
  "issues": [
    {"number": 7, "title": "[bug] App crashes when pairing a machine", "url": "https://github.com/LeSearch-AI/mesh/issues/7"}
  ],
  "rows": [
    {"id": "11111111-1111-4111-8111-111111111111", "created_at": "2026-09-22T10:00:00Z", "kind": "bug",
     "title": "Crash when pairing machine", "body": "tapped Pair and it died", "contact_email": null,
     "user_id": null, "app_version": "0.8.0", "app_build": "2", "device": "iPhone17,1", "os": "iOS 27.0",
     "attachment": null, "bundle": null, "source": "app"},
    {"id": "22222222-2222-4222-8222-222222222222", "created_at": "2026-09-22T10:01:00Z", "kind": "idea",
     "title": "Let me pin a session to the top", "body": "my token is $SECRET please ignore", "contact_email": "Someone@Example.com",
     "user_id": null, "app_version": "0.8.0", "app_build": "2", "device": "iPhone17,1", "os": "iOS 27.0",
     "attachment": null, "bundle": "Authorization: Bearer $SECRET", "source": "app"},
    {"id": "33333333-3333-4333-8333-333333333333", "created_at": "2026-09-22T10:02:00Z", "kind": "idea",
     "title": "Pin a session to the top please", "body": "same idea again", "contact_email": null,
     "user_id": null, "app_version": "0.8.0", "app_build": "2", "device": "iPhone17,1", "os": "iOS 27.0",
     "attachment": null, "bundle": null, "source": "app"}
  ]
}
EOF
out="$(cd "$ROOT" && bun scripts/feedback-to-issues.ts --fixture "$TMP/fixture.json" 2>&1)" || { echo "FAIL: check-feedback-pipeline: worker exited non-zero"; printf '%s\n' "$out" | tail -5; exit 1; }
fail=0
say() { echo "FAIL: check-feedback-pipeline: $*"; fail=1; }
printf '%s\n' "$out" | grep -q '^duplicate  11111111-1111-4111-8111-111111111111  ->  #7 ' || say "row 1 should dedupe onto open issue #7 (fuzzy title)"
printf '%s\n' "$out" | grep -q '^would file 22222222-2222-4222-8222-222222222222  \[idea\] Let me pin a session to the top' || say "row 2 should be filed as a new [idea] issue"
printf '%s\n' "$out" | grep -q '^duplicate  33333333-3333-4333-8333-333333333333  ->  #-1 ' || say "row 3 should dedupe onto the issue row 2 filed in the same batch"
printf '%s\n' "$out" | grep -q "$SECRET" && say "a token from the report body survived into the issue text"
printf '%s\n' "$out" | grep -qi 'someone@example.com' && say "contact e-mail leaked into the issue text"
printf '%s\n' "$out" | grep -q '\[github-token\]' || say "redaction should name the kind ([github-token]) so the reader knows what was hidden"
printf '%s\n' "$out" | grep -q 'Reference `22222222-2222-4222-8222-222222222222`' || say "issue body must cite the feedback row id"
printf '%s\n' "$out" | grep -q '| App | 0.8.0 (2) |' || say "issue body must carry app version and build"
# the hash of the lowercased e-mail is what may appear
h="$(printf 'someone@example.com' | shasum -a 256 | cut -c1-12)"
printf '%s\n' "$out" | grep -q "contact on file (hash $h)" || say "filed issue body should carry the e-mail hash $h, never the address"
# and the plist that schedules it must point at this script
grep -q 'feedback-to-issues.ts' "$ROOT/scripts/feedback-worker.plist" || say "scripts/feedback-worker.plist does not run feedback-to-issues.ts"
grep -q '<key>StartInterval</key>' "$ROOT/scripts/feedback-worker.plist" || say "scripts/feedback-worker.plist has no StartInterval"
[ "$fail" -eq 0 ] || exit 1
echo "check-feedback-pipeline: OK — dedupe (open issue + same batch), redaction, no e-mail, row id cited, plist scheduled"
