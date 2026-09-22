#!/bin/sh
# Reject an account identity migration that could store a mesh secret.
# Column names are read from create-table bodies. A banned word fails the
# check when it sits in a name. The platform enum and the recipient device
# id are the schema's own columns: the segment "platform" is not a latitude,
# and the segments "recipient" and "ciphertext" are not addresses. Any other segment that
# contains the banned word still fails (latitude, recipient_ip, platform_lat).
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SQL="$ROOT/supabase/account/001_identity.sql"

[ -f "$SQL" ] || { echo "FAIL: missing supabase/account/001_identity.sql"; exit 1; }

python3 - "$SQL" <<'PY'
import re
import sys

FORBIDDEN = (
    "token",
    "hostname",
    "host",
    "apns",
    "tailnet",
    "screen",
    "mac",
    "lng",
    "lat",
    "ip",
)

# Whole snake_case segments that contain a banned substring and are required
# by the identity schema. The exemption is the segment, not the banned word.
# "platform" contains "lat", "recipient" contains "ip", and "ciphertext"
# contains "ip". latitude, recipient_ip, and a column named ip still fail.
SAFE_SEGMENTS = {
    "lat": {"platform"},
    "ip": {"recipient", "ciphertext"},
}

REQUIRED = {
    "profiles": ["id", "username", "created_at"],
    "devices": [
        "id",
        "user_id",
        "label",
        "platform",
        "public_key",
        "created_at",
        "last_seen_at",
    ],
    "mailbox": [
        "id",
        "user_id",
        "recipient_device_id",
        "sender_device_id",
        "ciphertext",
        "created_at",
        "expires_at",
    ],
}


def strip_comments(sql):
    out = []
    i = 0
    n = len(sql)
    while i < n:
        if sql[i] == "'":
            j = i + 1
            while j < n:
                if sql[j] == "'":
                    if j + 1 < n and sql[j + 1] == "'":
                        j += 2
                        continue
                    j += 1
                    break
                j += 1
            out.append(sql[i:j])
            i = j
        elif sql.startswith("--", i):
            j = sql.find("\n", i)
            if j < 0:
                break
            out.append("\n")
            i = j + 1
        elif sql.startswith("/*", i):
            j = sql.find("*/", i + 2)
            if j < 0:
                break
            out.append(" ")
            i = j + 2
        else:
            out.append(sql[i])
            i += 1
    return "".join(out)


def split_fields(body):
    parts = []
    buf = []
    depth = 0
    for ch in body:
        if ch == "(":
            depth += 1
            buf.append(ch)
        elif ch == ")":
            depth -= 1
            buf.append(ch)
        elif ch == "," and depth == 0:
            parts.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    if buf:
        parts.append("".join(buf))
    return parts


def tables(sql):
    src = strip_comments(sql)
    found = []
    lower = src.lower()
    i = 0
    while True:
        j = lower.find("create table", i)
        if j < 0:
            break
        rest = src[j + len("create table") :]
        m = re.match(
            r"\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-zA-Z_][a-zA-Z0-9_]*)\s*\(",
            rest,
            re.I,
        )
        if not m:
            i = j + len("create table")
            continue
        name = m.group(1).lower()
        paren = j + len("create table") + m.end() - 1
        depth = 0
        end = None
        for idx in range(paren, len(src)):
            if src[idx] == "(":
                depth += 1
            elif src[idx] == ")":
                depth -= 1
                if depth == 0:
                    end = idx
                    break
        if end is None:
            break
        cols = []
        skip = {"constraint", "primary", "unique", "check", "foreign", "exclude"}
        for part in split_fields(src[paren + 1 : end]):
            line = part.strip()
            if not line:
                continue
            head = line.split()[0].lower().strip('"')
            if head in skip:
                continue
            quoted = re.match(r'"([^"]+)"', line)
            if quoted:
                cols.append(quoted.group(1).lower())
            else:
                ident = re.match(r"([a-zA-Z_][a-zA-Z0-9_]*)", line)
                if ident:
                    cols.append(ident.group(1).lower())
        found.append((name, cols))
        i = end + 1
    return found


def forbidden_hits(names):
    hits = []
    for name in names:
        for word in FORBIDDEN:
            safe = SAFE_SEGMENTS.get(word, set())
            for seg in name.split("_"):
                if word in seg and seg not in safe:
                    hits.append("%s contains %s" % (name, word))
                    break
    return hits


def secret_hits(sql):
    hits = []
    if "service_role" in sql.lower():
        hits.append("service_role")
    if "eyJ" in sql:
        hits.append("eyJ")
    if re.search(r"https?://", sql, re.I):
        hits.append("http url")
    return hits


