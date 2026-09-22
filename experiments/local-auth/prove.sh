#!/bin/sh
# Prove email sign-up, sign-in, recovery, and profile isolation against a
# Supabase stack that is already running on this machine. The anon key and
# database URL are read from `supabase status` at runtime and are never
# written into the repo. This is not a scripts/check-*.sh file: check-all.sh
# runs every check, and those CI machines do not have this stack.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SQL="$ROOT/supabase/account/001_identity.sql"

[ -f "$SQL" ] || { echo "FAIL: missing $SQL"; exit 1; }
command -v supabase >/dev/null || { echo "FAIL: supabase CLI is not installed"; exit 1; }
command -v psql >/dev/null || { echo "FAIL: psql is not installed"; exit 1; }
command -v python3 >/dev/null || { echo "FAIL: python3 is not installed"; exit 1; }

STATUS="$(mktemp)"
trap 'rm -f "$STATUS"' EXIT INT TERM
if ! supabase status -o env >"$STATUS" 2>/dev/null; then
  echo "FAIL: local supabase is not running. Start it on this machine; do not use a hosted project."
  exit 1
fi

python3 - "$STATUS" "$SQL" <<'PY'
import json, os, re, subprocess, sys, time, urllib.error, urllib.parse, urllib.request
import secrets

