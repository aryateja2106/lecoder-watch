#!/bin/sh
# `mesh shellenv` + `mesh setup` + install.sh's PATH wiring, run for real.
#
# Every one of these fails silently in a way a reader cannot see:
#   - a `shellenv` that prints two lines (or a stray progress line) makes
#     `eval "$(mesh shellenv)"` execute garbage in the user's login shell;
#   - an installer that appends its PATH line on every run turns ~/.zshrc into a
#     stack of duplicates;
#   - a first-run wizard that prompts with no TTY hangs forever — and it runs inside
#     `mesh new` sessions and CI, neither of which has one;
#   - and the original complaint: `mesh` not being on PATH at all in the next shell,
#     which reads as "the install did not work".
#
# The installer is run in --only tools mode (no daemon, no bun install, no network)
# against a throwaway HOME + prefix, so the PATH wiring under test is the real code path
# and nothing here can touch the deployed ~/.mesh or the user's own rc files.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null 2>&1 || { echo "check-mesh-onboarding: SKIP (bun not installed)"; exit 0; }

TH="$(mktemp -d)"
trap 'rm -rf "$TH" 2>/dev/null || true' EXIT INT TERM

CLI="$ROOT/install/payload/bin/mesh"
fail() { echo "FAIL: $*"; exit 1; }

# ---------- mesh shellenv: exactly one eval-safe line ----------

MESH_HOME="$TH/prefix" bun "$CLI" shellenv > "$TH/shellenv.out" 2>"$TH/shellenv.err"
[ ! -s "$TH/shellenv.err" ] || fail "shellenv wrote to stderr: $(cat "$TH/shellenv.err")"
LINES="$(wc -l < "$TH/shellenv.out" | tr -d ' ')"
[ "$LINES" = "1" ] || fail "shellenv printed $LINES lines; eval needs exactly 1"
grep -Fqx "export PATH=\"$TH/prefix/bin:\$PATH\"" "$TH/shellenv.out" \
  || fail "shellenv line is not the expected export: $(cat "$TH/shellenv.out")"

# It has to survive `eval` and actually make the CLI reachable by bare name.
mkdir -p "$TH/prefix/bin"
printf '#!/bin/sh\necho reachable\n' > "$TH/prefix/bin/mesh"; chmod +x "$TH/prefix/bin/mesh"
GOT="$(MESH_HOME="$TH/prefix" PATH="/usr/bin:/bin" sh -c 'eval "$('"$(command -v bun)"' '"$CLI"' shellenv)"; command -v mesh >/dev/null && mesh')" \
  || fail "eval \"\$(mesh shellenv)\" did not make mesh reachable"
[ "$GOT" = "reachable" ] || fail "after eval, 'mesh' resolved to something unexpected: $GOT"
rm -rf "$TH/prefix"

# ---------- mesh setup with no TTY: a checklist, not a hang ----------

MESH_HOME="$TH/nohome" bun "$CLI" setup </dev/null >"$TH/setup.out" 2>&1 \
  || fail "mesh setup exited nonzero without a TTY: $(cat "$TH/setup.out")"
for want in "mesh doctor" "mesh pair" "mesh status" "install.sh | sh"; do
  grep -Fq "$want" "$TH/setup.out" || fail "the no-TTY checklist never mentions '$want'"
done

# ---------- install.sh really wires PATH into the shell rc ----------

HM="$TH/home"; PREFIX="$TH/home/.mesh"
mkdir -p "$HM"
install_tools() {
  HOME="$HM" SHELL="$1" MESH_HOME="$PREFIX" PATH="/usr/bin:/bin:/usr/sbin:/sbin:$(dirname "$(command -v bun)")" \
    sh "$ROOT/install/install.sh" --only tools --prefix "$PREFIX" >"$TH/install.log" 2>&1
}

install_tools /bin/zsh || { cat "$TH/install.log"; fail "install.sh --only tools failed"; }
[ -f "$HM/.zshrc" ] || fail "install.sh did not create ~/.zshrc with the PATH line"
COUNT="$(grep -Fc 'mesh shellenv' "$HM/.zshrc" || true)"
[ "$COUNT" = "1" ] || fail "expected exactly 1 shellenv line in ~/.zshrc, found $COUNT"
grep -Fq "eval \"\$($PREFIX/bin/mesh shellenv)\"" "$HM/.zshrc" \
  || fail "the appended line is not the eval form: $(grep -F 'shellenv' "$HM/.zshrc")"
# The user cannot act on something they were not told about, and a child process can
# never fix the parent shell — so the run has to name the file and say `source`.
grep -Fq "$HM/.zshrc" "$TH/install.log" || fail "the install output never names the rc file it edited"
grep -Fq "source $HM/.zshrc" "$TH/install.log" || fail "the install output never tells the user to source it"

# Re-running must not stack duplicates.
install_tools /bin/zsh || { cat "$TH/install.log"; fail "second install.sh run failed"; }
COUNT="$(grep -Fc 'mesh shellenv' "$HM/.zshrc" || true)"
[ "$COUNT" = "1" ] || fail "a second install appended the PATH line again ($COUNT copies in ~/.zshrc)"

# A shell we do not know how to configure must be told the line, never guessed at.
rm -f "$HM/.zshrc"
install_tools /usr/local/bin/fish || { cat "$TH/install.log"; fail "install.sh failed under an unknown \$SHELL"; }
[ ! -f "$HM/.zshrc" ] || fail "install.sh wrote ~/.zshrc for a fish user"
grep -Fq "$PREFIX/bin/mesh shellenv" "$TH/install.log" \
  || fail "an unknown \$SHELL was left with no instructions at all"

# Already on PATH: nothing to say, nothing to edit.
rm -f "$HM/.bashrc"
HOME="$HM" SHELL=/bin/bash MESH_HOME="$PREFIX" PATH="$PREFIX/bin:/usr/bin:/bin:/usr/sbin:/sbin:$(dirname "$(command -v bun)")" \
  sh "$ROOT/install/install.sh" --only tools --prefix "$PREFIX" >"$TH/install.log" 2>&1 \
  || { cat "$TH/install.log"; fail "install.sh failed when the prefix was already on PATH"; }
[ ! -f "$HM/.bashrc" ] || fail "install.sh edited ~/.bashrc even though ~/.mesh/bin was already on PATH"

echo "check-mesh-onboarding: OK (shellenv is one eval-safe line, setup degrades to a checklist, install.sh wires PATH once and says how to load it)"
