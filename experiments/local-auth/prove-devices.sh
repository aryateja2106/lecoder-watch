#!/bin/sh
# Prove a signed-in user can insert a device and a mailbox ciphertext
# through local PostgREST, and that the other user's access token cannot
# read those rows or address the first user's devices. Keys come from
# `supabase status` and are never written into the repo. This is not a
# scripts/check-*.sh file: check-all.sh runs every check, and those CI
# machines do not have this stack.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SQL="$ROOT/supabase/account/001_identity.sql"
EXPECTED_SQL_SHA="cd47695328f67abb077b62e48b670ed7cf78d6f4a916348958229d1862445253"

[ -f "$SQL" ] || { echo "FAIL: missing $SQL"; exit 1; }
command -v supabase >/dev/null || { echo "FAIL: supabase CLI is not installed"; exit 1; }
command -v psql >/dev/null || { echo "FAIL: psql is not installed"; exit 1; }
command -v python3 >/dev/null || { echo "FAIL: python3 is not installed"; exit 1; }

ACTUAL_SQL_SHA="$(python3 - "$SQL" <<'PY'
import hashlib, sys
print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
PY
)"
if [ "$ACTUAL_SQL_SHA" != "$EXPECTED_SQL_SHA" ]; then
  echo "FAIL: identity SQL hash changed"
  exit 1
fi

STATUS="$(mktemp)"
trap 'rm -f "$STATUS"' EXIT INT TERM
if ! supabase status -o env >"$STATUS" 2>/dev/null; then
  echo "FAIL: local supabase is not running. Start it on this machine; do not use a hosted project."
  exit 1
fi

python3 - "$STATUS" "$SQL" "$EXPECTED_SQL_SHA" <<'PY'
import base64, hashlib, json, os, re, subprocess, sys, urllib.error, urllib.parse, urllib.request
import secrets
from pathlib import Path

status_path, sql_path, expected_sha = sys.argv[1], sys.argv[2], sys.argv[3]
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
    print("FAIL: " + redact(message))
    sys.exit(1)

def redact(text):
    text = re.sub(r"postgres(?:ql)?://\S+", "postgresql://REDACTED", str(text))
    text = re.sub(r"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+", "REDACTED_JWT", text)
    text = re.sub(
        r"(?i)(apikey|authorization|access_token|refresh_token|bearer)\s*[:=]\s*\S+",
        r"\1=REDACTED",
        text,
    )
    return text

api = env.get("API_URL", "").rstrip("/")
anon = env.get("ANON_KEY", "")
db = env.get("DB_URL", "")
if not api or not anon or not db:
    fail("local status did not include API_URL, ANON_KEY, and DB_URL")
blob = api + " " + db
if "supabase.co" in blob or "zmisjteztezaqfflwbgf" in blob:
    fail("refusing a non-local stack")
if not re.match(r"https?://(127\.0\.0\.1|localhost)(:\d+)?$", api):
    fail("API_URL is not a local loopback address")
api_port = urllib.parse.urlparse(api).port
if api_port == 8899:
    fail("API_URL uses port 8899")

home = Path.home().resolve()
mesh = home / ".mesh"
home_before = sorted(p.name for p in home.iterdir())
mesh_before = mesh.exists()
if mesh_before:
    fail("refusing to run while ~/.mesh already exists")

sql_bytes = open(sql_path, "rb").read()
sql_sha = hashlib.sha256(sql_bytes).hexdigest()
if sql_sha != expected_sha:
    fail("identity SQL hash changed")
print("identity_sql_sha256: " + sql_sha)

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
if hashlib.sha256(open(sql_path, "rb").read()).hexdigest() != expected_sha:
    fail("identity SQL hash changed after apply")

FIXTURE_TOKEN = "mesh-token-sentinel"
FIXTURE_IP = "203.0.113.10"
FIXTURE_HOST = "fixture-mac"
PLATFORMS = ("web", "ios", "watchos", "macos", "linux")
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

def b64url(n):
    return base64.urlsafe_b64encode(secrets.token_bytes(n)).decode("ascii").rstrip("=")

def decode_b64url(value):
    pad = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(value + pad)

