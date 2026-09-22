#!/bin/sh
# Prove device-sync bodies survive the identity row level security from
# pull request 135. The SQL in this file is that migration, copied unchanged,
# and it is applied only to a throwaway cluster under /tmp. The registration
# and ciphertext come from the existing device-sync helper. This check does
# not rebuild the seal, the key file, or the round trip, and it does not open
# a cloud database.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/experiments/device-sync/client.ts"
SEAL="$ROOT/experiments/sealed-mailbox/seal.ts"
EXPECTED_SHA256="cd47695328f67abb077b62e48b670ed7cf78d6f4a916348958229d1862445253"

command -v node >/dev/null 2>&1 || { echo "FAIL: check-sync-rls: node is not installed"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FAIL: check-sync-rls: python3 is not installed"; exit 1; }
[ -f "$CLIENT" ] || { echo "FAIL: check-sync-rls: missing $CLIENT"; exit 1; }
[ -f "$SEAL" ] || { echo "FAIL: check-sync-rls: missing $SEAL"; exit 1; }

REAL_HOME="${HOME:-}"
TMP="$(mktemp -d /tmp/sync-rls.XXXXXX)"
case "$TMP" in
  /tmp/sync-rls.*) ;;
  *) echo "FAIL: check-sync-rls: temp directory is not under /tmp"; exit 1 ;;
esac
case "$TMP" in
  */.mesh|*/.mesh/*)
    echo "FAIL: check-sync-rls: temp directory is a mesh directory"
    exit 1
    ;;
esac
if [ -n "$REAL_HOME" ]; then
  case "$TMP" in
    "$REAL_HOME"|"$REAL_HOME"/*)
      echo "FAIL: check-sync-rls: temp directory is under the home directory"
      exit 1
      ;;
  esac
fi

PGDATA="$TMP/pg"
SOCK="$TMP/sock"
HOME_DIR="$TMP/home"
SQL_FILE="$TMP/001_identity.sql"
PG_CTL=""
cleanup() {
  status=$?
  if [ -n "$PG_CTL" ] && [ -d "$PGDATA" ]; then
    "$PG_CTL" -D "$PGDATA" -m immediate stop >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP"
  exit "$status"
}
trap cleanup EXIT

mkdir -p "$HOME_DIR" "$SOCK"
chmod 700 "$HOME_DIR" "$SOCK"

# Identity SQL from pull request 135, unchanged. The hash gate fails if a
# byte in this copy drifts from that file.
cat > "$SQL_FILE" <<'END_IDENTITY_SQL'
-- Identity only. Never store mesh tokens, tailnet addresses, or host lists.
-- Do not run this on the telemetry project.
-- These tables hold a username, a user-typed device label, a platform enum,
-- a device public key, and sealed mailbox ciphertext. The secret that opens
-- a machine is not a column. Deleting the auth user cascades profiles,
-- devices, and mailbox rows.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null,
  created_at timestamptz not null default now(),
  constraint profiles_username_unique unique (username),
  constraint profiles_username_shape check (username ~ '^[a-z0-9_]{3,32}$')
);

alter table public.profiles enable row level security;

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  label text not null,
  platform text not null,
  public_key text not null,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint devices_user_public_key unique (user_id, public_key),
  constraint devices_label_len check (char_length(label) between 1 and 64),
  constraint devices_platform_kind check (platform in ('web', 'ios', 'watchos', 'macos', 'linux')),
  constraint devices_public_key_len check (char_length(public_key) between 1 and 512)
);

alter table public.devices enable row level security;

create table public.mailbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  recipient_device_id uuid not null references public.devices (id) on delete cascade,
  sender_device_id uuid not null references public.devices (id) on delete cascade,
  ciphertext text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  constraint mailbox_ciphertext_len check (char_length(ciphertext) between 1 and 16384)
);

alter table public.mailbox enable row level security;

create policy profiles_select
  on public.profiles
  for select
  to authenticated
  using (id = auth.uid());

create policy profiles_insert
  on public.profiles
  for insert
  to authenticated
  with check (id = auth.uid());

create policy profiles_update
  on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy profiles_delete
  on public.profiles
  for delete
  to authenticated
  using (id = auth.uid());

create policy devices_select
  on public.devices
  for select
  to authenticated
  using (auth.uid() = user_id);

create policy devices_insert
  on public.devices
  for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy devices_update
  on public.devices
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy devices_delete
  on public.devices
  for delete
  to authenticated
  using (auth.uid() = user_id);

create policy mailbox_select
  on public.mailbox
  for select
  to authenticated
  using (auth.uid() = user_id);

create policy mailbox_insert
  on public.mailbox
  for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.devices
      where id = recipient_device_id
        and user_id = auth.uid()
    )
    and exists (
      select 1 from public.devices
      where id = sender_device_id
        and user_id = auth.uid()
    )
  );

create policy mailbox_delete
  on public.mailbox
  for delete
  to authenticated
  using (auth.uid() = user_id);

revoke all on table public.profiles from public;
revoke all on table public.profiles from anon;
revoke all on table public.devices from public;
revoke all on table public.devices from anon;
revoke all on table public.mailbox from public;
revoke all on table public.mailbox from anon;

grant select, insert, update, delete on table public.profiles to authenticated;
grant select, insert, update, delete on table public.devices to authenticated;
grant select, insert, delete on table public.mailbox to authenticated;
END_IDENTITY_SQL

sha256sum "$SQL_FILE" > "$TMP/sql.sha"
SQL_SHA256="$(awk 'NR==1 { print $1 }' "$TMP/sql.sha")"
if [ "$SQL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "FAIL: check-sync-rls: identity SQL does not match the pull request file"
  exit 1
fi
if grep -E -q 'https?://|postgres(ql)?://' "$SQL_FILE"; then
  echo "FAIL: check-sync-rls: identity SQL contains a url"
  exit 1
fi
echo "identity_sql_sha256: $SQL_SHA256"

PG_BIN=""
for dir in /usr/lib/postgresql/*/bin; do
  if [ -x "$dir/initdb" ] && [ -x "$dir/pg_ctl" ]; then
    PG_BIN="$dir"
    break
  fi
