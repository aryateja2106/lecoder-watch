#!/bin/sh
# check-account-devices.sh — account home lists device labels only.
#
# The Devices block on the home page and the devices query must not name
# an address. Sentences outside that block still say the account does not
# hold mesh tokens; check-account-pages.sh owns those lines.
# A devices read must not run when account config is missing or empty.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOME_HTML="$ROOT/web/account/home.html"
JS="$ROOT/web/account/account.js"
ok=1
bad() { echo "FAIL: check-account-devices.sh: $1"; ok=0; }

[ -f "$HOME_HTML" ] || bad "web/account/home.html is missing"
[ -f "$JS" ] || bad "web/account/account.js is missing"

SENTENCE="Pairing still happens on the machine. This page lists labels only."
if [ -f "$HOME_HTML" ]; then
  grep -F -q "$SENTENCE" "$HOME_HTML" || bad "home is missing the devices empty state"
fi

if [ -f "$HOME_HTML" ] && [ -f "$JS" ]; then
  python3 - "$HOME_HTML" "$JS" "$SENTENCE" << 'PY' || ok=0
import re, sys
home = open(sys.argv[1], encoding="utf-8").read()
js = open(sys.argv[2], encoding="utf-8").read()
sentence = sys.argv[3]
errors = []

def fail(msg):
    errors.append(msg)

forbidden = re.compile(r"(?i)(?<![A-Za-z])(?:ip|hostname|token|host)(?![A-Za-z])")

section_m = re.search(r"<h2\b[^>]*>\s*Devices\s*</h2>(.*?)(?=<h2\b|\Z)", home, re.S)
if not section_m:
    fail("home is missing a Devices section")
    section = ""
else:
    section = section_m.group(0)
if sentence not in section:
    fail("home Devices section is missing the empty state")
hit = forbidden.search(section)
if hit:
    fail("home mentions " + hit.group(0))
if re.search(r"<input\b", section, re.I):
    fail("home Devices section has an input")

literals = re.findall(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'', js)
queries = []
for raw in literals:
    lit = raw[1:-1]
    if "/rest/v1/devices" in lit:
        queries.append(lit)
if len(queries) != 1:
    fail("account.js must contain one devices query")
for lit in queries:
    hit = forbidden.search(lit)
    if hit:
        fail("devices query mentions " + hit.group(0))
    q = lit.split("?", 1)[1] if "?" in lit else ""
    params = [p for p in q.split("&") if p]
    select_cols = None
    for p in params:
        key, _, val = p.partition("=")
        if forbidden.search(key) or forbidden.search(val):
            fail("devices query mentions " + (forbidden.search(key) or forbidden.search(val)).group(0))
        if key == "select":
            select_cols = [c for c in val.split(",") if c]
        elif key != "user_id":
            fail("devices query reads more than label and platform")
    if select_cols != ["label", "platform"]:
        fail("devices query must select label and platform only")

func_re = re.compile(r"^  function ([A-Za-z0-9_]+)\s*\(", re.M)
marks = list(func_re.finditer(js))
functions = {}
order = []
for i, fm in enumerate(marks):
    end = marks[i + 1].start() if i + 1 < len(marks) else len(js)
    name = fm.group(1)
    functions[name] = js[fm.start():end]
    order.append(name)

def guard_before_fetch(body):
    guard = re.search(r"if\s*\(\s*!cfg\s*\)", body)
    ret = re.search(r"return\s+Promise\.resolve\(\s*null\s*\)", body)
    fetch = re.search(r"fetch\s*\(", body)
    if not (guard and ret and fetch):
        return False
    return guard.start() < ret.start() < fetch.start()

call = functions.get("meshAccountCall", "")
if not guard_before_fetch(call):
    fail("devices fetch can run when config is empty")

device_fns = [name for name in order if "/rest/v1/devices" in functions[name]]
if device_fns != ["readDeviceLabels"]:
    fail("devices query must live in readDeviceLabels")
else:
    body = functions["readDeviceLabels"]
    if re.search(r"fetch\s*\(", body):
        fail("devices fetch can run when config is empty")
    if "meshAccountCall(" not in body:
        fail("devices fetch can run when config is empty")
    if not re.search(r'method\s*:\s*"GET"', body):
        fail("devices query is not a read")
    if re.search(r"row\.(?:ip|hostname|token|host)\b", body):
        fail("home reads a forbidden device field")

# Home handler: after the empty-config return, and not before it.
cb = re.search(r"^  loadAccountConfig\(\)\.then\(function\s*\(\s*cfg\s*\)\s*\{", js, re.M)
if not cb:
    fail("home does not wait for account config")
else:
    start = cb.end() - 1
    depth = 0
    block = ""
    for j in range(start, len(js)):
        if js[j] == "{":
            depth += 1
        elif js[j] == "}":
            depth -= 1
            if depth == 0:
                block = js[start:j + 1]
                break
    guard_m = re.search(r"if\s*\(\s*!cfg\s*\)\s*\{[^}]*return\s*;", block, re.S)
    if not guard_m:
        fail("devices fetch can run when config is empty")
    else:
        before = block[:guard_m.start()]
        after = block[guard_m.end():]
        if re.search(r"\breadDeviceLabels\s*\(", before):
            fail("devices fetch can run when config is empty")
        if not re.search(r"\breadDeviceLabels\s*\(", after):
            fail("home does not read devices after config exists")
        if re.search(r"fetch\s*\(", before) or re.search(r"/rest/v1/devices", block):
            fail("devices fetch can run when config is empty")
        hit = forbidden.search(block)
        if hit:
            fail("home mentions " + hit.group(0))

# A fetch( that includes the devices path is a second request, outside the guard.
for fm in re.finditer(r"fetch\s*\(", js):
    snippet = js[fm.start():fm.start() + 400]
    if "/rest/v1/devices" in snippet:
        fail("devices fetch can run when config is empty")

if errors:
    for msg in errors:
        print("FAIL: check-account-devices.sh: " + msg)
    sys.exit(1)
PY
fi

[ "$ok" -eq 1 ] || exit 1
echo "check-account-devices: OK"