def rls_problems(sql):
    src = strip_comments(sql)
    problems = []
    enables = []
    for table in ("profiles", "devices", "mailbox"):
        m = re.search(
            r"alter\s+table\s+(?:public\.)?%s\s+enable\s+row\s+level\s+security" % table,
            src,
            re.I,
        )
        if not m:
            problems.append("rls missing on %s" % table)
        else:
            enables.append(m.start())
    grants = [m.start() for m in re.finditer(r"\bgrant\b", src, re.I)]
    if grants and (not enables or min(grants) < max(enables)):
        problems.append("grant appears before row level security is enabled")
    if re.search(r"for\s+select\s+to\s+(anon|public)\b", src, re.I):
        problems.append("select granted to anon")
    if re.search(r"\bgrant\b[^;]*\bto\s+anon\b", src, re.I):
        problems.append("grant to anon")
    return problems


def identity_problems(sql):
    problems = []
    problems.extend(secret_hits(sql))
    found = {name: cols for name, cols in tables(sql)}
    for table, want in REQUIRED.items():
        got = found.get(table)
        if got is None:
            problems.append("missing table %s" % table)
            continue
        if got != want:
            problems.append("%s columns are %s" % (table, ", ".join(got) or "(none)"))
        problems.extend(forbidden_hits(got))
    problems.extend(rls_problems(sql))
    src = strip_comments(sql)
    if not re.search(r"username\s*~\s*'\^\[a-z0-9_\]\{3,32\}\$'", src):
        problems.append("username check missing")
    if "platform in ('web', 'ios', 'watchos', 'macos', 'linux')" not in src.lower():
        problems.append("platform check missing")
    if len(re.findall(r"references\s+auth\.users\s*\(\s*id\s*\)\s+on\s+delete\s+cascade", src, re.I)) < 3:
        problems.append("auth.users cascade missing")
    if len(re.findall(r"references\s+(?:public\.)?devices\s*\(\s*id\s*\)\s+on\s+delete\s+cascade", src, re.I)) < 2:
        problems.append("device cascade missing")
    insert = re.search(
        r"create\s+policy\s+\w+\s+on\s+(?:public\.)?mailbox\s+for\s+insert\b(.*?)(?:create\s+policy|\Z)",
        src,
        re.I | re.S,
    )
    if not insert or not all(
        bit in insert.group(1).lower()
        for bit in ("auth.uid()", "recipient_device_id", "sender_device_id")
    ):
        problems.append("mailbox insert does not require both devices")
    return problems


def expect_fail(label, sql, pred):
    if pred(sql):
        return
    raise SystemExit("FAIL: detector accepted %s" % label)


def expect_pass(label, sql, pred):
    if not pred(sql):
        return
    raise SystemExit("FAIL: detector rejected %s" % label)


# The detector has to fire. A check that only exits 0 is not a check.
expect_fail(
    "token column",
    "create table public.profiles (id uuid, mesh_token text);",
    lambda s: forbidden_hits([c for _, cols in tables(s) for c in cols]),
)
for bad in (
    "ip",
    "ip_address",
    "hostname",
    "host",
    "mac_address",
    "apns",
    "tailnet",
    "lat",
    "latitude",
    "lng",
    "screen",
    "screenshot",
    "recipient_ip",
    "platform_lat",
):
    expect_fail(bad, "", lambda s, name=bad: forbidden_hits([name]))

expect_pass(
    "platform and recipient",
    "",
    lambda s: forbidden_hits(
        ["platform", "recipient_device_id", "public_key", "ciphertext", "last_seen_at"]
    ),
)
expect_fail("service_role", "create role service_role;", secret_hits)
expect_fail("eyJ", "note eyJhbGciOiJub25lIn0", secret_hits)
expect_fail("http url", "see http://example.test/x", secret_hits)
expect_fail("https url", "see https://example.test/x", secret_hits)
expect_pass("plain comment", "-- identity only\n", secret_hits)
expect_fail(
    "missing rls",
    "create table public.profiles (id uuid); grant select on public.profiles to authenticated;",
    rls_problems,
)

path = sys.argv[1]
sql = open(path, encoding="utf-8").read()
problems = identity_problems(sql)
if problems:
    for item in problems:
        print("FAIL: %s" % item)
    raise SystemExit(1)

print("check-account-schema: OK")
print("supabase/account/001_identity.sql")
print("  tables: profiles, devices, mailbox")
print("  rls: enabled on all three before grants")
print("  forbidden column names: none")
print("  service_role, eyJ, http url: absent")
PY