def jwt_claims(token):
    parts = str(token or "").split(".")
    if len(parts) != 3:
        return {}
    try:
        payload = json.loads(decode_b64url(parts[1]).decode("utf-8"))
    except Exception:
        return {}
    if not isinstance(payload, dict):
        return {}
    return payload

def error_text(data):
    if not isinstance(data, dict):
        return ""
    parts = []
    for key in ("error_description", "msg", "message", "error", "code", "hint"):
        value = data.get(key)
        if isinstance(value, str) and value:
            parts.append(value)
    return redact(" ".join(parts))

def http(method, url, body=None, token=None, prefer=None):
    parsed = urllib.parse.urlparse(url)
    if parsed.port == 8899 or ":8899" in url:
        fail("request used port 8899")
    if parsed.hostname not in ("127.0.0.1", "localhost"):
        fail("request left the local loopback")
    if "supabase.co" in url or "zmisjteztezaqfflwbgf" in url:
        fail("request left the local stack")
    bearer = token or anon
    for label, credential in (("apikey", anon), ("bearer", bearer)):
        role = jwt_claims(credential).get("role") or ""
        if role == "service_role":
            fail(label + " is the service role")
        if role not in ("anon", "authenticated"):
            fail(label + " credential is not anon or the signed-in user")
    data = None if body is None else json.dumps(body).encode()
    headers = {
        "apikey": anon,
        "Authorization": "Bearer " + bearer,
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
    parsed_body = None
    if raw:
        try:
            parsed_body = json.loads(raw)
        except json.JSONDecodeError:
            parsed_body = {"message": raw[:180]}
    return status, parsed_body, raw

def session_of(data):
    if not isinstance(data, dict) or not data.get("access_token"):
        return None
    user = data.get("user") or {}
    if not user.get("id"):
        return None
    claims = jwt_claims(data["access_token"])
    if claims.get("role") != "authenticated" or claims.get("sub") != user["id"]:
        return None
    meta = user.get("user_metadata") or {}
    return {
        "token": data["access_token"],
        "id": user["id"],
        "username": meta.get("username") or "",
    }

def sign_up(email, password, username):
    status, data, raw = http(
        "POST",
        api + "/auth/v1/signup",
        {"email": email, "password": password, "data": {"username": username}},
    )
    if status < 200 or status >= 300:
        fail("sign-up refused: " + str(status) + " " + error_text(data))
    if FIXTURE_TOKEN in raw or FIXTURE_IP in raw or FIXTURE_HOST in raw:
        fail("sign-up response carried a fixture secret")
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

def access_token_for(email, password, username):
    session = sign_up(email, password, username)
    if session:
        print("sign-up: access token returned")
        return session
    session = sign_in(email, password)
    print("sign-up accepted; access token from password grant")
    return session

def rows_for(path, token):
    status, data, raw = http("GET", api + path, token=token)
    if status != 200 or not isinstance(data, list):
        fail("select failed " + str(status) + " " + path.split("?")[0] + " " + error_text(data if isinstance(data, dict) else {}))
    return data, raw

def quote_uuid(value):
    if not UUID_RE.match(value or ""):
        fail("refusing to query a non-uuid id")
    return value

username_re = re.compile(r"^[a-z0-9_]{3,32}$")
user_a = "a" + secrets.token_hex(4)
user_b = "b" + secrets.token_hex(4)
if not username_re.match(user_a) or not username_re.match(user_b):
    fail("generated usernames do not match the profile pattern")
email_a = user_a + "@example.com"
email_b = user_b + "@example.com"
password_a = secrets.token_hex(16)
password_b = secrets.token_hex(16)

private_key = b64url(32)
if len(decode_b64url(private_key)) != 32:
    fail("private key fixture is not 32 bytes")

banned = (FIXTURE_TOKEN, FIXTURE_IP, FIXTURE_HOST, private_key)

def opaque(n):
    for _ in range(8):
        value = b64url(n)
        raw = decode_b64url(value)
        if len(raw) != n:
            continue
        if not re.fullmatch(r"[A-Za-z0-9_-]+", value):
            continue
        if any(item and item in value for item in banned):
            continue
        if value == private_key:
            continue
        return value
    fail("could not mint an opaque base64url value")

public_key = opaque(32)
ciphertext = opaque(48)
if public_key == private_key or private_key in public_key or private_key in ciphertext:
    fail("opaque value contains the private key")
if any(item in ciphertext or item in public_key for item in (FIXTURE_TOKEN, FIXTURE_IP, FIXTURE_HOST)):
    fail("opaque value contains a fixture secret")

session_a = access_token_for(email_a, password_a, user_a)
session_b = access_token_for(email_b, password_b, user_b)
if session_a["token"] == session_b["token"] or session_a["id"] == session_b["id"]:
    fail("the two users are not distinct")
if session_a["username"] != user_a or session_b["username"] != user_b:
    fail("sign-up metadata did not keep the username")
print("sign-up: two users")

def write_profile(session, username):
    body = {"id": session["id"], "username": username}
    if set(body) != {"id", "username"}:
        fail("profile write is not {id, username}")
    status, data, raw = http(
        "POST",
        api + "/rest/v1/profiles?on_conflict=id",
        body,
        token=session["token"],
        prefer="resolution=merge-duplicates,return=minimal",
    )
    if status < 200 or status >= 300:
        fail("profile write failed: " + str(status) + " " + error_text(data))
    if any(item in raw for item in banned):
        fail("profile write stored a fixture secret")

write_profile(session_a, user_a)
write_profile(session_b, user_b)

platform = "macos"
if platform not in PLATFORMS:
    fail("platform is not web, ios, watchos, macos, or linux")

def device_rows(token):
    rows, raw = rows_for("/rest/v1/devices?select=id,user_id,label,platform,public_key", token)
    if any(item in raw for item in banned):
        fail("device select returned a fixture secret")
    return rows

if device_rows(session_a["token"]):
    fail("user A already has devices before the insert")

rejected_keys = []

def reject_column(column):
    body = {
        "user_id": session_a["id"],
        "label": "rejected-" + column.replace("_", ""),
        "platform": platform,
        "public_key": opaque(32),
        column: {
            "token": FIXTURE_TOKEN,
            "ip": FIXTURE_IP,
            "hostname": FIXTURE_HOST,
            "private_key": private_key,
        }[column],
    }
    if column not in body or set(body) != {"user_id", "label", "platform", "public_key", column}:
        fail("rejected device body did not include " + column)
    status, data, raw = http(
        "POST",
        api + "/rest/v1/devices",
        body,
        token=session_a["token"],
        prefer="return=representation",
    )
    message = error_text(data)
    if status != 400 or column not in message:
        fail("device POST including " + column + " was not rejected: " + str(status) + " " + message)
    if device_rows(session_a["token"]):
        fail("device POST including " + column + " stored a row")
    rejected_keys.append(body["public_key"])
    print("rejected " + column + " column: " + str(status))

for column in ("token", "ip", "hostname", "private_key"):
    reject_column(column)

device_body = {
    "user_id": session_a["id"],
    "label": "desk",
    "platform": platform,
    "public_key": public_key,
}
if set(device_body) != {"user_id", "label", "platform", "public_key"}:
    fail("device insert keys are not user_id, label, platform, public_key")
if any(key in device_body for key in ("token", "ip", "hostname", "private_key")):
    fail("device insert includes a forbidden column")
device_status, devices, device_raw = http(
    "POST",
    api + "/rest/v1/devices",
    device_body,
    token=session_a["token"],
    prefer="return=representation",
)
if device_status not in (200, 201) or not isinstance(devices, list) or len(devices) != 1:
    fail("device insert failed: " + str(device_status) + " " + error_text(devices if isinstance(devices, dict) else {}))
device = devices[0]
device_id = device.get("id") or ""
if not UUID_RE.match(device_id):
    fail("device insert did not return an id")
if device.get("user_id") != session_a["id"] or device.get("label") != "desk":
    fail("device insert did not store this user's label")
if device.get("platform") != platform:
    fail("device insert did not store the platform")
if device.get("public_key") != public_key:
    fail("device insert did not store the public key")
if len(decode_b64url(device.get("public_key") or "")) != 32:
    fail("stored public key is not 32 bytes")
forbidden_columns = {"token", "ip", "hostname", "private_key"}
if forbidden_columns.intersection(device):
    fail("device representation includes a forbidden column")
if any(item in device_raw for item in banned):
    fail("device representation contains a fixture secret")
print("device insert keys: user_id, label, platform, public_key")
print("device platform: " + platform)
print("public_key_bytes: 32")
print("public_key_is_private_key: false")

stored_devices = device_rows(session_a["token"])
if len(stored_devices) != 1 or stored_devices[0].get("id") != device_id:
    fail("owner could not read the inserted device")
if stored_devices[0].get("public_key") != public_key:
    fail("stored public key does not match the insert")
for extra in rejected_keys:
    if any(row.get("public_key") == extra for row in stored_devices):
        fail("a rejected device POST was stored")

mailbox_body = {
    "user_id": session_a["id"],
    "recipient_device_id": device_id,
    "sender_device_id": device_id,
    "ciphertext": ciphertext,
    "expires_at": "2030-01-01T00:00:00Z",
}
if set(mailbox_body) != {
    "user_id",
    "recipient_device_id",
    "sender_device_id",
    "ciphertext",
    "expires_at",
}:
    fail("mailbox insert is not the ciphertext row")
if any(key in mailbox_body for key in ("token", "ip", "hostname", "private_key")):
    fail("mailbox insert includes a forbidden column")
box_status, boxes, box_raw = http(
    "POST",
    api + "/rest/v1/mailbox",
    mailbox_body,
    token=session_a["token"],
    prefer="return=representation",
)
if box_status not in (200, 201) or not isinstance(boxes, list) or len(boxes) != 1:
    fail("mailbox insert failed: " + str(box_status) + " " + error_text(boxes if isinstance(boxes, dict) else {}))
box = boxes[0]
if box.get("ciphertext") != ciphertext:
    fail("mailbox representation did not return the ciphertext")
if forbidden_columns.intersection(box):
    fail("mailbox representation includes a forbidden column")
if any(item in (box.get("ciphertext") or "") for item in banned):
    fail("stored ciphertext contains a fixture secret")
if box.get("user_id") != session_a["id"]:
    fail("mailbox row is not owned by user A")
if box.get("recipient_device_id") != device_id or box.get("sender_device_id") != device_id:
    fail("mailbox row does not reference user A's device")
print("mailbox insert: ciphertext only")

own_boxes, own_raw = rows_for(
    "/rest/v1/mailbox?select=id,user_id,recipient_device_id,sender_device_id,ciphertext",
    session_a["token"],
)
if len(own_boxes) != 1 or own_boxes[0].get("ciphertext") != ciphertext:
    fail("owner could not read their mailbox ciphertext")
if any(item in own_raw for item in banned):
    fail("owner mailbox read contains a fixture secret")

user_a_sql = quote_uuid(session_a["id"])
user_b_sql = quote_uuid(session_b["id"])
device_sql = quote_uuid(device_id)
db_ciphertext = psql(
    "select ciphertext from public.mailbox where user_id = '" + user_a_sql + "'"
).strip().splitlines()
if db_ciphertext != [ciphertext]:
    fail("database ciphertext does not match the inserted blob")
db_devices = psql(
    "select public_key from public.devices where user_id = '" + user_a_sql + "'"
).strip().splitlines()
if db_devices != [public_key]:
    fail("database public key does not match the insert")
stored_text = psql(
    "select coalesce(json_agg(row_to_json(d))::text, '[]') from public.devices d "
    "where user_id = '" + user_a_sql + "'"
) + psql(
    "select coalesce(json_agg(row_to_json(m))::text, '[]') from public.mailbox m "
    "where user_id = '" + user_a_sql + "'"
)
for item, label in (
    (FIXTURE_TOKEN, "token"),
    (FIXTURE_IP, "ip"),
    (FIXTURE_HOST, "hostname"),
    (private_key, "private_key"),
):
    if item in stored_text or item in ciphertext or item in public_key:
        fail("stored rows contain the fixture " + label)
print("ciphertext_has_token: false")
print("ciphertext_has_ip: false")
print("ciphertext_has_hostname: false")
print("ciphertext_has_private_key: false")

a_filter = urllib.parse.quote(session_a["id"])
device_filter = urllib.parse.quote(device_id)

def expect_empty(path):
    rows, raw = rows_for(path, session_b["token"])
    if rows:
        fail("second user can select " + path.split("?")[0])
    if any(item in raw for item in (ciphertext, public_key, private_key, FIXTURE_TOKEN, FIXTURE_IP, FIXTURE_HOST)):
        fail("second user select returned a secret")
    return len(rows)

b_profile = expect_empty("/rest/v1/profiles?id=eq." + a_filter + "&select=id,username")
b_devices = expect_empty("/rest/v1/devices?user_id=eq." + a_filter + "&select=id,user_id,label,platform,public_key")
b_device_by_id = expect_empty("/rest/v1/devices?id=eq." + device_filter + "&select=id,user_id")
b_mailbox = expect_empty("/rest/v1/mailbox?user_id=eq." + a_filter + "&select=id,ciphertext")
b_mailbox_by_device = expect_empty(
    "/rest/v1/mailbox?recipient_device_id=eq." + device_filter + "&select=id,ciphertext"
)
if any(value != 0 for value in (b_profile, b_devices, b_device_by_id, b_mailbox, b_mailbox_by_device)):
    fail("second user select was not empty")
unfiltered_devices, _ = rows_for("/rest/v1/devices?select=id,user_id", session_b["token"])
unfiltered_mailbox, _ = rows_for("/rest/v1/mailbox?select=id,user_id,ciphertext", session_b["token"])
unfiltered_profiles, _ = rows_for("/rest/v1/profiles?select=id,username", session_b["token"])
if unfiltered_devices or unfiltered_mailbox:
    fail("second user can select another user's devices or mailbox without a filter")
profile_ids = {row.get("id") for row in unfiltered_profiles}
if session_a["id"] in profile_ids or profile_ids != {session_b["id"]}:
    fail("second user can select the first user's profile")
own_profile, _ = rows_for(
    "/rest/v1/profiles?id=eq." + urllib.parse.quote(session_b["id"]) + "&select=id,username",
    session_b["token"],
)
if own_profile != [{"id": session_b["id"], "username": user_b}]:
    fail("second user cannot read their own profile")
print("b_sees_a_profile: 0")
print("b_sees_a_devices: 0")
print("b_sees_a_mailbox: 0")

intrusion = {
    "user_id": session_b["id"],
    "recipient_device_id": device_id,
    "sender_device_id": device_id,
    "ciphertext": opaque(48),
    "expires_at": "2030-01-01T00:00:00Z",
}
if intrusion["recipient_device_id"] != device_id or intrusion["sender_device_id"] != device_id:
    fail("intrusion does not reference user A's device ids")
intrude_status, intrude_data, intrude_raw = http(
    "POST",
    api + "/rest/v1/mailbox",
    intrusion,
    token=session_b["token"],
    prefer="return=representation",
)
intrude_message = error_text(intrude_data)
if intrude_status < 400 or (
    "row-level security" not in intrude_message.lower() and "42501" not in intrude_message
):
    fail("second user mailbox insert was not refused by row level security: " + str(intrude_status) + " " + intrude_message)
if ciphertext in intrude_raw or public_key in intrude_raw or private_key in intrude_raw:
    fail("refused mailbox insert echoed a stored secret")
b_after, _ = rows_for("/rest/v1/mailbox?select=id", session_b["token"])
a_after, _ = rows_for("/rest/v1/mailbox?select=id,ciphertext", session_a["token"])
if b_after or len(a_after) != 1 or a_after[0].get("ciphertext") != ciphertext:
    fail("refused mailbox insert changed the stored rows")
db_mailbox_count = psql(
    "select count(*) from public.mailbox where user_id in ('" + user_a_sql + "', '" + user_b_sql + "')"
).strip()
db_b_count = psql(
    "select count(*) from public.mailbox where recipient_device_id = '" + device_sql + "' and user_id = '" + user_b_sql + "'"
).strip()
if db_mailbox_count != "1" or db_b_count != "0":
    fail("database stored the second user's mailbox row")
print("b_insert_a_devices: refused")

if hashlib.sha256(open(sql_path, "rb").read()).hexdigest() != expected_sha:
    fail("identity SQL hash changed")
home_after = sorted(p.name for p in home.iterdir())
if home_after != home_before or mesh.exists():
    fail("wrote under the home directory")
print("requests to port 8899: none")
print("home_write: false")
print("mesh_dir: false")
print("local-device-rest: OK")
PY
