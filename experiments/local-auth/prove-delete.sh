#!/bin/sh
# Prove web/api/delete-account.js against a Supabase stack that is already
# running on this machine. The handler is loaded unchanged. SUPABASE_URL,
# SUPABASE_ANON_KEY, and SUPABASE_SERVICE_ROLE_KEY are copied from
# `supabase status` into that process and are never written into the repo.
# This is not a scripts/check-*.sh file: check-all.sh runs every check, and
# those CI machines do not have this stack.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SQL="$ROOT/supabase/account/001_identity.sql"
JS="$ROOT/web/api/delete-account.js"
EXPECTED_SQL_SHA256="cd47695328f67abb077b62e48b670ed7cf78d6f4a916348958229d1862445253"

[ -f "$SQL" ] || { echo "FAIL: missing $SQL"; exit 1; }
[ -f "$JS" ] || { echo "FAIL: missing $JS"; exit 1; }
command -v supabase >/dev/null || { echo "FAIL: supabase CLI is not installed"; exit 1; }
command -v psql >/dev/null || { echo "FAIL: psql is not installed"; exit 1; }
command -v node >/dev/null || { echo "FAIL: node is not installed"; exit 1; }

STATUS="$(mktemp)"
trap 'rm -f "$STATUS"' EXIT INT TERM
if ! supabase status -o env >"$STATUS" 2>/dev/null; then
  echo "FAIL: local supabase is not running. Start it on this machine; do not use a hosted project."
  exit 1
fi

node - "$STATUS" "$SQL" "$JS" "$EXPECTED_SQL_SHA256" << 'NODE'
"use strict";

var fs = require("fs");
var nodeCrypto = require("crypto");
var child = require("child_process");
var os = require("os");
var path = require("path");

var statusPath = process.argv[2];
var sqlPath = process.argv[3];
var jsPath = process.argv[4];
var expectedSqlHash = process.argv[5];
var env = {};
var statusText = fs.readFileSync(statusPath, "utf8");
fs.unlinkSync(statusPath);
statusText.split(/\n/).forEach(function (line) {
  line = line.trim();
  if (!/^[A-Z0-9_]+=/.test(line)) return;
  var key = line.split("=", 1)[0];
  var value = line.slice(key.length + 1);
  if (value.length >= 2 && value.charAt(0) === '"' && value.charAt(value.length - 1) === '"') {
    value = value.slice(1, -1);
  }
  env[key] = value;
});

var secrets = [];

function remember(value) {
  if (typeof value === "string" && value.length >= 8) secrets.push(value);
}

function redact(text) {
  var out = String(text || "");
  secrets.forEach(function (secret) {
    out = out.split(secret).join("REDACTED");
  });
  return out
    .replace(/postgres(?:ql)?:\/\/\S+/gi, "postgresql://REDACTED")
    .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, "REDACTED_JWT")
    .replace(/(apikey|authorization|access_token|refresh_token|bearer)\s*[:=]\s*\S+/gi, "$1=REDACTED");
}

function fail(message) {
  console.log("FAIL: " + redact(message));
  process.exit(1);
}

var api = String(env.API_URL || "").replace(/\/+$/, "");
var anon = String(env.ANON_KEY || "");
var serviceKey = String(env.SERVICE_ROLE_KEY || "");
var db = String(env.DB_URL || "");
remember(anon);
remember(serviceKey);
remember(db);
remember(String(env.JWT_SECRET || ""));
remember(String(env.SECRET_KEY || ""));
remember(String(env.PUBLISHABLE_KEY || ""));
remember(String(env.S3_PROTOCOL_ACCESS_KEY_ID || ""));
remember(String(env.S3_PROTOCOL_ACCESS_KEY_SECRET || ""));

if (!api || !anon || !serviceKey || !db) {
  fail("local status did not include API_URL, ANON_KEY, SERVICE_ROLE_KEY, and DB_URL");
}
var blob = [api, db, env.MAILPIT_URL || "", env.STUDIO_URL || ""].join(" ");
if (blob.indexOf("supabase.co") !== -1 || blob.indexOf("zmisjteztezaqfflwbgf") !== -1) {
  fail("refusing a non-local stack");
}
if (!/^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(api)) fail("API_URL is not a local loopback address");
var dbHost = "";
try { dbHost = new URL(db).hostname; } catch (err) { dbHost = ""; }
if (dbHost !== "127.0.0.1" && dbHost !== "localhost") fail("DB_URL is not a local loopback address");

