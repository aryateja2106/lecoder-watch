#!/bin/sh
# Drive web/account/account.js readDeviceLabels against a Supabase stack
# that is already running on this machine. The page script keeps its own
# fetch; this file only supplies a fake document and points window.MESH_ACCOUNT
# at the local API URL and anon key from `supabase status`. Those values are
# never written into the repo. This is not a scripts/check-*.sh file:
# check-all.sh runs every check, and those CI machines do not have this stack.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SQL="$ROOT/supabase/account/001_identity.sql"
JS="$ROOT/web/account/account.js"
PAGE="$ROOT/web/account/home.html"
EXPECTED_SQL_SHA="cd47695328f67abb077b62e48b670ed7cf78d6f4a916348958229d1862445253"

[ -f "$SQL" ] || { echo "FAIL: missing $SQL"; exit 1; }
[ -f "$JS" ] || { echo "FAIL: missing $JS"; exit 1; }
[ -f "$PAGE" ] || { echo "FAIL: missing $PAGE"; exit 1; }
command -v supabase >/dev/null || { echo "FAIL: supabase CLI is not installed"; exit 1; }
command -v psql >/dev/null || { echo "FAIL: psql is not installed"; exit 1; }
command -v node >/dev/null || { echo "FAIL: node is not installed"; exit 1; }

ACTUAL_SQL_SHA="$(node -e 'const fs=require("fs");const crypto=require("crypto");process.stdout.write(crypto.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"))' "$SQL")"
if [ "$ACTUAL_SQL_SHA" != "$EXPECTED_SQL_SHA" ]; then
  echo "FAIL: identity SQL hash changed"
  exit 1
fi

STATUS="$(mktemp)"
RUNNER="$(mktemp)"
trap 'rm -f "$STATUS" "$RUNNER"' EXIT INT TERM
if ! supabase status -o env >"$STATUS" 2>/dev/null; then
  echo "FAIL: local supabase is not running. Start it on this machine; do not use a hosted project."
  exit 1
fi

cat >"$RUNNER" << 'NODE'
"use strict";

var fs = require("fs");
var vm = require("vm");
var nodeCrypto = require("crypto");
var child = require("child_process");

var statusPath = process.argv[2];
var sqlPath = process.argv[3];
var jsPath = process.argv[4];
var homePath = process.argv[5];
var expectedSha = process.argv[6];
var source = fs.readFileSync(jsPath, "utf8");
var homeHtml = fs.readFileSync(homePath, "utf8");
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

function fail(message) {
  console.log("FAIL: " + redact(message));
  process.exit(1);
}

function redact(text) {
  return String(text || "")
    .replace(/postgres(?:ql)?:\/\/\S+/gi, "postgresql://REDACTED")
    .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, "REDACTED_JWT")
    .replace(/sb_secret_[A-Za-z0-9_-]+/g, "REDACTED_SECRET")
    .replace(/(apikey|authorization|access_token|refresh_token|bearer)\s*[:=]\s*\S+/gi, "$1=REDACTED");
}

var EMPTY = "Pairing still happens on the machine. This page lists labels only.";
var emptyAt = homeHtml.indexOf('id="devices-empty"');
if (emptyAt < 0) fail("home page has no devices-empty element");
var emptySlice = homeHtml.slice(emptyAt, emptyAt + 500);
var emptyMatch = emptySlice.match(/>([^<]+)</);
if (!emptyMatch || emptyMatch[1] !== EMPTY) fail("home page empty state is not the pairing line");
if (/id="devices-empty"[^>]*\shidden[\s>]/.test(emptySlice)) {
  fail("home page hides the empty state before any device");
}
var listAt = homeHtml.indexOf('id="device-labels"');
if (listAt < 0) fail("home page has no device-labels element");
var listTag = homeHtml.slice(listAt, listAt + 180);
if (!/\shidden[\s>]/.test(listTag)) fail("home page shows the device list before any device");