status_path, sql_path = sys.argv[1], sys.argv[2]
env = {}
with open(status_path, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not re.match(r"^[A-Z0-9_]+=", line):
            continue
        key, value = line.split("=", 1)
        if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
            value = value[1:-1]
        env[key] = value
os.remove(status_path)

def fail(message):
    print("FAIL: " + message)
    sys.exit(1)

api = env.get("API_URL", "").rstrip("/")
anon = env.get("ANON_KEY", "")
db = env.get("DB_URL", "")
mail = env.get("MAILPIT_URL", "").rstrip("/")
if not api or not anon or not db or not mail:
    fail("local status did not include API_URL, ANON_KEY, DB_URL, and MAILPIT_URL")
blob = api + " " + db + " " + mail
if "supabase.co" in blob or "zmisjteztezaqfflwbgf" in blob:
    fail("refusing a non-local stack")
if not re.match(r"https?://(127\.0\.0\.1|localhost)(:\d+)?$", api):
    fail("API_URL is not a local loopback address")
if not re.match(r"https?://(127\.0\.0\.1|localhost)(:\d+)?$", mail):
    fail("MAILPIT_URL is not a local loopback address")

def redact(text):
    text = re.sub(r"postgres(?:ql)?://\S+", "postgresql://REDACTED", text)
    text = re.sub(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", "REDACTED_JWT", text)
    text = re.sub(r"(?i)(apikey|authorization|access_token|refresh_token|bearer)\s*[:=]\s*\S+", r"\1=REDACTED", text)
    return text

def psql(sql):
    result = subprocess.run(
        ["psql", db, "-v", "ON_ERROR_STOP=1", "-At", "-c", sql],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        fail("database query failed: " + redact(result.stderr.strip() or result.stdout.strip()))
    return result.stdout

present = psql("select to_regclass('public.profiles') is not null")
if present.strip() != "t":
    applied = subprocess.run(
        ["psql", db, "-v", "ON_ERROR_STOP=1", "-f", sql_path],
        capture_output=True, text=True,
    )
    if applied.returncode != 0:
        fail("identity SQL failed: " + redact(applied.stderr.strip()))
    print(applied.stdout.strip())
else:
    print("identity SQL already applied")
psql("notify pgrst, 'reload schema'")

def http(method, url, body=None, token=None, prefer=None):
    data = None if body is None else json.dumps(body).encode()
    headers = {
        "apikey": anon,
        "Authorization": "Bearer " + (token or anon),
        "Accept": "application/json",
    }
    if body is not None:
        headers["Content-Type"] = "application/json"
    if prefer:
        headers["Prefer"] = prefer
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read().decode()
            status = response.status
    except urllib.error.HTTPError as error:
        raw = error.read().decode()
        status = error.code
    parsed = None
    if raw:
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            parsed = {"message": raw[:180]}
    return status, parsed, raw

def session_of(data):
    if not isinstance(data, dict) or not data.get("access_token"):
        return None
    user = data.get("user") or {}
    if not user.get("id"):
        return None
    meta = user.get("user_metadata") or {}
    return {
        "token": data["access_token"],
        "id": user["id"],
        "username": meta.get("username") or "",
    }

def error_text(data):
    if not isinstance(data, dict):
        return ""
    for key in ("error_description", "msg", "message", "error", "code"):
        value = data.get(key)
        if isinstance(value, str) and value:
            return redact(value)
    return ""

def sign_up(email, password, username):
    status, data, raw = http(
        "POST",
        api + "/auth/v1/signup",
        {"email": email, "password": password, "data": {"username": username}},
    )
    if status < 200 or status >= 300:
        fail("sign-up refused: " + str(status) + " " + error_text(data))
    return session_of(data)

def sign_in(email, password):
    status, data, raw = http(
        "POST",
        api + "/auth/v1/token?grant_type=password",
        {"email": email, "password": password},
    )
    session = session_of(data)
    if status < 200 or status >= 300 or not session:
        fail("sign-in did not return a session: " + str(status) + " " + error_text(data))
    return session

username_re = re.compile(r"^[a-z0-9_]{3,32}$")
user_a = "a" + secrets.token_hex(4)
user_b = "b" + secrets.token_hex(4)
if not username_re.match(user_a) or not username_re.match(user_b):
    fail("generated usernames do not match the profile pattern")
email_a = user_a + "@example.com"
email_b = user_b + "@example.com"
password_a = secrets.token_hex(16)
password_b = secrets.token_hex(16)
marker = "sealed-" + secrets.token_hex(16)

sign_up(email_a, password_a, user_a)
session_a = sign_in(email_a, password_a)
print("sign-up: accepted for a username matching ^[a-z0-9_]{3,32}$")
print("sign-in: session returned")
if session_a["username"] != user_a:
    fail("sign-in metadata did not keep the username")

bad_body = {"id": session_a["id"], "username": "Bad-Name"}
bad_status, bad_data, _ = http(
    "POST",
    api + "/rest/v1/profiles?on_conflict=id",
    bad_body,
    token=session_a["token"],
    prefer="resolution=merge-duplicates,return=minimal",
)
if bad_status < 400:
    fail("username outside ^[a-z0-9_]{3,32}$ was stored")
print("username outside ^[a-z0-9_]{3,32}$: rejected " + str(bad_status))

profile_body = {"id": session_a["id"], "username": user_a}
if set(profile_body) != {"id", "username"}:
    fail("profile write is not {id, username}")
saved_status, saved_data, _ = http(
    "POST",
    api + "/rest/v1/profiles?on_conflict=id",
    profile_body,
    token=session_a["token"],
    prefer="resolution=merge-duplicates,return=minimal",
)
if saved_status < 200 or saved_status >= 300:
    fail("profile write failed: " + str(saved_status) + " " + error_text(saved_data))

read_status, rows, _ = http(
    "GET",
    api + "/rest/v1/profiles?id=eq." + urllib.parse.quote(session_a["id"]) + "&select=id,username",
    token=session_a["token"],
)
if read_status != 200 or rows != [profile_body]:
    fail("profile read was not {id, username}")
print("profile write and read: {id, username}")

full_status, full_rows, _ = http(
    "GET",
    api + "/rest/v1/profiles?id=eq." + urllib.parse.quote(session_a["id"]) + "&select=*",
    token=session_a["token"],
)
if full_status != 200 or len(full_rows) != 1:
    fail("profile row missing after write")
if set(full_rows[0]) != {"id", "username", "created_at"}:
    fail("profile columns are not id, username, created_at")
print("profile columns: id, username, created_at")

device_status, devices, _ = http(
    "POST",
    api + "/rest/v1/devices",
    {
        "user_id": session_a["id"],
        "label": "wrist",
        "platform": "web",
        "public_key": "pub-" + user_a,
    },
    token=session_a["token"],
    prefer="return=representation",
)
if device_status not in (200, 201) or not isinstance(devices, list) or len(devices) != 1:
    fail("device insert failed: " + str(device_status) + " " + error_text(devices if isinstance(devices, dict) else {}))
device_id = devices[0]["id"]

box_status, boxes, _ = http(
    "POST",
    api + "/rest/v1/mailbox",
    {
        "user_id": session_a["id"],
        "recipient_device_id": device_id,
        "sender_device_id": device_id,
        "ciphertext": marker,
        "expires_at": "2030-01-01T00:00:00Z",
    },
    token=session_a["token"],
    prefer="return=representation",
)
if box_status not in (200, 201) or not isinstance(boxes, list) or len(boxes) != 1:
    fail("mailbox insert failed: " + str(box_status) + " " + error_text(boxes if isinstance(boxes, dict) else {}))

own_box_status, own_boxes, _ = http(
    "GET",
    api + "/rest/v1/mailbox?select=id,ciphertext",
    token=session_a["token"],
)
if own_box_status != 200 or not any(row.get("ciphertext") == marker for row in own_boxes or []):
    fail("owner could not read their mailbox row")

sign_up(email_b, password_b, user_b)
session_b = sign_in(email_b, password_b)
profile_b = {"id": session_b["id"], "username": user_b}
saved_b, saved_b_data, _ = http(
    "POST",
    api + "/rest/v1/profiles?on_conflict=id",
    profile_b,
    token=session_b["token"],
    prefer="resolution=merge-duplicates,return=minimal",
)
if saved_b < 200 or saved_b >= 300:
    fail("second profile write failed: " + str(saved_b) + " " + error_text(saved_b_data))

def rows_for(path, token):
    status, data, raw = http("GET", api + path, token=token)
    if status != 200 or not isinstance(data, list):
        fail("select failed " + str(status) + " " + path.split("?")[0] + " " + error_text(data if isinstance(data, dict) else {}))
    if marker in raw and token == session_b["token"]:
        fail("second user select returned mailbox plaintext")
    return data

b_profiles = rows_for("/rest/v1/profiles?select=id,username", session_b["token"])
b_profile_ids = {row.get("id") for row in b_profiles}
if session_a["id"] in b_profile_ids or b_profile_ids != {session_b["id"]}:
    fail("second user can select the first user's profile")
a_filter = urllib.parse.quote(session_a["id"])
if rows_for("/rest/v1/profiles?id=eq." + a_filter + "&select=id,username", session_b["token"]):
    fail("second user can select the first profile by id")
if rows_for("/rest/v1/devices?user_id=eq." + a_filter + "&select=id,user_id,label,platform", session_b["token"]):
    fail("second user can select the first user's devices")
if rows_for("/rest/v1/devices?select=id,user_id", session_b["token"]):
    fail("second user can select another user's devices without a filter")
if rows_for("/rest/v1/mailbox?user_id=eq." + a_filter + "&select=id,ciphertext", session_b["token"]):
    fail("second user can select the first user's mailbox")
if rows_for("/rest/v1/mailbox?select=id,ciphertext", session_b["token"]):
    fail("second user can select another user's mailbox without a filter")
print("second user: cannot select the first profile, devices, or mailbox")

columns = psql(
    "select table_name || ' ' || column_name from information_schema.columns "
    "where table_schema = 'public' and table_name in ('profiles','devices','mailbox') "
    "order by table_name, ordinal_position"
).strip().splitlines()
by_table = {"profiles": [], "devices": [], "mailbox": []}
for line in columns:
    table, column = line.split(" ", 1)
    by_table[table].append(column)
expected = {
    "profiles": ["id", "username", "created_at"],
    "devices": ["id", "user_id", "label", "platform", "public_key", "created_at", "last_seen_at"],
    "mailbox": ["id", "user_id", "recipient_device_id", "sender_device_id", "ciphertext", "created_at", "expires_at"],
}
for table, want in expected.items():
    if by_table[table] != want:
        fail(table + " columns are " + ",".join(by_table[table]))

safe_segments = {"ip": {"recipient", "ciphertext"}, "lat": {"platform"}}
banned = ("token", "hostname", "ip", "private")
for table in ("devices", "mailbox"):
    for column in by_table[table]:
        for segment in column.split("_"):
            for word in banned:
                if word in segment and segment not in safe_segments.get(word, set()):
                    fail(table + "." + column + " contains " + word)
print("devices columns: " + ", ".join(by_table["devices"]))
print("mailbox columns: " + ", ".join(by_table["mailbox"]))
print("devices and mailbox: no token, ip, hostname, or private key columns")

redirect = "http://127.0.0.1:3000/account/reset"
recover_status, recover_data, recover_raw = http(
    "POST",
    api + "/auth/v1/recover?redirect_to=" + urllib.parse.quote(redirect, safe=""),
    {"email": email_a},
)
if recover_status < 200 or recover_status >= 300:
    fail("recovery request refused: " + str(recover_status) + " " + error_text(recover_data))
if marker in recover_raw:
    fail("recovery response returned mailbox plaintext")
print("recovery request: accepted " + str(recover_status))
print("recovery response contains mailbox plaintext: no")

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def recovery_token():
    deadline = time.time() + 20
    while time.time() < deadline:
        with urllib.request.urlopen(mail + "/api/v1/messages") as response:
            listing = json.loads(response.read().decode())
        for item in listing.get("messages") or []:
            recipients = []
            for person in item.get("To") or []:
                recipients.append((person.get("Address") or "").lower())
            if email_a.lower() not in recipients:
                continue
            with urllib.request.urlopen(mail + "/api/v1/message/" + item["ID"]) as response:
                message = json.loads(response.read().decode())
            text = (message.get("HTML") or "") + "\n" + (message.get("Text") or "")
            if marker in text:
                fail("recovery mail returned mailbox plaintext")
            urls = re.findall(r"https?://[^\s\"'<>]+", text)
            for url in urls:
                opener = urllib.request.build_opener(NoRedirect)
                try:
                    followed = opener.open(url)
                    location = followed.headers.get("Location") or ""
                    body = followed.read().decode(errors="replace")
                except urllib.error.HTTPError as error:
                    location = error.headers.get("Location") or ""
                    body = error.read().decode(errors="replace")
                if marker in location or marker in body:
                    fail("reset redirect returned mailbox plaintext")
                parsed = urllib.parse.urlparse(location or url)
                fragment = urllib.parse.parse_qs(parsed.fragment)
                query = urllib.parse.parse_qs(parsed.query)
                token = (fragment.get("access_token") or query.get("access_token") or [""])[0]
                kind = (fragment.get("type") or query.get("type") or [""])[0]
                if token and kind == "recovery":
                    return token
        time.sleep(0.5)
    return ""

token = recovery_token()
if not token:
    fail("local auth server accepted recovery but no recovery session was issued")
new_password = secrets.token_hex(16)
reset_status, reset_data, reset_raw = http(
    "PUT",
    api + "/auth/v1/user",
    {"password": new_password},
    token=token,
)
if reset_status < 200 or reset_status >= 300:
    fail("reset refused: " + str(reset_status) + " " + error_text(reset_data))
if marker in reset_raw or "ciphertext" in reset_raw:
    fail("reset returned mailbox plaintext")
if not isinstance(reset_data, dict) or not reset_data.get("id"):
    fail("reset did not return the auth user")
print("reset: accepted " + str(reset_status))
print("reset response contains mailbox plaintext: no")
print("local-auth-proof: OK")
PY
