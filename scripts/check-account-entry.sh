#!/bin/sh
# check-account-entry.sh — the public homepage links into the account pages.
#
# A visitor landing on web/index.html must be able to open sign-in and
# sign-up from the header. Installing still does not require an account.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAGE="$ROOT/web/index.html"
ok=1
bad() { echo "FAIL: check-account-entry.sh: $1"; ok=0; }

[ -f "$PAGE" ] || bad "web/index.html is missing"

header="$(awk '/<header>/,/<\/header>/' "$PAGE" || true)"
printf '%s\n' "$header" | grep -q 'href="/account/sign-in"' \
  || bad "header is missing a link to /account/sign-in"
printf '%s\n' "$header" | grep -q 'href="/account/sign-up"' \
  || bad "header is missing a link to /account/sign-up"

grep -q 'no account required to install' "$PAGE" \
  || bad "homepage dropped the sentence that install does not require an account"

if grep -q '.nav a.link{display:none}' "$PAGE"; then
  bad "small-screen CSS hides every header link, including the account links"
fi

[ "$ok" -eq 1 ] || exit 1
echo "ok: homepage header links to /account/sign-in and /account/sign-up"
