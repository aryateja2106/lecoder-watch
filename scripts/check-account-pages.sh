#!/bin/sh
# check-account-pages.sh — static website account pages stay identity-only.
#
# Missing config.js must leave the setup message in the HTML and the script
# must return before fetch. No service role and no bearer token belong in
# web/account/. The real config.js is gitignored.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ACC="$ROOT/web/account"
ok=1
bad() { echo "FAIL: check-account-pages.sh: $1"; ok=0; }

for page in sign-up sign-in forgot reset home; do
  [ -f "$ACC/$page.html" ] || bad "web/account/$page.html is missing"
done

SU="$ACC/sign-up.html"
grep -q 'name="username"' "$SU" || bad "sign-up is missing a username field"
grep -q 'name="email"' "$SU" || bad "sign-up is missing an email field"
grep -q 'type="password"' "$SU" || bad "sign-up is missing a password field"
grep -q 'name="email"' "$ACC/forgot.html" || bad "forgot is missing an email field"
grep -q 'name="new-password"' "$ACC/reset.html" || bad "reset is missing a new-password field"

HOME="$ACC/home.html"
grep -q 'id="delete-account"' "$HOME" || bad "home is missing the delete control"
grep -q 'Delete account' "$HOME" || bad "home is missing a Delete account control"
grep -q 'does not rotate mesh tokens' "$HOME" || bad "home does not say deletion leaves mesh tokens alone"
grep -q 'does not reach a machine' "$HOME" || bad "home does not say deletion does not reach a machine"
grep -q 'token rotation locally' "$HOME" || bad "home does not say machines stay paired until local token rotation"

EX="$ACC/config.example.js"
[ -f "$EX" ] || bad "web/account/config.example.js is missing"
if [ -f "$EX" ]; then
  grep -E -q 'https?://' "$EX" && bad "config.example.js contains an http URL" || true
  grep -F -q 'eyJ' "$EX" && bad "config.example.js contains an eyJ string" || true
fi

grep -q '^account/config\.js$' "$ROOT/web/.gitignore" \
  || bad "web/.gitignore does not list account/config.js"
git -C "$ROOT" check-ignore -q web/account/config.js \
  || bad "web/account/config.js is not gitignored"
if git -C "$ROOT" ls-files --error-unmatch web/account/config.js >/dev/null 2>&1; then
  bad "web/account/config.js is tracked"
fi

if grep -R -n -E 'service_role|eyJ' "$ACC" >/dev/null 2>&1; then
  bad "web/account contains service_role or an eyJ string"
  grep -R -n -E 'service_role|eyJ' "$ACC" || true
fi
if grep -R -n -E 'Bearer [A-Za-z0-9._-]{20,}' "$ACC" >/dev/null 2>&1; then
  bad "web/account contains a pasted bearer token"
  grep -R -n -E 'Bearer [A-Za-z0-9._-]{20,}' "$ACC" || true
fi

if grep -q '<h2>No accounts</h2>' "$ROOT/web/privacy.html"; then
  bad "web/privacy.html still has <h2>No accounts</h2>"
fi

SETUP="Account setup is not finished on this deploy"
for page in sign-up sign-in forgot reset home; do
  grep -q "$SETUP" "$ACC/$page.html" || bad "$page.html is missing the setup message"
  grep -q 'fetch(' "$ACC/$page.html" && bad "$page.html calls fetch" || true
done