done
if [ -z "$PG_BIN" ]; then
  echo "FAIL: check-sync-rls: local postgres was not found"
  exit 1
fi
PG_CTL="$PG_BIN/pg_ctl"
PSQL="$(command -v psql || true)"
if [ -z "$PSQL" ] && [ -x "$PG_BIN/psql" ]; then
  PSQL="$PG_BIN/psql"
fi
if [ -z "$PSQL" ]; then
  echo "FAIL: check-sync-rls: psql was not found"
  exit 1
fi

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
case "$PORT" in
  ''|*[!0-9]*) echo "FAIL: check-sync-rls: could not choose a local port"; exit 1 ;;
esac

export HOME="$HOME_DIR"
unset DATABASE_URL SUPABASE_URL SUPABASE_DB_URL PGPASSWORD PGHOST PGPORT PGUSER PGDATABASE || true
export PGPASSFILE="$TMP/no-pgpass"

"$PG_BIN/initdb" -D "$PGDATA" -U postgres --auth-local=trust --auth-host=reject --no-instructions -E UTF8 --locale=C >/dev/null
"$PG_CTL" -D "$PGDATA" -l "$TMP/postgres.log" -w \
  -o "-c listen_addresses='' -c unix_socket_directories=${SOCK} -c port=${PORT} -c fsync=off -c log_statement=none" \
  start >/dev/null

psql_local() {
  "$PSQL" -X -q -v ON_ERROR_STOP=1 -h "$SOCK" -p "$PORT" -U postgres -d postgres "$@"
}