var api = String(env.API_URL || "").replace(/\/+$/, "");
var anon = String(env.ANON_KEY || "");
var db = String(env.DB_URL || "");
if (!api || !anon || !db) fail("local status did not include API_URL, ANON_KEY, and DB_URL");
var blob = api + " " + db;
if (blob.indexOf("supabase.co") !== -1 || blob.indexOf("zmisjteztezaqfflwbgf") !== -1) {
  fail("refusing a non-local stack");
}
if (!/^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(api)) fail("API_URL is not a local loopback address");
var apiPort = "";
try { apiPort = String(new URL(api).port || ""); } catch (err) { apiPort = ""; }
if (apiPort === "8899") fail("API_URL uses port 8899");

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

var homeDir = require("os").homedir();
var meshDir = homeDir + "/.mesh";
var homeBefore = fs.readdirSync(homeDir).slice().sort();
if (fs.existsSync(meshDir)) fail("refusing to run while ~/.mesh already exists");

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

var sqlSha = nodeCrypto.createHash("sha256").update(fs.readFileSync(sqlPath)).digest("hex");
if (sqlSha !== expectedSha) fail("identity SQL hash changed");
console.log("identity_sql_sha256: " + sqlSha);
if (psql("select to_regclass('public.profiles') is not null").trim() !== "t") {
  process.stdout.write(psql("", sqlPath));
} else {
  console.log("identity SQL already applied");
}
psql("notify pgrst, 'reload schema'");
if (nodeCrypto.createHash("sha256").update(fs.readFileSync(sqlPath)).digest("hex") !== expectedSha) {
  fail("identity SQL hash changed after apply");
}

var ORIGIN = "http://127.0.0.1:3000";
var SENTINEL_TOKEN = "mesh-token-sentinel";
var SENTINEL_IP = "203.0.113.10";
var SENTINEL_HOST = "fixture-mac";
var PLATFORMS = ["web", "ios", "watchos", "macos", "linux"];
var LABEL = "wrist";
var PLATFORM = "macos";
var allCalls = [];

function b64url(bytes) {
  return nodeCrypto.randomBytes(bytes).toString("base64url");
}

function decodeB64url(value) {
  return Buffer.from(value, "base64url");
}

var privateKey = b64url(32);
if (decodeB64url(privateKey).length !== 32) fail("private key fixture is not 32 bytes");

function opaque(n) {
  var i;
  for (i = 0; i < 8; i++) {
    var value = b64url(n);
    if (decodeB64url(value).length !== n) continue;
    if (!/^[A-Za-z0-9_-]+$/.test(value)) continue;
    if (value === privateKey || value.indexOf(privateKey) !== -1) continue;
    if (value.indexOf(SENTINEL_TOKEN) !== -1) continue;
    if (value.indexOf(SENTINEL_IP) !== -1 || value.indexOf(SENTINEL_HOST) !== -1) continue;
    return value;
  }
  fail("could not mint an opaque base64url value");
}

var publicKey = opaque(32);
var ciphertext = opaque(48);
if (publicKey === privateKey || publicKey.indexOf(privateKey) !== -1 || ciphertext.indexOf(privateKey) !== -1) {
  fail("opaque value contains the private key");
}
if (PLATFORM === undefined || PLATFORMS.indexOf(PLATFORM) === -1) fail("platform is not web, ios, watchos, macos, or linux");

function el() {
  return {
    hidden: false,
    textContent: "",
    className: "",
    disabled: false,
    value: "",
    children: [],
    firstChild: null,
    _listeners: [],
    appendChild: function (child) {
      this.children.push(child);
      this.firstChild = this.children[0] || null;
      return child;
    },
    removeChild: function (child) {
      var i = this.children.indexOf(child);
      if (i >= 0) this.children.splice(i, 1);
      this.firstChild = this.children[0] || null;
      return child;
    },
    addEventListener: function (type, fn) {
      this._listeners.push({ type: type, fn: fn });
    }
  };
}