function jwtRole(token) {
  var parts = String(token || "").split(".");
  if (parts.length !== 3) return "";
  try {
    return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8")).role || "";
  } catch (err) {
    return "";
  }
}

if (jwtRole(anon) !== "anon") fail("local API key is not the anon role");
if (jwtRole(serviceKey) !== "service_role") fail("local service key is not the service role");

var sqlBytes = fs.readFileSync(sqlPath);
var sqlHash = nodeCrypto.createHash("sha256").update(sqlBytes).digest("hex");
if (sqlHash !== expectedSqlHash) fail("identity SQL sha256 changed");
console.log("identity_sql_sha256: " + sqlHash);

function psql(sql, file) {
  var args = [db, "-v", "ON_ERROR_STOP=1", "-At"];
  if (file) args.push("-f", file);
  else args.push("-c", sql);
  var result = child.spawnSync("psql", args, { encoding: "utf8" });
  if (result.status !== 0) {
    fail("database command failed: " + redact((result.stderr || result.stdout || "").trim()));
  }
  return result.stdout || "";
}

if (psql("select to_regclass('public.profiles') is not null").trim() !== "t") {
  process.stdout.write(psql("", sqlPath));
} else {
  console.log("identity SQL already applied");
}
psql("notify pgrst, 'reload schema'");

process.env.SUPABASE_URL = api;
process.env.SUPABASE_ANON_KEY = anon;
process.env.SUPABASE_SERVICE_ROLE_KEY = serviceKey;

var handler = require(jsPath);
var realFetch = global.fetch;
if (typeof realFetch !== "function") fail("node has no fetch");

var machineToken = "mesh-token-sentinel-" + nodeCrypto.randomBytes(8).toString("hex");
var machineTokenBefore = machineToken;
var tokenFile = path.join(os.tmpdir(), "account-delete-sentinel-" + nodeCrypto.randomBytes(6).toString("hex"));
fs.writeFileSync(tokenFile, machineToken, { mode: 0o600 });
remember(machineToken);

var allCalls = [];
var handlerCalls = null;

global.fetch = function (url, init) {
  var options = init || {};
  var call = {
    url: String(url),
    method: String(options.method || "GET").toUpperCase(),
    headers: options.headers || {},
    body: Object.prototype.hasOwnProperty.call(options, "body") ? options.body : undefined
  };
  allCalls.push(call);
  if (handlerCalls) handlerCalls.push(call);
  return realFetch(url, init);
};

function header(headers, name) {
  if (!headers) return "";
  var keys = Object.keys(headers);
  for (var i = 0; i < keys.length; i++) {
    if (keys[i].toLowerCase() === name.toLowerCase()) return String(headers[keys[i]]);
  }
  return "";
}

function callFlat(call) {
  return call.url + "\n" + JSON.stringify(call.headers || {}) + "\n" + (call.body == null ? "" : String(call.body));
}

function assertNoMachine(call, label) {
  var url;
  try { url = new URL(call.url); } catch (err) { fail(label + " request URL was not absolute"); }
  if (url.port === "8899" || call.url.indexOf(":8899") !== -1) fail(label + " called port 8899");
  if (url.hostname !== "127.0.0.1" && url.hostname !== "localhost") fail(label + " left loopback");
  var flat = callFlat(call);
  if (flat.indexOf(machineToken) !== -1 || flat.indexOf("mesh-token") !== -1) {
    fail(label + " carries a mesh token");
  }
  if (/\/(pair|rotate|token-rotate|machine-token)(\/|$|\?)/i.test(url.pathname)) {
    fail(label + " rotates a machine token");
  }
}

function assertClean(text, label) {
  var value = String(text || "");
  if (serviceKey && value.indexOf(serviceKey) !== -1) fail(label + " contains the service role");
  if (value.indexOf(machineToken) !== -1 || value.indexOf("mesh-token") !== -1) {
    fail(label + " contains a mesh token");
  }
}

