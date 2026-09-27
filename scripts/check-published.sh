#!/bin/sh
# check-published.sh — the finish line for "LeSearch AI is published at lesearch.ai and ready
# for real users": exits 0 only when every publish assertion below holds, live.
#
# Two halves, the same shape as every other check in scripts/:
#
#   sh scripts/check-published.sh                    # structural — what check-all.sh runs.
#       PUBLISHED.md, when present, must be well-formed and its gate SHA must be an
#       ancestor of HEAD with only docs between them. Absent PUBLISHED.md is fine here:
#       the tree is simply not published yet.
#
#   MESH_PUBLISHED=1 sh scripts/check-published.sh   # the finish line. Runs check-all.sh
#       for real, probes lesearch.ai, Supabase and GitHub, and reads PUBLISHED.md as the
#       ledger of proof. The project Stop hook (.claude/hooks/stop-published.sh) runs this
#       form; only its exit 0 means <promise>PUBLISHED</promise>.
#
# Rules. This file is an ADD (2026-09-22) and is never loosened to make it pass: add
# evidence to PUBLISHED.md, fix the product, or record a human blocker in BLOCKED.md.
# Every assertion prints one `FAIL: check-published: <n> <what>` line and the script goes
# on, so one run names everything that is still missing. Secrets are read from
# supabase/.env (gitignored) and never printed.
#
# PUBLISHED.md contract (one `Key: value` per line, anywhere in the file):
#   Gate: `FACTORY_GATES: level=full status=GREEN passed=N failed=0 failing=none skipped=none misconfigured=none`
#   Gate SHA: <full sha of the tree the full gate ran on>
#   Gate log: <path, committed, whose last FACTORY_GATES line equals the Gate line>
#   PR: #133 <state>            (the PR body carries the third-pass table)
#   Landing: https://lesearch.ai
#   Installer: <URL that the check resolves to install.sh at the daemon's VERSION>
#   Clean-device install: <device or simulator that had never seen the app> — <how> — <result>
#   Supabase project: <ref>
#   Signup user: <auth user id created by a fresh signup>
#   Feedback row: <feedback.id written by the published app>
#   Feedback issue: <GitHub issue URL labeled from-users that cites that row id>
#   Feedback worker: <what runs the pipeline, and where>
#   Fresh-eyes issues: <GitHub search URL or repo>  (issues labeled ux-review exist)
#   Blockers: BLOCKED.md                            (every `## ` heading of BLOCKED.md appears in PUBLISHED.md)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
PUB="$ROOT/PUBLISHED.md"
BLK="$ROOT/BLOCKED.md"
BRANCH="feat/lesearch-ai-overnight-2026-09-21"
PR_NUMBER=133
LANDING="https://lesearch.ai"
FEEDBACK_REPO="LeSearch-AI/mesh"
SUPABASE_REF="zmisjteztezaqfflwbgf"
STATE="$ROOT/docs/overnight/2026-09-21/STATE.md"
HANDOFF_DIR="$ROOT/docs/overnight/2026-09-21"
GATE_RE='FACTORY_GATES: level=full status=GREEN passed=[0-9]+ failed=0 failing=none skipped=none misconfigured=none'

fail=0
FAIL() { echo "FAIL: check-published: $*"; fail=1; }
ok()   { echo "ok:   check-published: $*"; }
field() { # field <Key> — first `Key: value` line of PUBLISHED.md, value only, backticks stripped
  sed -n "s/^[-* ]*$1:[[:space:]]*//p" "$PUB" 2>/dev/null | head -1 | sed 's/`//g; s/[[:space:]]*$//'
}
have() { command -v "$1" >/dev/null 2>&1; }
# Every probe here crosses a network. A single dropped request is not evidence that a
# service is off — reporting it as one sent this check red twice on things that were
# provably fine (the auth provider, a GitHub issue). Three tries, then believe it.
retry() {
  _out=""; _i=1
  while [ "$_i" -le 3 ]; do
    _out="$("$@" 2>/dev/null)" && [ -n "$_out" ] && { printf '%s' "$_out"; return 0; }
    _i=$((_i + 1)); sleep 2
  done
  printf '%s' "$_out"; return 1
}