function makeDocument(page) {
  var setup = el();
  setup.textContent = "Account setup is not finished on this deploy";
  var status = el();
  var ids = { setup: setup, status: status };
  if (page === "home") {
    var empty = el();
    empty.hidden = true;
    empty.textContent = EMPTY;
    var list = el();
    list.hidden = true;
    var del = el();
    ids["devices-empty"] = empty;
    ids["device-labels"] = list;
    ids["delete-account"] = del;
  } else {
    var form = el();
    form.elements = {};
    form.querySelector = function (sel) {
      if (sel === "button[type=submit]") return button;
      return null;
    };
    var button = el();
    ids.form = form;
  }
  return {
    body: {
      getAttribute: function (name) {
        return name === "data-account" ? page : null;
      }
    },
    getElementById: function (id) {
      return Object.prototype.hasOwnProperty.call(ids, id) ? ids[id] : null;
    },
    createElement: function () { return el(); },
    _ids: ids
  };
}

function storageOf() {
  var map = new Map();
  return {
    getItem: function (key) { return map.has(key) ? map.get(key) : null; },
    setItem: function (key, value) { map.set(key, String(value)); },
    removeItem: function (key) { map.delete(key); }
  };
}

function decoyFields(extra) {
  var fields = {
    hostname: { value: SENTINEL_HOST },
    host: { value: "mac.local" },
    ip: { value: SENTINEL_IP },
    token: { value: SENTINEL_TOKEN }
  };
  Object.keys(extra || {}).forEach(function (key) { fields[key] = extra[key]; });
  return fields;
}

function makeFetch(calls) {
  return function (url, init) {
    var options = init || {};
    var call = {
      url: String(url),
      method: options.method || "GET",
      headers: options.headers || {},
      body: Object.prototype.hasOwnProperty.call(options, "body") ? options.body : undefined
    };
    calls.push(call);
    allCalls.push(call);
    var request = { method: call.method, headers: call.headers };
    if (call.body != null) request.body = call.body;
    return fetch(call.url, request).then(function (res) {
      return res.text().then(function (text) {
        call.status = res.status;
        call.responseText = text;
        return {
          ok: res.ok,
          status: res.status,
          text: function () { return Promise.resolve(text); }
        };
      });
    }, function (err) {
      call.networkError = true;
      throw err;
    });
  };
}

function boot(pageName, fields, existingStorage) {
  var calls = [];
  var document = makeDocument(pageName);
  if (document._ids.form) document._ids.form.elements = fields;
  var location = {
    origin: ORIGIN,
    hash: "",
    pathname: "/account/" + pageName,
    search: "",
    assign: function (url) { location.assigned = String(url); }
  };
  var fetchImpl = makeFetch(calls);
  var windowObj = {
    location: location,
    confirm: function () { return false; },
    fetch: fetchImpl,
    MESH_ACCOUNT: { url: api, anonKey: anon }
  };
  var sandbox = {
    document: document,
    window: windowObj,
    history: { replaceState: function () { location.hash = ""; } },
    sessionStorage: existingStorage || storageOf(),
    fetch: fetchImpl,
    URLSearchParams: URLSearchParams,
    Promise: Promise,
    JSON: JSON,
    Object: Object,
    String: String,
    RegExp: RegExp,
    Array: Array,
    Date: Date,
    Error: Error,
    Math: Math,
    Number: Number,
    encodeURIComponent: encodeURIComponent,
    decodeURIComponent: decodeURIComponent,
    console: console,
    setTimeout: setTimeout,
    clearTimeout: clearTimeout
  };
  sandbox.globalThis = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox, { filename: "web/account/account.js" });
  return {
    calls: calls,
    document: document,
    storage: sandbox.sessionStorage,
    fetch: fetchImpl,
    location: location
  };
}

function delay(ms) {
  return new Promise(function (resolve) { setTimeout(resolve, ms); });
}

function submit(page) {
  var form = page.document._ids.form;
  var listeners = form._listeners.filter(function (item) { return item.type === "submit"; });
  if (listeners.length !== 1) fail("expected one submit listener");
  listeners[0].fn({ preventDefault: function () {} });
}