# The identity SQL references auth.users and auth.uid(). These two names are
# the local stand-in that lets that file run. They are not a second copy of
# profiles, devices, or mailbox.
psql_local <<'END_AUTH_STUB'
create schema auth;

create table auth.users (
  id uuid primary key
);

create function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create role anon nologin nosuperuser nobypassrls;
create role authenticated nologin nosuperuser nobypassrls;

grant usage on schema public to anon, authenticated;
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
END_AUTH_STUB

psql_local -f "$SQL_FILE" >/dev/null

env -u DATABASE_URL -u SUPABASE_URL -u SUPABASE_DB_URL -u PGPASSWORD \
  HOME="$HOME_DIR" \
  PGPASSFILE="$TMP/no-pgpass" \
  ROOT="$ROOT" \
  PSQL="$PSQL" \
  PGSOCKET="$SOCK" \
  PGPORT="$PORT" \
  TMP="$TMP" \
  NODE_NO_WARNINGS=1 \
  node --experimental-strip-types <<'END_NODE'
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const { buildDeviceSyncBodies } = require(process.env.ROOT + "/experiments/device-sync/client.ts");
const { generateDeviceKeyPair } = require(process.env.ROOT + "/experiments/sealed-mailbox/seal.ts");

const TOKEN = "fixture-token-not-a-secret";
const ADDRESS = "203.0.113.10";
const HOST = "fixture-mac";

function fail(message) {
  console.error(`FAIL: check-sync-rls: ${message}`);
  process.exit(1);
}

function scalarEncodings(privateKey) {
  const jwk = privateKey.export({ format: "jwk" });
  if (typeof jwk.d !== "string") fail("device private key has no scalar");
  const raw = Buffer.from(jwk.d, "base64url");
  if (raw.length !== 32) fail("device private key is not 32 bytes");
  const pem = String(privateKey.export({ format: "pem", type: "pkcs8" }));
  const pemBody = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  return { raw, texts: [jwk.d, raw.toString("base64"), raw.toString("hex"), pemBody] };
}

function lit(value, what) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value)) fail(`${what} is not safe to store`);
  return `'${value}'`;
}

function psql(sql) {
  const socket = process.env.PGSOCKET;
  const port = process.env.PGPORT;
  const tmp = process.env.TMP;
  if (typeof socket !== "string" || typeof tmp !== "string" || !socket.startsWith(tmp + path.sep)) {
    fail("postgres socket is outside the temp directory");
  }
  const result = spawnSync(
    process.env.PSQL,
    ["-X", "-q", "-v", "ON_ERROR_STOP=1", "-h", socket, "-p", port, "-U", "postgres", "-d", "postgres", "-t", "-A"],
    {
      input: sql,
      encoding: "utf8",
      env: {
        PATH: process.env.PATH,
        HOME: process.env.HOME,
        LANG: "C",
        PGPASSFILE: process.env.PGPASSFILE,
        PGSOCKET: socket,
        PGPORT: port,
      },
    },
  );
  if (result.status !== 0) {
    const line = (result.stderr || "").split("\n").find((item) => item.startsWith("ERROR:")) || "psql failed";
    fail(line.slice(0, 180));
  }
  return result.stdout.split("\n").map((item) => item.trim()).filter((item) => item.includes("|"));
}

function rows(sql) {
  const out = psql(sql);
  const found = new Map();
  for (const line of out) {
    const cut = line.indexOf("|");
    found.set(line.slice(0, cut), line.slice(cut + 1));
  }
  return found;
}

function must(found, key, expected) {
  if (found.get(key) !== expected) fail(`${key} was ${found.get(key) ?? "missing"}`);
}

const plaintext = {
  token: TOKEN,
  fleet: [{ host: HOST, ip: ADDRESS, port: 8898, token: TOKEN }],
};