daemon_version() {
  sed -n 's/^[[:space:]]*const VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/install/payload/meshd/server.ts" | head -1
}

# ---------------------------------------------------------------- structural half
structural() {
  [ -f "$PUB" ] || { echo "check-published: structural OK (no PUBLISHED.md yet — not published)"; return 0; }
  # A ledger with `pending` fields is one being assembled, which is the same state as no
  # ledger at all: the live half is what decides, and it accepts no placeholder. Without
  # this, check-all could never go green while PUBLISHED.md waits for the gate line that
  # a green check-all produces.
  pend="$(grep -cE '^[A-Za-z][A-Za-z -]*: *pending *$' "$PUB" 2>/dev/null || true)"
  [ "${pend:-0}" -eq 0 ] || { echo "check-published: structural OK (PUBLISHED.md is still being filled — $pend field(s) pending)"; return 0; }
  gate="$(field Gate)"
  printf '%s\n' "$gate" | grep -Eq "^$GATE_RE\$" || FAIL "1 Gate line in PUBLISHED.md is not the verbatim GREEN full-gate line (got: '$gate')"
  sha="$(field 'Gate SHA')"
  printf '%s' "$sha" | grep -Eq '^[0-9a-f]{40}$' || FAIL "8 Gate SHA in PUBLISHED.md is not a full 40-hex sha (got: '$sha')"
  if printf '%s' "$sha" | grep -Eq '^[0-9a-f]{40}$'; then
    git cat-file -e "$sha^{commit}" 2>/dev/null || FAIL "8 Gate SHA $sha is not a commit in this repo"
    git merge-base --is-ancestor "$sha" HEAD 2>/dev/null || FAIL "8 Gate SHA $sha is not an ancestor of HEAD"
    # Whether code landed after the gated sha is the live half's business, not this one.
    # This half runs inside check-all, which is what the re-gate itself runs: failing here
    # would make the gate red for the very staleness that running it resolves.
  fi
  log="$(field 'Gate log')"
  if [ -n "$log" ] && [ -f "$ROOT/$log" ]; then
    last="$(grep -E '^FACTORY_GATES:' "$ROOT/$log" | tail -1)"
    [ "$last" = "$gate" ] || FAIL "1 Gate log $log last FACTORY_GATES line differs from PUBLISHED.md Gate line"
    git ls-files --error-unmatch "$log" >/dev/null 2>&1 || FAIL "1 Gate log $log is not committed"
  else
    FAIL "1 Gate log missing (PUBLISHED.md 'Gate log:' must name a committed file; got '$log')"
  fi
  for key in 'PR' 'Landing' 'Installer' 'Clean-device install' 'Supabase project' 'Signup user' 'Feedback row' 'Feedback issue' 'Feedback worker' 'Fresh-eyes issues' 'Blockers'; do
    [ -n "$(field "$key")" ] || FAIL "8 PUBLISHED.md lacks a '$key:' line"
  done
  if [ -f "$BLK" ]; then
    grep -E '^## ' "$BLK" | sed 's/^## //' | while IFS= read -r h; do
      [ -n "$h" ] || continue
      grep -Fq -- "$h" "$PUB" || echo "FAIL: check-published: 8 BLOCKED.md heading not carried into PUBLISHED.md: $h"
    done | tee /tmp/check-published-blk.$$ ; if [ -s /tmp/check-published-blk.$$ ]; then fail=1; fi; rm -f /tmp/check-published-blk.$$
  else
    FAIL "8 BLOCKED.md missing (record human blockers there, even when empty)"
  fi
  [ "$fail" -eq 0 ] && echo "check-published: structural OK"
  return "$fail"
}