function statusTextOf(page) {
  return page.document._ids.status.textContent || "";
}

function pageSettled(page) {
  var button = page.document._ids.form.querySelector("button[type=submit]");
  if (!button || button.disabled) return false;
  if (!statusTextOf(page)) return false;
  return page.calls.every(function (call) { return call.status != null || call.networkError; });
}

async function waitSettled(page) {
  var start = Date.now();
  var stable = 0;
  while (Date.now() - start < 20000) {
    await delay(40);
    if (pageSettled(page)) stable += 1;
    else stable = 0;
    if (stable >= 3) return;
  }
  fail("page did not settle: " + statusTextOf(page));
}

function deviceReads(page) {
  return page.calls.filter(function (call) {
    return call.method === "GET" && call.url.indexOf("/rest/v1/devices") !== -1;
  });
}

function homeSettled(page) {
  var reads = deviceReads(page);
  if (reads.length !== 1) return false;
  if (reads[0].status == null && !reads[0].networkError) return false;
  if (!statusTextOf(page)) return false;
  return page.calls.every(function (call) { return call.status != null || call.networkError; });
}

async function waitHome(page) {
  var start = Date.now();
  var stable = 0;
  while (Date.now() - start < 20000) {
    await delay(40);
    if (homeSettled(page)) stable += 1;
    else stable = 0;
    if (stable >= 3) return;
  }
  fail("home page did not settle: " + statusTextOf(page));
}

function parsed(call) {
  if (call.body == null) return null;
  return JSON.parse(String(call.body));
}

function keysOf(value) {
  return Object.keys(value || {}).sort().join(",");
}

function callsTo(page, fragment) {
  return page.calls.filter(function (call) { return call.url.indexOf(fragment) !== -1; });
}

function jsonOf(call) {
  if (!call.responseText) return null;
  try { return JSON.parse(call.responseText); } catch (err) { return null; }
}

function assertShape(call, label) {
  var url;
  try { url = new URL(call.url); } catch (err) { fail(label + " request URL was not absolute"); }
  if (url.port === "8899" || call.url.indexOf(":8899") !== -1) fail(label + " called port 8899");
  if (url.hostname !== "127.0.0.1" && url.hostname !== "localhost") fail(label + " left the local API");
  if (call.url.indexOf("supabase.co") !== -1 || call.url.indexOf("zmisjteztezaqfflwbgf") !== -1) {
    fail(label + " left the local stack");
  }
  if (url.hostname.indexOf("vercel") !== -1 || call.url.indexOf("gateway") !== -1) {
    fail(label + " called a hosted gateway");
  }
  var headerText = JSON.stringify(call.headers || {});
  var raw = headerText + "\n" + String(call.body || "") + "\n" + call.url;
  if (raw.indexOf(SENTINEL_TOKEN) !== -1) fail(label + " request carries a mesh token");
  if (raw.indexOf(SENTINEL_IP) !== -1) fail(label + " request carries an ip");
  if (raw.indexOf(SENTINEL_HOST) !== -1 || raw.indexOf("mac.local") !== -1) fail(label + " request carries a hostname");
  if (raw.indexOf("service_role") !== -1) fail(label + " request carries a service role");
  if (raw.indexOf(privateKey) !== -1) fail(label + " request carries a private key");
  ["apikey", "Authorization"].forEach(function (header) {
    var value = call.headers[header] || "";
    var token = header === "Authorization" ? value.replace(/^Bearer\s+/, "") : value;
    if (!token) return;
    var role = jwtRole(token);
    if (role !== "anon" && role !== "authenticated") fail(label + " request credential is not anon or the signed-in user");
  });
  if (call.networkError) fail(label + " network error");
}