async function invoke(headers) {
  var captured = [];
  var methods = ["log", "info", "warn", "error", "debug"];
  var originals = {};
  methods.forEach(function (name) {
    originals[name] = console[name];
    console[name] = function () {
      var parts = [];
      for (var i = 0; i < arguments.length; i++) {
        var item = arguments[i];
        parts.push(typeof item === "string" ? item : JSON.stringify(item));
      }
      captured.push(parts.join(" "));
    };
  });
  var stdout = process.stdout.write;
  var stderr = process.stderr.write;
  function trap(chunk, enc, cb) {
    captured.push(Buffer.isBuffer(chunk) ? chunk.toString("utf8") : String(chunk));
    if (typeof enc === "function") enc();
    else if (typeof cb === "function") cb();
    return true;
  }
  process.stdout.write = trap;
  process.stderr.write = trap;
  handlerCalls = [];
  var settled = false;
  try {
    return await new Promise(function (resolve, reject) {
      var timer = setTimeout(function () {
        if (!settled) reject(new Error("delete handler timed out"));
      }, 20000);
      var res = {
        statusCode: 0,
        headersOut: {},
        setHeader: function (key, value) { this.headersOut[key] = value; },
        end: function (body) {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          resolve({
            status: this.statusCode,
            body: body == null ? "" : String(body),
            headersOut: this.headersOut,
            logs: captured.slice(),
            calls: handlerCalls.slice()
          });
        }
      };
      Promise.resolve(handler({ method: "POST", headers: headers || {} }, res)).then(function () {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          reject(new Error("delete handler returned without a response"));
        }
      }, function (err) {
        if (!settled) {
          settled = true;
          clearTimeout(timer);
          reject(err);
        }
      });
    });
  } finally {
    handlerCalls = null;
    methods.forEach(function (name) { console[name] = originals[name]; });
    process.stdout.write = stdout;
    process.stderr.write = stderr;
  }
}

async function request(method, url, body, token, prefer) {
  var headers = {
    apikey: anon,
    Authorization: "Bearer " + (token || anon),
    Accept: "application/json"
  };
  if (body != null) headers["Content-Type"] = "application/json";
  if (prefer) headers.Prefer = prefer;
  var response = await global.fetch(url, {
    method: method,
    headers: headers,
    body: body == null ? undefined : JSON.stringify(body)
  });
  var text = await response.text();
  var data = null;
  if (text) {
    try { data = JSON.parse(text); } catch (err) { data = null; }
  }
  return { status: response.status, data: data, text: text };
}

function errorText(data) {
  if (!data || typeof data !== "object") return "";
  var keys = ["error_description", "msg", "message", "error", "code"];
  for (var i = 0; i < keys.length; i++) {
    var value = data[keys[i]];
    if (typeof value === "string" && value) return redact(value);
  }
  return "";
}

function sessionOf(data) {
  if (!data || typeof data.access_token !== "string" || !data.user || typeof data.user.id !== "string") return null;
  return { token: data.access_token, id: data.user.id };
}

async function signUp(email, password, username) {
  var result = await request("POST", api + "/auth/v1/signup", {
    email: email,
    password: password,
    data: { username: username }
  });
  if (result.status < 200 || result.status >= 300) fail("sign-up refused: " + result.status + " " + errorText(result.data));
  return sessionOf(result.data);
}

async function signIn(email, password) {
  var result = await request("POST", api + "/auth/v1/token?grant_type=password", {
    email: email,
    password: password
  });
  var session = sessionOf(result.data);
  return { status: result.status, session: session, detail: errorText(result.data) };
}

function assertUuid(id) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) {
    fail("user id was not a uuid");
  }
}

function countWhere(table, column, id) {
  assertUuid(id);
  return psql("select count(*) from " + table + " where " + column + " = '" + id + "'").trim();
}

function countsFor(id) {
  return {
    profile: countWhere("public.profiles", "id", id),
    devices: countWhere("public.devices", "user_id", id),
    mailbox: countWhere("public.mailbox", "user_id", id),
    auth: countWhere("auth.users", "id", id)
  };
}

async function insertOwnedRows(session, username) {
  var profile = await request(
    "POST",
    api + "/rest/v1/profiles?on_conflict=id",
    { id: session.id, username: username },
    session.token,
    "resolution=merge-duplicates,return=minimal"
  );
  if (profile.status < 200 || profile.status >= 300) fail("profile insert failed: " + profile.status + " " + errorText(profile.data));
  var device = await request(
    "POST",
    api + "/rest/v1/devices",
    {
      user_id: session.id,
      label: "wrist",
      platform: "web",
      public_key: "pub-" + username
    },
    session.token,
    "return=representation"
  );
  if (device.status !== 200 && device.status !== 201) fail("device insert failed: " + device.status + " " + errorText(device.data));
  if (!Array.isArray(device.data) || device.data.length !== 1 || !device.data[0].id) fail("device insert did not return a row");
  var deviceId = device.data[0].id;
  var box = await request(
    "POST",
    api + "/rest/v1/mailbox",
    {
      user_id: session.id,
      recipient_device_id: deviceId,
      sender_device_id: deviceId,
      ciphertext: "sealed-" + nodeCrypto.randomBytes(16).toString("hex"),
      expires_at: "2030-01-01T00:00:00Z"
    },
    session.token,
    "return=representation"
  );
  if (box.status !== 200 && box.status !== 201) fail("mailbox insert failed: " + box.status + " " + errorText(box.data));
}