const anchor = generateDeviceKeyPair();
const mintedB = buildDeviceSyncBodies({
  label: "Wrist",
  platform: "watchos",
  recipientPublicKey: anchor.publicKey,
  plaintext,
});
const recipientB = crypto.createPublicKey({
  key: { kty: "OKP", crv: "X25519", x: mintedB.privateKey.export({ format: "jwk" }).x },
  format: "jwk",
});
const mintedA = buildDeviceSyncBodies({
  label: "Kitchen Mac",
  platform: "macos",
  recipientPublicKey: recipientB,
  plaintext,
});

const registrationA = JSON.parse(mintedA.registration);
const registrationB = JSON.parse(mintedB.registration);
const mailbox = JSON.parse(mintedA.mailbox);
if (Object.keys(registrationA).join(",") !== "label,platform,public_key") {
  fail("registration keys are not label, platform, and public_key");
}
if (Object.keys(registrationB).join(",") !== "label,platform,public_key") {
  fail("the second registration keys are not label, platform, and public_key");
}
if (Object.keys(mailbox).join(",") !== "ciphertext") fail("mailbox key is not ciphertext");
if (registrationA.label !== "Kitchen Mac" || registrationA.platform !== "macos") {
  fail("device A registration did not keep the label and platform");
}
if (registrationB.label !== "Wrist" || registrationB.platform !== "watchos") {
  fail("device B registration did not keep the label and platform");
}
if (registrationA.public_key === registrationB.public_key) fail("the two devices share a public key");
if (typeof mailbox.ciphertext !== "string" || mailbox.ciphertext.length < 1) fail("ciphertext is empty");

const deviceColumns = "(user_id, label, platform, public_key)";
const mailboxColumns = "(user_id, recipient_device_id, sender_device_id, ciphertext, expires_at)";

const userA = crypto.randomUUID();
const userB = crypto.randomUUID();
const publicA = lit(registrationA.public_key, "public key");
const publicB = lit(registrationB.public_key, "public key");
const cipher = lit(mailbox.ciphertext, "ciphertext");

function insertAs(userId, username) {
  return `
BEGIN;
DO $$ BEGIN PERFORM set_config('request.jwt.claim.sub', '${userId}', true); END $$;
SET LOCAL ROLE authenticated;
INSERT INTO public.profiles (id, username) VALUES (auth.uid(), '${username}');
INSERT INTO public.devices ${deviceColumns} VALUES
  (auth.uid(), 'Kitchen Mac', 'macos', ${publicA}),
  (auth.uid(), 'Wrist', 'watchos', ${publicB});
INSERT INTO public.mailbox ${mailboxColumns}
SELECT auth.uid(),
  (SELECT id FROM public.devices WHERE user_id = auth.uid() AND public_key = ${publicB}),
  (SELECT id FROM public.devices WHERE user_id = auth.uid() AND public_key = ${publicA}),
  ${cipher},
  now() + interval '1 day';
COMMIT;
`;
}

psql(`INSERT INTO auth.users (id) VALUES ('${userA}'::uuid), ('${userB}'::uuid);`);
psql(insertAs(userA, "user_a"));
psql(insertAs(userB, "user_b"));

function seeAs(userId, otherId, prefix) {
  return rows(`
BEGIN;
DO $$ BEGIN PERFORM set_config('request.jwt.claim.sub', '${userId}', true); END $$;
SET LOCAL ROLE authenticated;
SELECT '${prefix}_other_profile|' || count(*) FROM public.profiles WHERE id = '${otherId}'::uuid;
SELECT '${prefix}_own_profile|' || count(*) FROM public.profiles WHERE id = auth.uid();
SELECT '${prefix}_other_devices|' || count(*) FROM public.devices WHERE user_id = '${otherId}'::uuid;
SELECT '${prefix}_own_devices|' || count(*) FROM public.devices WHERE user_id = auth.uid();
SELECT '${prefix}_other_mailbox|' || count(*) FROM public.mailbox WHERE user_id = '${otherId}'::uuid;
SELECT '${prefix}_own_mailbox|' || count(*) FROM public.mailbox WHERE user_id = auth.uid();
SELECT '${prefix}_profile_ids|' || coalesce(string_agg(id::text, ',' ORDER BY id::text), '') FROM public.profiles;
SELECT '${prefix}_device_users|' || coalesce(string_agg(DISTINCT user_id::text, ',' ORDER BY user_id::text), '') FROM public.devices;
SELECT '${prefix}_mailbox_users|' || coalesce(string_agg(DISTINCT user_id::text, ',' ORDER BY user_id::text), '') FROM public.mailbox;
ROLLBACK;
`);
}