function assertProfileWrite(call, id, username) {
  if (call.method !== "POST") fail("profile write is not a POST");
  if (call.status < 200 || call.status >= 300) fail("profile write was refused " + call.status);
  if (call.url.indexOf("/rest/v1/profiles?on_conflict=id") === -1) fail("profile write is not an upsert by id");
  var body = parsed(call);
  if (keysOf(body) !== "id,username") fail("profile write is not {id, username} only");
  if (!body || body.id !== id || body.username !== username) fail("profile write did not keep this user's id and username");
}

function sessionFromTokenCall(call) {
  var data = jsonOf(call);
  if (!data || !data.access_token || !data.user || !data.user.id) return null;
  var meta = data.user.user_metadata || {};
  return { token: data.access_token, id: data.user.id, username: meta.username || "" };
}

function storedSession(page) {
  var raw = page.storage.getItem("mesh.account.session");
  if (!raw) return null;
  var data = JSON.parse(raw);
  if (keysOf(data) !== "id,token,username") fail("page session stored more than id, token, and username");
  return data;
}

function walkText(node, out) {
  if (!node || typeof node !== "object") return;
  if (typeof node.textContent === "string" && node.textContent) out.push(node.textContent);
  if (typeof node.className === "string" && node.className) out.push(node.className);
  (node.children || []).forEach(function (child) { walkText(child, out); });
}

function renderedBlob(page) {
  var out = [];
  ["devices-empty", "device-labels", "status", "setup"].forEach(function (id) {
    walkText(page.document._ids[id], out);
  });
  return out.join("\n");
}

function assertSecretsHidden(page, secrets) {
  var blob = renderedBlob(page);
  secrets.forEach(function (item) {
    if (item && blob.indexOf(item.value) !== -1) fail("page rendered " + item.name);
  });
}

function deviceQuery(call, session) {
  var url;
  try { url = new URL(call.url); } catch (err) { fail("device read URL was not absolute"); }
  if (url.pathname !== "/rest/v1/devices") fail("device read is not the devices table");
  if (url.searchParams.get("select") !== "label,platform") fail("device read select is not label,platform");
  if (url.searchParams.get("user_id") !== "eq." + session.id) fail("device read is not limited to the signed-in user");
  var select = url.searchParams.get("select") || "";
  ["public_key", "user_id", "ciphertext", "token", "ip", "hostname"].forEach(function (column) {
    if (select.split(",").indexOf(column) !== -1) fail("device read selects " + column);
  });
}

function renderedRows(page) {
  var list = page.document._ids["device-labels"];
  return (list.children || []).map(function (li) {
    return (li.children || []).map(function (span) {
      return { className: span.className, text: span.textContent };
    });
  });
}

async function signUp(username, email, password) {
  var page = boot("sign-up", decoyFields({
    username: { value: username },
    email: { value: email },
    password: { value: password }
  }));
  submit(page);
  await waitSettled(page);
  page.calls.forEach(function (call) { assertShape(call, "sign-up"); });
  if (statusTextOf(page).length && page.document._ids.status.className.indexOf("error") !== -1) {
    fail("sign-up failed: " + statusTextOf(page));
  }
  return page;
}

async function signIn(email, password) {
  var page = boot("sign-in", decoyFields({
    email: { value: email },
    password: { value: password },
    username: { value: "should-not-be-sent" }
  }));
  submit(page);
  await waitSettled(page);
  page.calls.forEach(function (call) { assertShape(call, "sign-in"); });
  if (statusTextOf(page).length && page.document._ids.status.className.indexOf("error") !== -1) {
    fail("sign-in failed: " + statusTextOf(page));
  }
  return page;
}

async function openHome(storage) {
  var page = boot("home", {}, storage);
  await waitHome(page);
  page.calls.forEach(function (call) { assertShape(call, "home"); });
  var session = storedSession(page);
  if (!session) fail("home page has no signed-in session");
  var reads = deviceReads(page);
  if (reads.length !== 1) fail("home page did not read device labels once");
  if (reads[0].status !== 200) fail("device label read was refused " + reads[0].status);
  deviceQuery(reads[0], session);
  var rows = jsonOf(reads[0]);
  if (!Array.isArray(rows)) fail("device label read was not a list");
  rows.forEach(function (row) {
    if (keysOf(row) !== "label,platform") fail("device label read returned more than label and platform");
  });
  return { page: page, session: session, rows: rows, read: reads[0] };
}