function assertServiceRoleOnlyOnAdminDelete(calls, adminUrl) {
  var admin = calls.filter(function (call) {
    return call.method === "DELETE" && call.url === adminUrl;
  });
  if (admin.length !== 1) fail("admin delete was not sent once");
  calls.forEach(function (call) {
    if (call.url.indexOf(serviceKey) !== -1) fail("service role appeared in a URL");
    if (call.body != null && String(call.body).indexOf(serviceKey) !== -1) {
      fail("service role appeared in a request body");
    }
    var headerFlat = JSON.stringify(call.headers || {});
    var headerHas = headerFlat.indexOf(serviceKey) !== -1;
    var isAdmin = call === admin[0];
    if (headerHas && !isAdmin) fail("service role was sent outside the admin delete");
    if (!isAdmin && header(call.headers, "apikey") === serviceKey) fail("service role was sent outside the admin delete");
  });
  if (header(admin[0].headers, "apikey") !== serviceKey) fail("admin delete did not send the service role as apikey");
  if (header(admin[0].headers, "Authorization") !== "Bearer " + serviceKey) {
    fail("admin delete did not send the service role bearer");
  }
}

function usernameOf(prefix) {
  var name = prefix + nodeCrypto.randomBytes(4).toString("hex");
  if (!/^[a-z0-9_]{3,32}$/.test(name)) fail("generated username does not match the profile pattern");
  return name;
}