const asB = seeAs(userB, userA, "b");
must(asB, "b_other_profile", "0");
must(asB, "b_own_profile", "1");
must(asB, "b_other_devices", "0");
must(asB, "b_own_devices", "2");
must(asB, "b_other_mailbox", "0");
must(asB, "b_own_mailbox", "1");
must(asB, "b_profile_ids", userB);
must(asB, "b_device_users", userB);
must(asB, "b_mailbox_users", userB);

const asA = seeAs(userA, userB, "a");
must(asA, "a_other_profile", "0");
must(asA, "a_own_profile", "1");
must(asA, "a_other_devices", "0");
must(asA, "a_own_devices", "2");
must(asA, "a_other_mailbox", "0");
must(asA, "a_own_mailbox", "1");

const owned = psql(`
SELECT 'device|' || id::text || '|' || public_key
FROM public.devices
WHERE user_id = '${userA}'::uuid
ORDER BY public_key;
`);
if (owned.length !== 2) fail("user A does not own two devices");
const sender = owned.find((line) => line.endsWith("|" + registrationA.public_key));
const recipient = owned.find((line) => line.endsWith("|" + registrationB.public_key));
if (!sender || !recipient) fail("stored devices are not the minted public keys");
const senderId = sender.split("|")[1];
const recipientId = recipient.split("|")[1];

psql(`
BEGIN;
DO $$ BEGIN PERFORM set_config('request.jwt.claim.sub', '${userB}', true); END $$;
SET LOCAL ROLE authenticated;
DO $cross$
BEGIN
  INSERT INTO public.mailbox ${mailboxColumns}
  VALUES (
    auth.uid(),
    '${recipientId}'::uuid,
    '${senderId}'::uuid,
    ${cipher},
    now() + interval '1 day'
  );
  RAISE EXCEPTION 'mailbox insert using another user device ids was allowed';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM NOT LIKE '%row-level security%' THEN
      RAISE;
    END IF;
END
$cross$;
ROLLBACK;
SELECT 'cross|refused';
`);

const totals = rows(`
SELECT 'device_rows|' || count(*) FROM public.devices;
SELECT 'profile_rows|' || count(*) FROM public.profiles;
SELECT 'mailbox_rows|' || count(*) FROM public.mailbox;
SELECT 'cipher_match|' || count(*) FROM public.mailbox WHERE ciphertext = ${cipher};
`);
must(totals, "device_rows", "4");
must(totals, "profile_rows", "2");
must(totals, "mailbox_rows", "2");
must(totals, "cipher_match", "2");

const storedDevices = psql(`
SELECT 'stored|' || label || '|' || platform || '|' || public_key
FROM public.devices
ORDER BY user_id::text, public_key;
`);
const expectedStored = [
  `stored|Kitchen Mac|macos|${registrationA.public_key}`,
  `stored|Wrist|watchos|${registrationB.public_key}`,
].sort();
const gotStored = storedDevices.filter((line) => line.startsWith("stored|")).sort();
if (gotStored.length !== 4) fail("stored device rows were not the two registrations for each user");
for (const line of gotStored) {
  const body = line.split("|").slice(1).join("|");
  const bare = `stored|${body}`;
  if (!expectedStored.includes(bare)) fail("a stored device row was not label, platform, and public_key");
}