async function rest(page, method, path, body, prefer) {
  var session = storedSession(page);
  if (!session || !session.token) fail("page script did not keep a sign-in session");
  var headers = {
    apikey: anon,
    Authorization: "Bearer " + session.token,
    Accept: "application/json"
  };
  var init = { method: method, headers: headers };
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
    init.body = JSON.stringify(body);
  }
  if (prefer) headers.Prefer = prefer;
  var response = await page.fetch(api + path, init);
  var text = await response.text();
  var data = null;
  if (text) {
    try { data = JSON.parse(text); } catch (err) { data = { message: text.slice(0, 180) }; }
  }
  if (response.status == null) fail("rest call did not finish");
  return { status: response.status, data: data, text: text };
}

async function selectRows(page, path) {
  var result = await rest(page, "GET", path);
  if (result.status !== 200 || !Array.isArray(result.data)) {
    fail("select failed " + result.status + " " + path.split("?")[0]);
  }
  return result;
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

  await signUp(userA, emailA, passwordA);
  var signedA = await signIn(emailA, passwordA);
  var tokenCalls = callsTo(signedA, "/auth/v1/token");
  if (tokenCalls.length !== 1) fail("sign-in did not send one token request");
  var sessionA = sessionFromTokenCall(tokenCalls[0]);
  if (!sessionA || sessionA.username !== userA) fail("sign-in did not return user A");
  var profilesA = callsTo(signedA, "/rest/v1/profiles");
  if (profilesA.length !== 1) fail("sign-in did not write user A's profile");
  assertProfileWrite(profilesA[0], sessionA.id, userA);
  var keptA = storedSession(signedA);
  if (!keptA || keptA.id !== sessionA.id || keptA.token !== sessionA.token) {
    fail("page script did not store user A's sign-in session");
  }

  var before = await openHome(signedA.storage);
  var empty = before.page.document._ids["devices-empty"];
  var list = before.page.document._ids["device-labels"];
  if (before.rows.length !== 0) fail("user A had a device before the insert");
  if (empty.hidden !== false) fail("empty state stayed hidden before any device");
  if (empty.textContent !== EMPTY) fail("empty state text changed");
  if (list.hidden !== true || list.children.length !== 0) fail("device list rendered before any device");
  console.log("empty_state: shown");
  console.log("empty_state_text: " + EMPTY);

  var deviceBody = {
    user_id: sessionA.id,
    label: LABEL,
    platform: PLATFORM,
    public_key: publicKey
  };
  if (keysOf(deviceBody) !== "label,platform,public_key,user_id") {
    fail("device insert keys are not user_id, label, platform, public_key");
  }
  if (["token", "ip", "hostname", "private_key", "ciphertext"].some(function (key) {
    return Object.prototype.hasOwnProperty.call(deviceBody, key);
  })) fail("device insert includes a forbidden column");
  if (decodeB64url(deviceBody.public_key).length !== 32) fail("public key is not 32 bytes");
  var inserted = await rest(signedA, "POST", "/rest/v1/devices", deviceBody, "return=representation");
  if (inserted.status !== 200 && inserted.status !== 201) fail("device insert failed " + inserted.status);
  if (!Array.isArray(inserted.data) || inserted.data.length !== 1) fail("device insert did not return one row");
  var device = inserted.data[0];
  var deviceId = device.id || "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(deviceId)) {
    fail("device insert did not return an id");
  }
  if (device.user_id !== sessionA.id || device.label !== LABEL || device.platform !== PLATFORM) {
    fail("device insert did not store this user's label and platform");
  }
  if (device.public_key !== publicKey || decodeB64url(device.public_key).length !== 32) {
    fail("stored public key is not the 32-byte insert");
  }
  if (device.public_key === privateKey) fail("stored public key is the private key");
  console.log("device insert keys: user_id, label, platform, public_key");
  console.log("device platform: " + PLATFORM);
  console.log("public_key_bytes: 32");
  console.log("public_key_is_private_key: false");

  var mailboxBody = {
    user_id: sessionA.id,
    recipient_device_id: deviceId,
    sender_device_id: deviceId,
    ciphertext: ciphertext,
    expires_at: "2030-01-01T00:00:00Z"
  };
  if (keysOf(mailboxBody) !== "ciphertext,expires_at,recipient_device_id,sender_device_id,user_id") {
    fail("mailbox insert is not the ciphertext row");
  }
  var boxed = await rest(signedA, "POST", "/rest/v1/mailbox", mailboxBody, "return=representation");
  if (boxed.status !== 200 && boxed.status !== 201) fail("mailbox insert failed " + boxed.status);

  var after = await openHome(signedA.storage);
  var shown = renderedRows(after.page);
  if (after.rows.length !== 1) fail("signed-in page did not receive the one device");
  if (after.rows[0].label !== LABEL || after.rows[0].platform !== PLATFORM) {
    fail("signed-in page did not receive label and platform");
  }
  if (JSON.stringify(shown) !== JSON.stringify([[
    { className: "device-label", text: LABEL },
    { className: "device-platform", text: PLATFORM }
  ]])) fail("signed-in page did not render only label and platform");
  var afterEmpty = after.page.document._ids["devices-empty"];
  var afterList = after.page.document._ids["device-labels"];
  if (afterList.hidden !== false) fail("device list stayed hidden after the insert");
  if (afterEmpty.hidden !== true) fail("empty state stayed visible after the insert");
  if ((after.read.responseText || "").indexOf(publicKey) !== -1) fail("label read returned the public key");
  if ((after.read.responseText || "").indexOf(ciphertext) !== -1) fail("label read returned ciphertext");
  if ((after.read.responseText || "").indexOf(sessionA.id) !== -1) fail("label read returned the user id");
  var secrets = [
    { name: "public_key", value: publicKey },
    { name: "user_id", value: sessionA.id },
    { name: "ciphertext", value: ciphertext },
    { name: "token", value: SENTINEL_TOKEN },
    { name: "ip", value: SENTINEL_IP },
    { name: "hostname", value: SENTINEL_HOST },
    { name: "private_key", value: privateKey }
  ];
  assertSecretsHidden(after.page, secrets);
  console.log("page renders: label, platform");
  console.log("rendered_public_key: false");
  console.log("rendered_user_id: false");
  console.log("rendered_ciphertext: false");
  console.log("rendered_token: false");
  console.log("rendered_ip: false");
  console.log("rendered_hostname: false");

  await signUp(userB, emailB, passwordB);
  var signedB = await signIn(emailB, passwordB);
  var tokenBCall = callsTo(signedB, "/auth/v1/token")[0];
  var sessionB = sessionFromTokenCall(tokenBCall || {});
  if (!sessionB || sessionB.username !== userB || sessionB.id === sessionA.id) {
    fail("second sign-in did not return a different user");
  }
  var profilesB = callsTo(signedB, "/rest/v1/profiles");
  if (profilesB.length !== 1) fail("second sign-in did not write a profile");
  assertProfileWrite(profilesB[0], sessionB.id, userB);
  if (!storedSession(signedB) || storedSession(signedB).id !== sessionB.id) {
    fail("second page script did not store its session");
  }

  var homeB = await openHome(signedB.storage);
  var blobB = renderedBlob(homeB.page);
  if (homeB.rows.length !== 0 || renderedRows(homeB.page).length !== 0) {
    fail("user B's page rendered a device");
  }
  if (blobB.indexOf(LABEL) !== -1) fail("user B's page rendered user A's label");
  if (homeB.page.document._ids["devices-empty"].hidden !== false) {
    fail("user B's page hid the empty state");
  }
  if (homeB.page.document._ids["devices-empty"].textContent !== EMPTY) {
    fail("user B's empty state text changed");
  }
  assertSecretsHidden(homeB.page, secrets);
  console.log("user_b_sees_a_label: false");

  var ownProfile = await selectRows(signedA, "/rest/v1/profiles?id=eq." + encodeURIComponent(sessionA.id) + "&select=id,username");
  if (ownProfile.data.length !== 1 || ownProfile.data[0].username !== userA) {
    fail("owner could not select their own profile");
  }
  var ownDevices = await selectRows(signedA, "/rest/v1/devices?user_id=eq." + encodeURIComponent(sessionA.id) + "&select=label");
  if (ownDevices.data.length !== 1 || ownDevices.data[0].label !== LABEL) {
    fail("owner could not select their own device");
  }
  var ownMail = await selectRows(signedA, "/rest/v1/mailbox?user_id=eq." + encodeURIComponent(sessionA.id) + "&select=ciphertext");
  if (ownMail.data.length !== 1 || ownMail.data[0].ciphertext !== ciphertext) {
    fail("owner could not select their own mailbox");
  }

  async function expectEmpty(path) {
    var result = await selectRows(signedB, path);
    if (result.data.length !== 0) fail("second user can select " + path.split("?")[0]);
    if (result.text.indexOf(publicKey) !== -1 || result.text.indexOf(ciphertext) !== -1 || result.text.indexOf(privateKey) !== -1) {
      fail("second user select returned a secret");
    }
    if (result.text.indexOf(LABEL) !== -1) fail("second user select returned user A's label");
  }

  var aFilter = encodeURIComponent(sessionA.id);
  var deviceFilter = encodeURIComponent(deviceId);
  await expectEmpty("/rest/v1/profiles?id=eq." + aFilter + "&select=id,username");
  await expectEmpty("/rest/v1/devices?user_id=eq." + aFilter + "&select=id,user_id,label,platform,public_key");
  await expectEmpty("/rest/v1/devices?id=eq." + deviceFilter + "&select=id,label");
  await expectEmpty("/rest/v1/mailbox?user_id=eq." + aFilter + "&select=id,ciphertext");
  await expectEmpty("/rest/v1/mailbox?recipient_device_id=eq." + deviceFilter + "&select=id,ciphertext");
  var seenProfiles = await selectRows(signedB, "/rest/v1/profiles?select=id,username");
  var seenIds = seenProfiles.data.map(function (row) { return row.id; });
  if (seenIds.indexOf(sessionA.id) !== -1 || seenIds.join(",") !== sessionB.id) {
    fail("second user can select the first user's profile");
  }
  var seenDevices = await selectRows(signedB, "/rest/v1/devices?select=id,label");
  if (seenDevices.data.length !== 0) fail("second user can select devices without a filter");
  var seenMail = await selectRows(signedB, "/rest/v1/mailbox?select=id,ciphertext");
  if (seenMail.data.length !== 0) fail("second user can select mailbox without a filter");
  console.log("b_sees_a_profile: 0");
  console.log("b_sees_a_devices: 0");
  console.log("b_sees_a_mailbox: 0");

  allCalls.forEach(function (call) { assertShape(call, "account page"); });
  if (nodeCrypto.createHash("sha256").update(fs.readFileSync(sqlPath)).digest("hex") !== expectedSha) {
    fail("identity SQL hash changed");
  }
  var homeAfter = fs.readdirSync(homeDir).slice().sort();
  if (homeAfter.join("\n") !== homeBefore.join("\n") || fs.existsSync(meshDir)) {
    fail("wrote under the home directory");
  }
  console.log("requests to port 8899: none");
  console.log("home_write: false");
  console.log("mesh_dir: false");
  console.log("account-device-labels: OK");
}

main().catch(function (err) {
  fail(err && err.stack ? err.stack : err);
});
NODE
node "$RUNNER" "$STATUS" "$SQL" "$JS" "$PAGE" "$EXPECTED_SQL_SHA"