JS="$ACC/account.js"
[ -f "$JS" ] || bad "web/account/account.js is missing"
grep -q "$SETUP" "$JS" || bad "account.js is missing the setup message"
# The only fetch must sit after the missing-config return.
awk '
  /function meshAccountCall/ { infn = "call"; callguard = 0; callret = 0 }
  /function deleteAccount/ { infn = "del"; delguard = 0; delret = 0 }
  infn == "call" && /if \(!cfg\)/ { callguard = 1 }
  infn == "call" && callguard && /return Promise\.resolve\(null\)/ { callret = 1 }
  infn == "del" && /if \(!cfg\)/ { delguard = 1 }
  infn == "del" && delguard && /return Promise\.resolve\(null\)/ { delret = 1 }
  /fetch\(/ {
    fetches++
    if (infn == "call") {
      if (!(callguard && callret)) bad = 1
      callfetch = 1
    } else if (infn == "del") {
      if (!(delguard && delret)) bad = 1
      delfetch = 1
    } else bad = 1
  }
  END {
    if (fetches != 2 || bad || !callfetch || !delfetch) exit 1
  }
' "$JS" || bad "account.js must refuse the network when config is missing, before each fetch"

grep -q '/api/delete-account' "$JS" || bad "account.js does not call /api/delete-account"
grep -q 'Authorization: "Bearer " + session.token' "$JS" \
  || bad "account.js does not send the session access token"

API="$ROOT/web/api/delete-account.js"
[ -f "$API" ] || bad "web/api/delete-account.js is missing"
if [ -f "$API" ]; then
  grep -q 'SUPABASE_URL' "$API" || bad "delete-account.js does not read SUPABASE_URL"
  grep -q 'SUPABASE_ANON_KEY' "$API" || bad "delete-account.js does not read SUPABASE_ANON_KEY"
  grep -q 'SUPABASE_SERVICE_ROLE_KEY' "$API" || bad "delete-account.js does not read SUPABASE_SERVICE_ROLE_KEY"
  grep -q '/auth/v1/user' "$API" || bad "delete-account.js does not verify the caller"
  grep -q '/auth/v1/admin/users/' "$API" || bad "delete-account.js does not delete the auth user"
  grep -q '401' "$API" || bad "delete-account.js does not return 401"
  grep -q '200' "$API" || bad "delete-account.js does not return 200"
  grep -q '500' "$API" || bad "delete-account.js does not return 500"
  grep -F -q 'eyJ' "$API" && bad "delete-account.js contains an eyJ string" || true
  grep -E -q 'console\.' "$API" && bad "delete-account.js logs" || true
  grep -E -q "['\"]service_role['\"]" "$API" && bad "delete-account.js contains service_role as a value" || true
  grep -E -q "['\"][A-Za-z0-9_-]{40,}['\"]" "$API" && bad "delete-account.js contains a literal key" || true
fi

if ! command -v python3 >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
  bad "python3 and curl are required to serve the four account pages"
else
  TMP="$(mktemp -d)"
  PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
  cat > "$TMP/serve.py" << 'PY'
import os, sys
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
root, port = sys.argv[1], int(sys.argv[2])

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=root, **kwargs)
    def do_GET(self):
        raw = self.path
        path, _, query = raw.partition("?")
        if path != "/" and path.endswith("/"):
            path = path[:-1]
        rel = path.lstrip("/")
        html = os.path.join(root, rel + ".html")
        direct = os.path.join(root, rel)
        if rel and os.path.isfile(html) and not os.path.exists(direct):
            self.path = "/" + rel + ".html" + ("?" + query if query else "")
        return super().do_GET()
    def log_message(self, fmt, *args):
        return

ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
PY
  python3 "$TMP/serve.py" "$ROOT/web" "$PORT" &
  PID=$!
  trap 'kill "$PID" 2>/dev/null || true; rm -rf "$TMP"' EXIT
  i=0
  while [ "$i" -lt 50 ]; do
    if curl -sf -o /dev/null "http://127.0.0.1:$PORT/account/sign-up"; then
      break
    fi
    i=$((i + 1))
    sleep 0.05
  done
  for page in sign-up sign-in forgot reset home; do
    body="$TMP/$page.body"
    code="$(curl -sS -o "$body" -w '%{http_code}' "http://127.0.0.1:$PORT/account/$page" || true)"
    [ "$code" = "200" ] || bad "/account/$page returned $code"
    grep -q "$SETUP" "$body" || bad "/account/$page HTML is missing the setup message"
  done
  body="$TMP/home-file.body"
  code="$(curl -sS -o "$body" -w '%{http_code}' "http://127.0.0.1:$PORT/account/home.html" || true)"
  [ "$code" = "200" ] || bad "/account/home.html returned $code"
  grep -q "$SETUP" "$body" || bad "/account/home.html HTML is missing the setup message"
  grep -q "does not rotate mesh tokens" "$body" || bad "/account/home.html does not say deletion leaves mesh tokens alone"
  grep -q "does not reach a machine" "$body" || bad "/account/home.html does not say deletion does not reach a machine"
  grep -q "token rotation locally" "$body" || bad "/account/home.html does not say machines stay paired until local token rotation"
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  trap - EXIT
  rm -rf "$TMP"
fi

[ "$ok" -eq 1 ] || exit 1
echo "check-account-pages: OK"