async function main() {
  var userA = usernameOf("a");
  var userB = usernameOf("b");
  var emailA = userA + "@example.com";
  var emailB = userB + "@example.com";
  var passwordA = nodeCrypto.randomBytes(16).toString("hex");
  var passwordB = nodeCrypto.randomBytes(16).toString("hex");
  remember(emailA);
  remember(emailB);
  remember(passwordA);
  remember(passwordB);

  await signUp(emailA, passwordA, userA);
  await signUp(emailB, passwordB, userB);
  var signedA = await signIn(emailA, passwordA);
  var signedB = await signIn(emailB, passwordB);
  if (!signedA.session || signedA.status < 200 || signedA.status >= 300) fail("first sign-in did not return a session");
  if (!signedB.session || signedB.status < 200 || signedB.status >= 300) fail("second sign-in did not return a session");
  if (signedA.session.id === signedB.session.id) fail("both users resolved to one id");
  remember(signedA.session.token);
  remember(signedB.session.token);
  await insertOwnedRows(signedA.session, userA);
  await insertOwnedRows(signedB.session, userB);

  var beforeA = countsFor(signedA.session.id);
  var beforeB = countsFor(signedB.session.id);
  if (beforeA.profile !== "1" || beforeA.devices !== "1" || beforeA.mailbox !== "1" || beforeA.auth !== "1") {
    fail("first user rows were not present before delete");
  }
  if (beforeB.profile !== "1" || beforeB.devices !== "1" || beforeB.mailbox !== "1" || beforeB.auth !== "1") {
    fail("second user rows were not present before delete");
  }

  var denied = await invoke({});
  if (denied.status !== 401) fail("missing bearer returned " + denied.status);
  var deniedBody = JSON.parse(denied.body);
  if (!deniedBody || deniedBody.ok === true || deniedBody.error !== "Sign in required.") {
    fail("missing bearer body was not the sign-in refusal");
  }
  if (denied.calls.length !== 0) fail("missing bearer contacted auth");
  assertClean(denied.body, "missing-bearer response");
  assertClean(JSON.stringify(denied.headersOut || {}), "missing-bearer response");
  assertClean(denied.logs.join("\n"), "missing-bearer logs");
  [emailA, emailB, signedA.session.token].forEach(function (secret) {
    if (denied.body.indexOf(secret) !== -1) fail("missing-bearer response contains the email or the user jwt");
    if (denied.logs.join("\n").indexOf(secret) !== -1) fail("missing-bearer logs contain the email or the user jwt");
  });
  var afterDeniedA = countsFor(signedA.session.id);
  var afterDeniedB = countsFor(signedB.session.id);
  if (JSON.stringify(afterDeniedA) !== JSON.stringify(beforeA) || JSON.stringify(afterDeniedB) !== JSON.stringify(beforeB)) {
    fail("missing bearer deleted a row");
  }
  var stillA = await signIn(emailA, passwordA);
  if (!stillA.session || stillA.status < 200 || stillA.status >= 300) fail("missing bearer broke sign-in");
  remember(stillA.session.token);
  console.log("missing bearer: 401");
  console.log("missing bearer did not delete");

  var deleted = await invoke({ Authorization: "Bearer " + signedA.session.token });
  if (deleted.status !== 200) fail("delete returned " + deleted.status);
  var deletedBody = JSON.parse(deleted.body);
  if (!deletedBody || deletedBody.ok !== true || Object.keys(deletedBody).join(",") !== "ok") {
    fail("delete body was not {ok:true}");
  }
  if (deleted.calls.length !== 2) fail("delete made " + deleted.calls.length + " auth requests");
  var userCall = deleted.calls[0];
  var adminUrl = api + "/auth/v1/admin/users/" + signedA.session.id;
  if (userCall.method !== "GET" || userCall.url !== api + "/auth/v1/user") fail("delete did not verify the signed-in user");
  if (header(userCall.headers, "apikey") !== anon) fail("user lookup did not use the anon key");
  if (header(userCall.headers, "Authorization") !== "Bearer " + signedA.session.token) {
    fail("user lookup did not use the user bearer");
  }
  if (header(userCall.headers, "apikey") === serviceKey || header(userCall.headers, "Authorization").indexOf(serviceKey) !== -1) {
    fail("user lookup sent the service role");
  }
  assertServiceRoleOnlyOnAdminDelete(deleted.calls, adminUrl);
  if (deleted.calls[1].url.indexOf(signedB.session.id) !== -1) fail("delete targeted the other user");
  deleted.calls.forEach(function (call) { assertNoMachine(call, "delete"); });
  assertClean(deleted.body, "delete response");
  assertClean(JSON.stringify(deleted.headersOut || {}), "delete response");
  var logText = deleted.logs.join("\n");
  assertClean(logText, "delete logs");
  [emailA, emailB, signedA.session.token, stillA.session.token].forEach(function (secret) {
    if (deleted.body.indexOf(secret) !== -1) fail("delete response contains the email or the user jwt");
    if (logText.indexOf(secret) !== -1) fail("delete logs contain the email or the user jwt");
    deleted.calls.forEach(function (call) {
      if (call.url.indexOf(secret) !== -1) fail("delete URL contains the email or the user jwt");
    });
  });
  console.log("delete: 200 {ok:true}");
  console.log("service role: admin delete only");
  console.log("service role absent from response, url, and logs");
  console.log("response and logs omit email and user jwt");

  var again = await signIn(emailA, passwordA);
  if (again.session || (again.status >= 200 && again.status < 300)) fail("deleted user signed in");
  console.log("sign-in after delete: failed");

  var afterA = countsFor(signedA.session.id);
  var afterB = countsFor(signedB.session.id);
  if (afterA.profile !== "0" || afterA.devices !== "0" || afterA.mailbox !== "0" || afterA.auth !== "0") {
    fail("deleted user profile, devices, or mailbox remain");
  }
  if (afterB.profile !== "1" || afterB.devices !== "1" || afterB.mailbox !== "1" || afterB.auth !== "1") {
    fail("second user did not stay");
  }
  var stillB = await signIn(emailB, passwordB);
  if (!stillB.session || stillB.session.id !== signedB.session.id) fail("second user could not sign in");
  console.log("a_profile_after_delete: 0");
  console.log("a_devices_after_delete: 0");
  console.log("a_mailbox_after_delete: 0");
  console.log("b_profile_after_delete: 1");
  console.log("second user profile: remains");

  var held = fs.readFileSync(tokenFile, "utf8");
  if (held !== machineTokenBefore || machineToken !== machineTokenBefore) fail("machine token was rotated");
  fs.unlinkSync(tokenFile);
  allCalls.forEach(function (call) { assertNoMachine(call, "proof"); });
  console.log("requests to port 8899: none");
  console.log("requests carrying a mesh token: none");
  console.log("machine token: not rotated");
  console.log("local-account-delete: OK");
}

main().catch(function (err) {
  try { fs.unlinkSync(tokenFile); } catch (ignore) {}
  fail(err && err.stack ? err.stack : err);
});
NODE
