#!/bin/sh
# check-links.sh — the front door still opens.
#
# Two links ARE the product to anyone who does not have it yet: the install one-liner and
# the TestFlight join link. Both have silently rotted before, and neither rot was visible
# from inside the repo:
#
#   - README's install command pointed at mesh.lesearch.ai when that name had no DNS at
#     all, so the first command a new user ran could not resolve. The README was correct
#     English about a host that did not exist.
#   - The TestFlight link kept serving a build from weeks earlier, because uploading is not
#     publishing. A link that answers 200 with the wrong thing is a different problem than
#     this check solves — but a link that answers 404 is this one, and it is cheaper.
#
# So: fetch every install/TestFlight URL the docs actually publish and demand a 2xx/3xx.
# The four canonical ones are named here, and the rest are harvested out of README.md and
# docs/updating.md so a link added next month is covered without anyone remembering to add
# it. Nothing here checks CONTENT — only that the address resolves and answers.
#
# Needs the network, and check-all.sh runs it on laptops that may not have any. Offline is
# a SKIP unless MESH_LINKS_REQUIRED=1, which CI sets: on a runner, "no network" is a broken
# runner, not a plane seat, and reporting it as a pass hides the very rot this exists for.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

note() { echo "check-links: $1"; }
REQUIRED="${MESH_LINKS_REQUIRED:-}"

if ! command -v curl >/dev/null 2>&1; then
  if [ "$REQUIRED" = "1" ]; then
    note "FAIL: MESH_LINKS_REQUIRED=1 but curl is not installed — no link was checked."
    exit 1
  fi
  note "SKIP — curl is not installed, so no link could be fetched."
  exit 0
fi

# curl reports a connect failure two ways at once: http_code 000 on stdout AND a non-zero
# exit. Under `set -e` the exit is what kills the script, so every call is `|| true` and the
# CAPTURED CODE is what gets tested. Writing `|| printf 000` instead would be worse than
# useless: it invents a code for cases that never reached the fallback, and a real 404 would
# be reported as a connect failure.
http_code() {
  curl -fsSIL --retry 1 -m 25 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || true
}

# Is there a network at all? Distinguishing "the link is dead" from "this machine is on a
# plane" is the entire difference between a real finding and a wasted hour. github.com is
# the probe because two of the four URLs are served from it.
if [ "$(http_code https://github.com)" = "000" ]; then
  if [ "$REQUIRED" = "1" ]; then
    note "FAIL: MESH_LINKS_REQUIRED=1 and this machine cannot reach https://github.com."
    note "      NOT ONE LINK WAS CHECKED. Where this flag is set the network is a given, so"
    note "      an offline result means the runner is broken — never that the links are fine."
    exit 1
  fi
  note "SKIP — offline (https://github.com is unreachable), so no link could be checked."
  note "      Set MESH_LINKS_REQUIRED=1 to make an offline run a failure instead."
  exit 0
fi

# The canonical four. These are what a stranger types, in the order they meet them.
# Kept in mktemp rather than the repo: release-testflight-asc.sh refuses to ship from a
# dirty tree, and a scratch file dropped in $ROOT would make this check cause that refusal.
URLS="$(mktemp -t mesh-check-links)"
trap 'rm -f "$URLS"' EXIT
cat > "$URLS" <<'EOF'
https://mesh.lesearch.ai/install.sh
https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh
https://github.com/LeSearch-AI/mesh-install/releases/latest/download/mesh-install.tgz
https://testflight.apple.com/join/pVYPTxc7
EOF

# …plus whatever the docs publish. Harvested rather than listed, because the list above is
# a snapshot and the docs are the thing users actually read. Parentheses are excluded from
# the character class so a markdown `[text](url)` does not capture its own closing bracket;
# trailing sentence punctuation is trimmed after.
for doc in README.md docs/updating.md; do
  [ -f "$doc" ] || continue
  grep -ohE 'https://[A-Za-z0-9._~:/?#@!$&*+,;=%-]+' "$doc" \
    | sed 's/[.,;:]*$//' \
    | grep -iE 'install|testflight\.apple\.com' >> "$URLS" || true
done

ok=1
n=0
for url in $(sort -u "$URLS"); do
  n=$((n + 1))
  code="$(http_code "$url")"
  case "$code" in
    2??|3??) printf '  %s  %s\n' "$code" "$url" ;;
    000)
      echo "FAIL: check-links.sh: $url did not answer at all (DNS, TLS or connection refused)."
      echo "      That is what a dead install one-liner looks like: the command a new user"
      echo "      pastes cannot even resolve, and the README reads perfectly fine."
      ok=0 ;;
    *)
      echo "FAIL: check-links.sh: $url answered $code."
      echo "      A published link that does not serve is a broken front door — fix the link"
      echo "      or fix what it points at, but do not ship with it in the README."
      ok=0 ;;
  esac
done

[ "$ok" -eq 1 ] || exit 1
echo "check-links: OK ($n published install/TestFlight links all answer)"