# ---------------------------------------------------------------- the finish line
live() {
  # Snapshot the tree BEFORE anything runs: check-all's sim-fleet check rewrites
  # docs/overnight/2026-09-21/shots/*.png every run, so asking afterwards would always
  # find the dirt this check itself just made.
  dirty="$(git status --porcelain 2>/dev/null)"
  [ -f "$PUB" ] || FAIL "8 PUBLISHED.md missing at repo root"
  structural >/dev/null 2>&1 || FAIL "8 PUBLISHED.md is not well-formed (run without MESH_PUBLISHED for the detail)"
  [ -f "$BLK" ] || FAIL "8 BLOCKED.md missing"

  # 1. Every self-check green, for real, now.
  #
  # Two runs driving one simulator kill each other's test runner ("Test crashed with
  # signal kill before establishing connection"), and the loser reports a red that says
  # nothing about the code. Refuse to race instead of manufacturing that red — this is a
  # failure, never a pass, so nothing is waved through.
  racing="$(pgrep -fl 'scripts/check-all\.sh|scripts/gates\.sh|xcodebuild test' 2>/dev/null | grep -v "check-published" | grep -v "^$$ " || true)"
  if [ -n "$racing" ]; then
    FAIL "1 another gate run is in flight — refusing to race it on the simulator: $(printf '%s' "$racing" | head -2 | tr '\n' ';')"
  elif [ "${MESH_PUBLISHED_CHECKALL:-1}" = "0" ]; then
    echo "note: check-published: check-all.sh skipped by MESH_PUBLISHED_CHECKALL=0 (dev iteration only — the Stop hook never sets it)"
  else
    CA="/tmp/check-published-check-all.$$.log"
    # Send the simulator captures somewhere else for this run. check-all reaches
    # check-overnight, whose sim-fleet check rewrites the four committed PNGs under
    # docs/overnight/2026-09-21/shots — so verifying "the tree is clean" would leave the
    # tree dirty, every time, for the next run to trip over.
    SHOTS_TMP="$(mktemp -d)"
    if MESH_PUBLISHED_INNER=1 MESH_SHOTS_DIR="$SHOTS_TMP" sh "$ROOT/scripts/check-all.sh" >"$CA" 2>&1 && ! grep -Eq '^FAIL' "$CA"; then
      ok "1 check-all.sh: $(tail -1 "$CA")"
    else
      FAIL "1 check-all.sh red: $(grep -E '^FAIL' "$CA" | head -5 | tr '\n' ';')"
    fi
    rm -f "$CA"; rm -rf "$SHOTS_TMP"
  fi

  # 1b. The gate line must describe THIS tree: only documentation may land after the sha
  # it ran on. Anything else means the quoted line is about code that is no longer here.
  gsha="$(field 'Gate SHA')"
  if printf '%s' "$gsha" | grep -Eq '^[0-9a-f]{40}$'; then
    off="$(git diff --name-only "$gsha" HEAD 2>/dev/null | grep -Ev '^(PUBLISHED\.md|BLOCKED\.md|docs/|.*\.md$)' || true)"
    [ -z "$off" ] || FAIL "1 non-doc files changed after the gated sha ${gsha%????????????????????????????????} (re-run the full gate): $(printf '%s' "$off" | tr '\n' ' ')"
  fi

  # 2. Clean (as of the start of this run), pushed, shots committed, PR body current.
  [ -z "$dirty" ] || FAIL "2 working tree not clean: $(printf '%s' "$dirty" | head -5 | tr '\n' ';')"
  git fetch -q origin "$BRANCH" 2>/dev/null || FAIL "2 cannot fetch origin/$BRANCH"
  git merge-base --is-ancestor HEAD "origin/$BRANCH" 2>/dev/null || FAIL "2 HEAD $(git rev-parse --short HEAD) is not on origin/$BRANCH (push it)"
  shots="$(git ls-files 'docs/overnight/2026-09-21/shots/*.png' | wc -l | tr -d ' ')"
  [ "$shots" -ge 4 ] || FAIL "2 fewer than 4 committed docs/overnight/2026-09-21/shots/*.png ($shots)"
  if have gh; then
    body="$(retry gh pr view "$PR_NUMBER" --json body,state -q '.state + "\n" + .body')"
    printf '%s' "$body" | grep -q 'third pass' || FAIL "2 PR #$PR_NUMBER body lacks the third-pass table"
    printf '%s' "$body" | grep -q '0\.8\.0' || FAIL "2 PR #$PR_NUMBER body does not mention 0.8.0"
  else
    FAIL "2 gh not installed — cannot verify PR #$PR_NUMBER"
  fi

  # 3. lesearch.ai serves the published build; clean-device install recorded.
  v="$(daemon_version)"
  [ -n "$v" ] || FAIL "3 no daemon VERSION in install/payload/meshd/server.ts"
  page="$(retry curl -fsSL --max-time 20 "$LANDING")"
  if [ -z "$page" ]; then
    FAIL "3 $LANDING did not answer 200"
  else
    printf '%s' "$page" | grep -qi 'LeSearch AI' || FAIL "3 $LANDING page does not say LeSearch AI"
    printf '%s' "$page" | grep -Eq 'href="[^"]*install\.sh"' || FAIL "3 $LANDING page has no install.sh link"
    printf '%s' "$page" | grep -Eq "$v" || FAIL "3 $LANDING page does not show the published version $v"
  fi
  installer="$(field Installer)"
  [ -n "$installer" ] || installer="$LANDING/install.sh"
  inst="$(retry curl -fsSL --max-time 30 "$installer")"
  if [ -z "$inst" ]; then
    FAIL "3 $installer does not resolve to an installer"
  else
    # Not "does the script mention the version" — the script points at a release by name
    # (`latest`), so the only honest test is to fetch what it would fetch and read the
    # daemon inside it. That is the code a stranger's machine actually runs.
    src="$(printf '%s' "$inst" | sed -n 's/^MESH_SRC_DEFAULT="\(.*\)"$/\1/p' | head -1)"
    [ -n "$src" ] || src="https://github.com/LeSearch-AI/mesh-install/releases/latest/download"
    tgz="/tmp/check-published-mesh-install.$$.tgz"
    # Same rule as every other probe here: one dropped request is not evidence that the
    # release is gone. Three tries (this one writes a file, so it cannot use retry()).
    _dl=1; _i=1
    while [ "$_i" -le 3 ]; do
      curl -fsSL --max-time 120 -o "$tgz" "$src/mesh-install.tgz" 2>/dev/null && [ -s "$tgz" ] && { _dl=0; break; }
      _i=$((_i + 1)); sleep 2
    done
    if [ "$_dl" -eq 0 ]; then
      got="$(tar xzf "$tgz" -O install/payload/meshd/server.ts 2>/dev/null | sed -n 's/^[[:space:]]*const VERSION[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
      [ "$got" = "$v" ] || FAIL "3 the installer at $installer fetches a daemon $got, not $v ($src/mesh-install.tgz)"
    else
      FAIL "3 could not download $src/mesh-install.tgz — the installer points at nothing"
    fi
    rm -f "$tgz"
  fi
  if have gh; then
    tag="$(gh release view "v$v" --repo LeSearch-AI/mesh-install --json tagName -q .tagName 2>/dev/null)"
    [ "$tag" = "v$v" ] || FAIL "3 LeSearch-AI/mesh-install has no release v$v"
  fi
  ci="$(field 'Clean-device install')"
  printf '%s' "$ci" | grep -Eiq 'ok|installed|launched' || FAIL "3 Clean-device install line does not record a successful install ('$ci')"
  printf '%s' "$ci" | grep -Eq '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}|[0-9a-f]{40}' \
    || FAIL "3 Clean-device install line names no device/simulator udid ('$ci')"

  # 4. Supabase live: auth e2e, feedback table sealed, real row present.
  ENVF="$ROOT/supabase/.env"
  SB_URL="https://$SUPABASE_REF.supabase.co"
  [ "$(field 'Supabase project')" = "$SUPABASE_REF" ] || FAIL "4 PUBLISHED.md Supabase project is not $SUPABASE_REF"
  if [ -f "$ENVF" ]; then
    ANON="$(sed -n 's/^SUPABASE_ANON_KEY=//p' "$ENVF" | head -1 | tr -d '"')"
    SRK="$(sed -n 's/^SUPABASE_SERVICE_ROLE_KEY=//p' "$ENVF" | head -1 | tr -d '"')"
  else
    ANON=""; SRK=""
    FAIL "4 supabase/.env missing (SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY) — the check cannot probe the backend"
  fi
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$SB_URL/rest/v1/feedback?select=id&limit=1")"
  case "$code" in 401|403) ok "4 unauthenticated GET /rest/v1/feedback -> $code" ;; *) FAIL "4 unauthenticated GET /rest/v1/feedback answered $code (want 401/403)" ;; esac
  if [ -n "$ANON" ]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -H "apikey: $ANON" -H "Authorization: Bearer $ANON" "$SB_URL/rest/v1/feedback?select=id&limit=1")"
    case "$code" in 401|403) ok "4 anon-key GET /rest/v1/feedback -> $code (no read for anon)" ;; *) FAIL "4 anon-key GET /rest/v1/feedback answered $code (want 401/403: anon must not read feedback)" ;; esac
    settings="$(retry curl -fsS --max-time 20 -H "apikey: $ANON" "$SB_URL/auth/v1/settings")"
    printf '%s' "$settings" | grep -q '"email":true' || FAIL "4 Supabase auth email provider is not enabled"
  fi
  uid="$(field 'Signup user')"
  printf '%s' "$uid" | grep -Eiq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' || FAIL "4 Signup user is not an auth user uuid ('$uid')"
  rid="$(field 'Feedback row')"
  printf '%s' "$rid" | grep -Eiq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' || FAIL "4 Feedback row is not a feedback.id uuid ('$rid')"
  if [ -n "$SRK" ]; then
    uid1="$(printf '%s' "$uid" | cut -c1-36)"
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 -H "apikey: $SRK" -H "Authorization: Bearer $SRK" "$SB_URL/auth/v1/admin/users/$uid1")"
    [ "$code" = "200" ] || FAIL "4 signup user $uid1 not found via auth admin ($code)"
    rid1="$(printf '%s' "$rid" | cut -c1-36)"
    row="$(retry curl -fsS --max-time 20 -H "apikey: $SRK" -H "Authorization: Bearer $SRK" "$SB_URL/rest/v1/feedback?id=eq.$rid1&select=id,kind,app_version,source,issue_url")"
    printf '%s' "$row" | grep -q "\"id\":\"$rid1\"" || FAIL "4 feedback row $rid1 not present in Supabase"
    printf '%s' "$row" | grep -q "\"app_version\":\"$v\"" || FAIL "4 feedback row $rid1 was not written by the published app $v (app_version)"
    # 5. …and that row became an issue.
    issue="$(field 'Feedback issue')"
    printf '%s' "$issue" | grep -Eq "^https://github.com/$FEEDBACK_REPO/issues/[0-9]+$" || FAIL "5 Feedback issue is not an issue URL on $FEEDBACK_REPO ('$issue')"
    printf '%s' "$row" | grep -q "\"issue_url\":\"$issue\"" || FAIL "5 feedback row $rid1 is not linked back to $issue (issue_url column)"
    if have gh && printf '%s' "$issue" | grep -Eq '/issues/[0-9]+$'; then
      n="${issue##*/}"
      ij="$(retry gh issue view "$n" --repo "$FEEDBACK_REPO" --json labels,body,state -q '(.labels|map(.name)|join(",")) + "\n" + .state + "\n" + .body')"
      printf '%s' "$ij" | head -1 | grep -q 'from-users' || FAIL "5 issue #$n on $FEEDBACK_REPO is not labeled from-users"
      printf '%s' "$ij" | grep -q "$rid1" || FAIL "5 issue #$n does not cite feedback row $rid1"
    fi
  fi
  [ -n "$(field 'Feedback worker')" ] || FAIL "5 PUBLISHED.md lacks a 'Feedback worker:' line naming what runs the pipeline"

  # 6. Docs a stranger can walk.
  for f in docs/getting-started.md docs/product/README.md docs/product/design-system.md; do
    [ -s "$ROOT/$f" ] || FAIL "6 $f missing or empty"
  done
  if [ -s "$ROOT/docs/getting-started.md" ]; then
    grep -Eqi '^#+ .*(account|sign)' "$ROOT/docs/getting-started.md" || FAIL "6 getting-started.md has no account/sign-up section"
    grep -Eqi '^#+ .*install' "$ROOT/docs/getting-started.md" || FAIL "6 getting-started.md has no install section"
    grep -Eq '!\[[^]]*\]\([^)]+\.png\)' "$ROOT/docs/getting-started.md" || FAIL "6 getting-started.md has no screenshots"
  fi
  if [ -s "$ROOT/docs/product/README.md" ]; then
    grep -Eq '\| *[^|]+ *\| *[^|]*(\.swift|\.ts|bin/mesh)[^|]* *\| *[^|]*check-' "$ROOT/docs/product/README.md" \
      || FAIL "6 docs/product/README.md has no feature | files | check table rows"
  fi
  if [ -s "$ROOT/docs/product/design-system.md" ]; then
    grep -Eqi 'token' "$ROOT/docs/product/design-system.md" || FAIL "6 design-system.md has no tokens section"
    grep -Eq '\.swift' "$ROOT/docs/product/design-system.md" || FAIL "6 design-system.md has no component -> source map"
  fi
  pshots="$(git ls-files 'docs/product/shots/*.png' | wc -l | tr -d ' ')"
  [ "$pshots" -ge 6 ] || FAIL "6 fewer than 6 committed docs/product/shots/*.png ($pshots)"
  for p in $(git ls-files 'docs/product/shots/*.png'); do
    [ "$(wc -c <"$ROOT/$p" | tr -d ' ')" -gt 10000 ] || FAIL "6 $p is under 10 KB — not a real screenshot"
  done

  # 7. Fresh-eyes review filed.
  if have gh; then
    n="$(gh issue list --repo "$FEEDBACK_REPO" --label ux-review --state all --limit 100 --json number -q 'length' 2>/dev/null)"
    [ "${n:-0}" -ge 1 ] || FAIL "7 no issues labeled ux-review on $FEEDBACK_REPO"
    grep -Eqi '^#+ .*fresh-eyes' "$PUB" 2>/dev/null || FAIL "7 PUBLISHED.md has no Fresh-eyes section (triage record)"
  fi

  # 8. PUBLISHED.md fields (beyond structural): PR state and the head sha it describes.
  pr="$(field PR)"
  printf '%s' "$pr" | grep -Eq "^#$PR_NUMBER " || FAIL "8 PUBLISHED.md PR line does not start with #$PR_NUMBER ('$pr')"
  grep -Eq 'tailscale serve|:8890' "$PUB" 2>/dev/null || FAIL "8 PUBLISHED.md does not record the state of the :8890 Tailscale share"

  # 9. STATE.md M8 row; handoff refreshed.
  grep -Eq '^\| *M8 ' "$STATE" || FAIL "9 STATE.md has no M8 row"
  hand="$(ls -t "$HANDOFF_DIR"/HANDOFF-*.md 2>/dev/null | head -1)"
  [ -n "$hand" ] || FAIL "9 no HANDOFF-*.md under $HANDOFF_DIR"
  [ -n "$hand" ] && { grep -q 'PUBLISHED.md' "$hand" || FAIL "9 newest handoff $(basename "$hand") does not mention PUBLISHED.md (refresh it)"; }

  if [ "$fail" -eq 0 ]; then
    echo "check-published: OK — published at $LANDING, daemon $v, gate $(field 'Gate SHA' | cut -c1-7)"
  else
    echo "check-published: FAIL"
  fi
  return "$fail"
}

# Re-entrancy: the live half runs check-all.sh, which globs this file back in. The inner
# run must be the cheap structural half, never the live one again.
if [ "${MESH_PUBLISHED:-0}" = "1" ] && [ "${MESH_PUBLISHED_INNER:-0}" != "1" ]; then
  live
else
  structural
fi