const columns = psql(`
SELECT 'col|' || table_name || '|' || column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('devices', 'mailbox')
ORDER BY table_name, ordinal_position;
`);
const byTable = new Map();
for (const line of columns) {
  const [, table, column] = line.split("|");
  if (!byTable.has(table)) byTable.set(table, []);
  byTable.get(table).push(column);
}
const expectColumns = {
  devices: ["id", "user_id", "label", "platform", "public_key", "created_at", "last_seen_at"],
  mailbox: ["id", "user_id", "recipient_device_id", "sender_device_id", "ciphertext", "created_at", "expires_at"],
};
for (const [table, names] of Object.entries(expectColumns)) {
  const actual = byTable.get(table) || [];
  if (actual.join(",") !== names.join(",")) fail(`${table} columns are ${actual.join(",")}`);
}
const passwordShaped = /password|passwd|passphrase|(^|_)pwd($|_)|secret/i;
for (const names of byTable.values()) {
  for (const name of names) {
    if (passwordShaped.test(name)) fail("password-shaped column is present");
  }
}

const rls = rows(`
SELECT 'rls_' || c.relname || '|' || c.relrowsecurity::text
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('profiles', 'devices', 'mailbox')
ORDER BY c.relname;
`);
must(rls, "rls_devices", "true");
must(rls, "rls_mailbox", "true");
must(rls, "rls_profiles", "true");

const roles = rows(`
SELECT 'role_' || rolname || '|' || rolbypassrls::text
FROM pg_roles
WHERE rolname IN ('anon', 'authenticated')
ORDER BY rolname;
`);
must(roles, "role_anon", "false");
must(roles, "role_authenticated", "false");

const ciphers = psql(`SELECT 'cipher|' || ciphertext FROM public.mailbox;`);
if (ciphers.length !== 2) fail("expected two stored ciphertexts");
const encodings = [anchor.privateKey, mintedA.privateKey, mintedB.privateKey].map(scalarEncodings);
const machine = os.hostname();
for (const line of ciphers) {
  const text = line.slice("cipher|".length);
  if (text !== mailbox.ciphertext) fail("stored ciphertext is not the sealed mailbox");
  let raw;
  try {
    raw = Buffer.from(text, "base64url");
  } catch {
    fail("stored ciphertext is not base64url");
  }
  if (text.includes(TOKEN) || raw.includes(Buffer.from(TOKEN))) fail("stored ciphertext contains the fixture token");
  if (text.includes(ADDRESS) || raw.includes(Buffer.from(ADDRESS))) fail("stored ciphertext contains the IP");
  if (text.includes(HOST) || raw.includes(Buffer.from(HOST))) fail("stored ciphertext contains the hostname");
  if (machine.length >= 4 && (text.includes(machine) || raw.includes(Buffer.from(machine)))) {
    fail("stored ciphertext contains the machine hostname");
  }
  for (const encoding of encodings) {
    for (const secret of encoding.texts) {
      if (secret.length > 0 && text.includes(secret)) fail("stored ciphertext contains the private key");
    }
    if (raw.includes(encoding.raw)) fail("stored ciphertext contains the raw private key");
  }
}

if (fs.existsSync(path.join(process.env.HOME, ".mesh"))) fail("a mesh directory was created");
console.log("users: 2");
console.log("devices: 2");
console.log("registration_keys: label,platform,public_key");
console.log("mailbox_keys: ciphertext");
console.log("b_sees_a_profile: 0");
console.log("b_sees_a_devices: 0");
console.log("b_sees_a_mailbox: 0");
console.log("b_insert_a_devices: refused");
console.log("ciphertext_has_token: false");
console.log("ciphertext_has_ip: false");
console.log("ciphertext_has_hostname: false");
console.log("ciphertext_has_private_key: false");
console.log("password_columns: none");
console.log("check-sync-rls: node OK");
END_NODE

echo "check-sync-rls: OK"
