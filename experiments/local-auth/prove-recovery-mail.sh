#!/bin/sh
# Prove the password-recovery email does not carry mailbox ciphertext, a
# device public key, or a mesh token. Recovery mail is rendered by local
# auth, so this seeds those rows only after a confirmed auth user exists,
# asks auth to send the reset while the rows are there, and reads the
# owner ciphertext back from the database. The product default is confirmation
# on; the committed local config keeps it off so prove-pages.sh can sign up
# with an immediate session. This script flips enable_confirmations for its
# own run, restores the file on every exit, and never leaves that toggle in
# git. Not a scripts/check-*.sh file: check-all.sh must not start Docker.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SQL="$ROOT/supabase/account/001_identity.sql"
JS="$ROOT/web/account/account.js"
CONFIG="$ROOT/supabase/config.toml"

[ -f "$SQL" ] || { echo "FAIL: missing $SQL"; exit 1; }
[ -f "$JS" ] || { echo "FAIL: missing $JS"; exit 1; }
[ -f "$CONFIG" ] || { echo "FAIL: missing $CONFIG"; exit 1; }
command -v supabase >/dev/null || { echo "FAIL: supabase CLI is not installed"; exit 1; }
command -v psql >/dev/null || { echo "FAIL: psql is not installed"; exit 1; }
command -v node >/dev/null || { echo "FAIL: node is not installed"; exit 1; }
command -v docker >/dev/null || { echo "FAIL: docker is not installed"; exit 1; }

# Local containers need bridge forwarding. DROP on FORWARD breaks the stack.
if command -v iptables-legacy >/dev/null 2>&1; then
  if iptables-legacy -L FORWARD -n 2>/dev/null | head -1 | grep -q 'policy DROP'; then
    if command -v sudo >/dev/null 2>&1; then
      sudo iptables-legacy -P FORWARD ACCEPT || true
    else
      iptables-legacy -P FORWARD ACCEPT || true
    fi
  fi
fi

CONFIG_BAK="$(mktemp)"
STATUS="$(mktemp)"
CONFIRM_ON=0
RESTORED=0

restore_config() {
  if [ "$RESTORED" -eq 0 ] && [ -f "$CONFIG_BAK" ]; then
    cp "$CONFIG_BAK" "$CONFIG"
    RESTORED=1
    if [ "$CONFIRM_ON" -eq 1 ]; then
      # Bring the running auth service back in line with the restored file.
      supabase stop >/dev/null 2>&1 || true
      supabase start >/dev/null 2>&1 || true
    fi
  fi
  rm -f "$CONFIG_BAK" "$STATUS"
}

trap 'restore_config' EXIT INT TERM

cp "$CONFIG" "$CONFIG_BAK"

# Flip only [auth.email] enable_confirmations. Leave [auth.sms] alone.
node - "$CONFIG" << 'TOGGLE'
"use strict";
var fs = require("fs");
var path = process.argv[2];
var text = fs.readFileSync(path, "utf8");
var lines = text.split(/\n/);
var section = "";
var changed = false;
for (var i = 0; i < lines.length; i++) {
  var line = lines[i];
  var heading = line.match(/^\[([^\]]+)\]\s*$/);
  if (heading) section = heading[1];
  if (section === "auth.email" && /^\s*enable_confirmations\s*=/.test(line)) {
    lines[i] = "enable_confirmations = true";
    changed = true;
  }
}
if (!changed) {
  console.error("FAIL: could not find [auth.email] enable_confirmations in config.toml");
  process.exit(1);
}
fs.writeFileSync(path, lines.join("\n"));
TOGGLE

CONFIRM_ON=1
if ! supabase stop >/dev/null 2>&1; then
  echo "FAIL: could not stop the local supabase stack before enabling confirmations"
  exit 1
fi
if ! supabase start >/dev/null 2>&1; then
  echo "FAIL: local supabase did not start with email confirmations enabled"
  exit 1
fi

if ! supabase status -o env >"$STATUS" 2>/dev/null; then
  echo "FAIL: local supabase is not running after enabling confirmations"
  exit 1
fi

node - "$STATUS" "$SQL" "$JS" "$CONFIG" "$CONFIG_BAK" << 'NODE'
"use strict";

var fs = require("fs");
var vm = require("vm");
var http = require("http");
var https = require("https");
var nodeCrypto = require("crypto");
var child = require("child_process");
var os = require("os");
var path = require("path");

var statusPath = process.argv[2];
var sqlPath = process.argv[3];
var jsPath = process.argv[4];
var configPath = process.argv[5];
var configBakPath = process.argv[6];
var source = fs.readFileSync(jsPath, "utf8");
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
    .replace(/sb_secret_\S+/g, "REDACTED_SECRET")
    .replace(/(apikey|authorization|access_token|refresh_token|bearer)\s*[:=]\s*\S+/gi, "$1=REDACTED");
}

var api = String(env.API_URL || "").replace(/\/+$/, "");
var anon = String(env.ANON_KEY || "");
var db = String(env.DB_URL || "");
var mail = String(env.MAILPIT_URL || env.INBUCKET_URL || "").replace(/\/+$/, "");
if (!api || !anon || !db || !mail) {
  fail("local status did not include API_URL, ANON_KEY, DB_URL, and MAILPIT_URL");
}
var blob = api + " " + db + " " + mail;
if (blob.indexOf("supabase.co") !== -1 || blob.indexOf("zmisjteztezaqfflwbgf") !== -1) {
  fail("refusing a non-local stack");
}
if (!/^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(api)) fail("API_URL is not a local loopback address");
if (!/^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(mail)) fail("MAILPIT_URL is not a local loopback address");

var configNow = fs.readFileSync(configPath, "utf8");
if (!/\[auth\.email\][\s\S]*?enable_confirmations\s*=\s*true/.test(configNow)) {
  fail("email confirmations were not enabled for this run");
}
var configBak = fs.readFileSync(configBakPath, "utf8");
if (!/\[auth\.email\][\s\S]*?enable_confirmations\s*=\s*false/.test(configBak)) {
  fail("config backup is not the confirmations-off baseline");
}

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

var ORIGIN = "http://127.0.0.1:3000";
var SENTINEL_TOKEN = "mesh-token-sentinel";
var SENTINEL_IP = "10.1.2.3";
var SENTINEL_HOST = "kitchen.local";
var allCalls = [];
var meshDir = path.join(os.homedir(), ".mesh");
var meshBefore = null;
try {
  meshBefore = fs.statSync(meshDir).mtimeMs;
} catch (err) {
  meshBefore = null;
}

var marker = "";
var publicKey = "";
var privateKey = "";

function el() {
  return {
    hidden: false,
    textContent: "",
    className: "",
    disabled: false,
    children: [],
    firstChild: null,
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
    }
  };
}

function makeDocument(page) {
  var setup = el();
  var status = el();
  var form = el();
  form.elements = {};
  form._listeners = [];
  form.addEventListener = function (type, fn) {
    this._listeners.push({ type: type, fn: fn });
  };
  var button = el();
  form.querySelector = function (sel) {
    if (sel === "button[type=submit]") return button;
    return null;
  };
  var ids = { setup: setup, status: status, form: form };
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

function boot(pageName, fields, hash) {
  var calls = [];
  var assigned = [];
  var document = makeDocument(pageName);
  document._ids.form.elements = fields;
  var location = {
    origin: ORIGIN,
    hash: hash || "",
    pathname: "/account/" + pageName,
    search: "",
    assign: function (url) { assigned.push(String(url)); }
  };
  var fetchImpl = function (url, init) {
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
        var headerLines = [];
        res.headers.forEach(function (value, key) {
          headerLines.push(key + ": " + value);
        });
        call.responseHeaders = headerLines.join("\n");
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
    sessionStorage: storageOf(),
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
    assigned: assigned,
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
  var headerText = JSON.stringify(call.headers || {});
  var raw = headerText + "\n" + String(call.body || "") + "\n" + call.url;
  if (raw.indexOf(SENTINEL_TOKEN) !== -1) fail(label + " request carries a mesh token");
  if (raw.indexOf(SENTINEL_IP) !== -1) fail(label + " request carries an ip");
  if (raw.indexOf(SENTINEL_HOST) !== -1 || raw.indexOf("mac.local") !== -1) fail(label + " request carries a hostname");
  if (raw.indexOf("service_role") !== -1) fail(label + " request carries a service role");
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
  if (call.headers.Prefer !== "resolution=merge-duplicates,return=minimal") fail("profile write prefer header changed");
  if (marker && JSON.stringify(body).indexOf(marker) !== -1) fail("profile write contains mailbox ciphertext");
  if (publicKey && JSON.stringify(body).indexOf(publicKey) !== -1) fail("profile write contains the device public key");
}

function sessionFromTokenCall(call) {
  var data = jsonOf(call);
  if (!data || !data.access_token || !data.user || !data.user.id) return null;
  var meta = data.user.user_metadata || {};
  return { token: data.access_token, id: data.user.id, username: meta.username || "" };
}

function userIdFromSignup(call) {
  var data = jsonOf(call);
  if (!data) return "";
  if (data.user && data.user.id) return String(data.user.id);
  if (data.id) return String(data.id);
  return "";
}

function storedSession(page) {
  var raw = page.storage.getItem("mesh.account.session");
  if (!raw) return null;
  var data = JSON.parse(raw);
  if (keysOf(data) !== "id,token,username") fail("page session stored more than id, token, and username");
  return data;
}

async function selectRows(page, query) {
  var session = storedSession(page);
  if (!session || !session.token) fail("page script did not keep a sign-in session");
  var url = api + query;
  var response = await page.fetch(url, {
    method: "GET",
    headers: {
      apikey: anon,
      Authorization: "Bearer " + session.token,
      Accept: "application/json"
    }
  });
  var text = await response.text();
  var rows = text ? JSON.parse(text) : null;
  if (response.status !== 200 || !Array.isArray(rows)) {
    fail("select failed " + response.status + " " + query.split("?")[0]);
  }
  return { rows: rows, text: text, url: url };
}

function usernameOf(prefix) {
  var name = prefix + nodeCrypto.randomBytes(4).toString("hex");
  if (!/^[a-z0-9_]{3,32}$/.test(name)) fail("generated username does not match the profile pattern");
  return name;
}

function profileCountFor(userId) {
  if (!userId) fail("missing auth user id for profile count");
  return psql(
    "select count(*)::int from public.profiles where id = '" + userId.replace(/'/g, "''") + "'"
  ).trim();
}

function sqlQuote(value) {
  return "'" + String(value).replace(/'/g, "''") + "'";
}

function assertUuid(value, label) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)) {
    fail(label + " is not a uuid");
  }
}

function assertNoSecrets(text, label) {
  var raw = String(text || "");
  if (!marker || !publicKey) fail(label + " was checked before the mailbox marker existed");
  if (raw.indexOf(marker) !== -1) fail(label + " contains mailbox ciphertext");
  if (raw.indexOf(publicKey) !== -1) fail(label + " contains the device public key");
  if (raw.indexOf(SENTINEL_TOKEN) !== -1) fail(label + " contains a mesh token");
  if (privateKey && raw.indexOf(privateKey) !== -1) fail(label + " contains a private key");
}

function makeSecrets(username, email, password) {
  var pub = nodeCrypto.randomBytes(32);
  var priv = nodeCrypto.randomBytes(32);
  var nextPublic = pub.toString("base64url");
  var nextPrivate = priv.toString("base64url");
  var nextMarker = "ctmarker-" + nodeCrypto.randomBytes(24).toString("hex");
  if (Buffer.from(nextPublic, "base64url").length !== 32) fail("device public key is not 32 bytes");
  if (Buffer.from(nextPrivate, "base64url").length !== 32) fail("private key material is not 32 bytes");
  if (nextPublic === nextPrivate) fail("public key is the private key");
  if (nextMarker === nextPrivate || nextPublic === nextPrivate) fail("marker or public key is the private key");
  if (nextMarker === nextPublic) fail("ciphertext marker is the device public key");
  [username, email, password, SENTINEL_TOKEN].forEach(function (item) {
    if (!item) return;
    if (nextMarker === item || nextMarker.indexOf(item) !== -1 || item.indexOf(nextMarker) !== -1) {
      fail("ciphertext marker is the username, email, or password");
    }
  });
  if (nextMarker.indexOf(nextPrivate) !== -1 || nextPublic.indexOf(nextPrivate) !== -1) {
    fail("marker or public key is the private key");
  }
  marker = nextMarker;
  publicKey = nextPublic;
  privateKey = nextPrivate;
}

function seedMailbox(userId) {
  assertUuid(userId, "auth user");
  if (!marker || !publicKey || !privateKey) fail("mailbox seed is missing its marker or keys");
  if (marker === privateKey || publicKey === privateKey) fail("marker or public key is the private key");
  var inserted = psql(
    "with dev as (" +
    "insert into public.devices (user_id, label, platform, public_key) values (" +
    sqlQuote(userId) + ", 'wrist', 'web', " + sqlQuote(publicKey) + ") returning id) " +
    "insert into public.mailbox (user_id, recipient_device_id, sender_device_id, ciphertext, expires_at) " +
    "select " + sqlQuote(userId) + ", dev.id, dev.id, " + sqlQuote(marker) + ", '2030-01-01 00:00:00+00' from dev " +
    "returning id"
  ).trim().split(/\n/)[0].trim();
  assertUuid(inserted, "mailbox row");
  var storedKey = psql(
    "select public_key from public.devices where user_id = " + sqlQuote(userId)
  ).trim();
  var storedBox = psql(
    "select ciphertext from public.mailbox where user_id = " + sqlQuote(userId)
  ).trim();
  if (storedKey !== publicKey) fail("device public key was not stored");
  if (storedBox !== marker) fail("mailbox ciphertext was not stored");
  if (storedKey === privateKey || storedBox === privateKey) fail("stored value is the private key");
  if (storedKey.indexOf(privateKey) !== -1 || storedBox.indexOf(privateKey) !== -1) {
    fail("private key was stored");
  }
  if (storedBox === storedKey) fail("ciphertext marker is the device public key");
}

function assertLocalSiteUrl(url, label) {
  var parsedUrl;
  try { parsedUrl = new URL(url); } catch (err) { fail(label + " is not a URL"); }
  if (parsedUrl.hostname !== "127.0.0.1" && parsedUrl.hostname !== "localhost") {
    fail(label + " is not the local site");
  }
  if (String(url).indexOf("supabase.co") !== -1 || String(url).indexOf("zmisjteztezaqfflwbgf") !== -1) {
    fail(label + " points at a hosted project");
  }
}

function assertLoopback(url, label) {
  var parsedUrl;
  try { parsedUrl = new URL(url); } catch (err) { fail(label + " URL was not absolute"); }
  if (parsedUrl.hostname !== "127.0.0.1" && parsedUrl.hostname !== "localhost") fail(label + " left the local stack");
  if (parsedUrl.port === "8899" || url.indexOf(":8899") !== -1) fail(label + " called port 8899");
  if (url.indexOf("supabase.co") !== -1 || url.indexOf("zmisjteztezaqfflwbgf") !== -1) fail(label + " left the local stack");
  return parsedUrl;
}

function requestOnce(url) {
  return new Promise(function (resolve, reject) {
    var parsedUrl = assertLoopback(url, "recovery redirect");
    var lib = parsedUrl.protocol === "https:" ? https : http;
    var req = lib.get({
      hostname: parsedUrl.hostname,
      port: parsedUrl.port,
      path: parsedUrl.pathname + parsedUrl.search,
      headers: { Accept: "text/html" }
    }, function (res) {
      var chunks = [];
      res.on("data", function (chunk) { chunks.push(chunk); });
      res.on("end", function () {
        resolve({
          status: res.statusCode || 0,
          location: res.headers.location || "",
          body: Buffer.concat(chunks).toString("utf8"),
          headers: res.headers
        });
      });
    });
    req.on("error", reject);
  });
}

function decodeMail(text) {
  return String(text || "")
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, "\"")
    .replace(/&#39;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

function judgeLanding(url) {
  var parsedUrl = assertLoopback(url, "recovery email redirect");
  var bare = url.split("#")[0];
  if (!bare.endsWith("/account/reset") || parsedUrl.pathname !== "/account/reset") {
    fail("recovery email redirect does not end in /account/reset");
  }
  var hash = new URLSearchParams((parsedUrl.hash || "").replace(/^#/, ""));
  var token = hash.get("access_token") || "";
  var type = hash.get("type") || "";
  if (token && type === "recovery" && !hash.get("error") && !hash.get("error_description")) {
    return { hash: parsedUrl.hash, token: token };
  }
  if (parsedUrl.searchParams.get("code") || (token && type !== "recovery")) {
    fail("reset page reads the recovery session from the URL hash (access_token with type=recovery). This redirect does not provide that session, so the page cannot set a password without a code change.");
  }
  return null;
}

async function chase(startUrl) {
  var current = startUrl;
  var followed = false;
  for (var hop = 0; hop < 4; hop++) {
    var parsedNow = assertLoopback(current, "recovery redirect");
    if (parsedNow.pathname === "/account/reset") {
      if (!followed && !parsedNow.hash) return null;
      assertNoSecrets(current, "recovery redirect");
      return judgeLanding(current);
    }
    var res = await requestOnce(current);
    var redirectBlob = String(res.location || "") + "\n" + String(res.body || "");
    assertNoSecrets(redirectBlob, "recovery redirect");
    if (!(res.status >= 300 && res.status < 400 && res.location)) return null;
    current = new URL(res.location, current).href;
    followed = true;
  }
  fail("recovery email redirect did not end in /account/reset");
}

async function listingFor(email) {
  var listingRes = await fetch(mail + "/api/v1/messages");
  if (!listingRes.ok) fail("mail listing failed");
  var listing = await listingRes.json();
  return (listing.messages || []).filter(function (item) {
    var recipients = (item.To || []).map(function (person) {
      return String(person.Address || "").toLowerCase();
    });
    return recipients.indexOf(email.toLowerCase()) !== -1;
  });
}

async function loadMessage(item) {
  var id = String(item.ID || "");
  if (!id) fail("recovery message had no id");
  var messageRes = await fetch(mail + "/api/v1/message/" + encodeURIComponent(id));
  if (!messageRes.ok) fail("recovery message was not readable");
  var message = await messageRes.json();
  var rawRes = await fetch(mail + "/api/v1/message/" + encodeURIComponent(id) + "/raw");
  var raw = rawRes.ok ? await rawRes.text() : "";
  var headerRes = await fetch(mail + "/api/v1/message/" + encodeURIComponent(id) + "/headers");
  var headerText = headerRes.ok ? await headerRes.text() : "";
  var listed = JSON.stringify({
    From: item.From || message.From || "",
    To: item.To || message.To || "",
    Subject: item.Subject || message.Subject || "",
    Headers: message.Headers || message.headers || ""
  });
  return {
    item: item,
    message: message,
    body: decodeMail(String(message.HTML || "") + "\n" + String(message.Text || "")),
    headers: raw + "\n" + headerText + "\n" + listed
  };
}

function assertMessageClean(bundle, label) {
  if (!String(bundle.body || "").trim()) fail(label + " had no body");
  if (!String(bundle.headers || "").trim()) fail(label + " headers were not readable");
  assertNoSecrets(bundle.body, label + " body");
  assertNoSecrets(bundle.headers, label + " headers");
}

async function recoveryLanding(email) {
  var deadline = Date.now() + 25000;
  var tried = Object.create(null);
  while (Date.now() < deadline) {
    var items = await listingFor(email);
    for (var i = 0; i < items.length; i++) {
      var bundle = await loadMessage(items[i]);
      assertMessageClean(bundle, "recovery message");
      if (bundle.body.indexOf("/account/reset") === -1 && bundle.body.indexOf("%2Faccount%2Freset") === -1) {
        continue;
      }
      var urls = bundle.body.match(/https?:\/\/[^\s\"'<>]+/g) || [];
      for (var u = 0; u < urls.length; u++) {
        var url = urls[u].replace(/[),.;]+$/, "");
        if (tried[url]) continue;
        tried[url] = true;
        var parsedUrl = assertLoopback(url, "recovery mail");
        if (parsedUrl.pathname.indexOf("/verify") === -1) continue;
        assertNoSecrets(url, "recovery mail link");
        var landed = await chase(url);
        if (landed && landed.token) return landed;
      }
    }
    await delay(400);
  }
  fail("recovery email redirect did not end in /account/reset");
}

async function waitMessages(email, minCount) {
  var deadline = Date.now() + 25000;
  while (Date.now() < deadline) {
    var items = await listingFor(email);
    if (items.length >= minCount) {
      var loaded = [];
      for (var i = 0; i < items.length; i++) loaded.push(await loadMessage(items[i]));
      return loaded;
    }
    await delay(400);
  }
  fail("expected at least " + minCount + " local confirmation messages");
}

function confirmationLinks(bundles) {
  var links = [];
  bundles.forEach(function (bundle) {
    var urls = String(bundle.body || "").match(/https?:\/\/[^\s\"'<>]+/g) || [];
    urls.forEach(function (url) {
      var href = url.replace(/&amp;/g, "&");
      if (href.indexOf("/auth/v1/verify") === -1 && href.indexOf("type=signup") === -1 && href.indexOf("confirmation") === -1) {
        return;
      }
      links.push(href);
    });
  });
  if (!links.length) fail("no local confirmation email link");
  return links;
}

async function followConfirmation(bundles) {
  var links = confirmationLinks(bundles);
  var href = links[0];
  var redirectMatch = href.match(/redirect_to=([^&]+)/);
  if (redirectMatch) {
    assertLocalSiteUrl(decodeURIComponent(redirectMatch[1]), "confirmation redirect_to");
  }
  assertLocalSiteUrl(ORIGIN, "confirmation redirect");
  var followed = await fetch(href, { redirect: "manual" });
  var location = followed.headers.get("location") || "";
  if (location) {
    if (location.indexOf("supabase.co") !== -1 || location.indexOf("zmisjteztezaqfflwbgf") !== -1) {
      fail("confirmation follow redirected to a hosted URL");
    }
    var locHost = "";
    try { locHost = new URL(location, api).hostname; } catch (err) { locHost = ""; }
    if (locHost && locHost !== "127.0.0.1" && locHost !== "localhost") {
      fail("confirmation follow left the local site");
    }
  }
  if (location) {
    try { await fetch(location, { redirect: "manual" }); } catch (err) {}
  }
  return href;
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
  return page;
}

function assertSignupHeld(page, email, password, username) {
  var signupCalls = callsTo(page, "/auth/v1/signup");
  if (signupCalls.length !== 1) fail("sign-up did not send one signup request");
  var signupBody = parsed(signupCalls[0]);
  if (signupCalls[0].method !== "POST") fail("sign-up is not a POST");
  if (keysOf(signupBody) !== "data,email,password") fail("sign-up body is not username, email, and password");
  if (!signupBody || signupBody.email !== email || signupBody.password !== password) {
    fail("sign-up did not send email and password");
  }
  if (keysOf(signupBody.data) !== "username" || signupBody.data.username !== username) {
    fail("sign-up did not send username");
  }
  if (signupCalls[0].status < 200 || signupCalls[0].status >= 300) fail("sign-up was refused");
  if (page.document._ids.status.className.indexOf("error") !== -1) fail("sign-up failed: " + statusTextOf(page));
  if (sessionFromTokenCall(signupCalls[0])) fail("sign-up returned a session while confirmations are required");
  if (callsTo(page, "/rest/v1/profiles").length !== 0) fail("profile write did not wait for sign-in");
  if (callsTo(page, "/auth/v1/token").length !== 0) fail("sign-up signed in when there was no session");
  if (statusTextOf(page).indexOf("Check your email") === -1) {
    fail("sign-up did not ask to confirm email before sign-in");
  }
  var userId = userIdFromSignup(signupCalls[0]);
  if (!userId) fail("sign-up response did not include the auth user id");
  if (profileCountFor(userId) !== "0") fail("profile row existed before confirmation");
  return { call: signupCalls[0], userId: userId };
}

async function assertSignedInProfile(email, password, userId, username) {
  var signedIn = await signIn(email, password);
  if (signedIn.document._ids.status.className.indexOf("error") !== -1) {
    fail("sign-in failed: " + statusTextOf(signedIn));
  }
  var tokenCalls = callsTo(signedIn, "/auth/v1/token");
  if (tokenCalls.length !== 1) fail("sign-in did not send one token request");
  var tokenBody = parsed(tokenCalls[0]);
  if (tokenCalls[0].method !== "POST") fail("sign-in is not a POST");
  if (tokenCalls[0].url.indexOf("grant_type=password") === -1) fail("sign-in is not a password grant");
  if (keysOf(tokenBody) !== "email,password") fail("sign-in body is not email and password");
  if (!tokenBody || tokenBody.email !== email || tokenBody.password !== password) {
    fail("sign-in did not send email and password");
  }
  if (JSON.stringify(tokenBody).indexOf("should-not-be-sent") !== -1) fail("sign-in sent the username");
  var session = sessionFromTokenCall(tokenCalls[0]);
  if (!session) fail("sign-in did not return a session");
  if (session.id !== userId) fail("sign-in user id did not match the signup user");
  if (session.username !== username) fail("sign-in metadata did not keep the username");
  var signInProfiles = callsTo(signedIn, "/rest/v1/profiles");
  if (signInProfiles.length !== 1) fail("sign-in did not write the profile");
  assertProfileWrite(signInProfiles[0], session.id, username);
  if (signInProfiles[0].headers.Authorization !== "Bearer " + session.token) {
    fail("sign-in profile write did not use the sign-in bearer");
  }
  var tokenAt = signedIn.calls.indexOf(tokenCalls[0]);
  var profileAt = signedIn.calls.indexOf(signInProfiles[0]);
  if (!(tokenAt >= 0 && profileAt > tokenAt)) fail("profile write did not follow sign-in");
  var kept = storedSession(signedIn);
  if (!kept || kept.token !== session.token || kept.id !== session.id || kept.username !== username) {
    fail("page script did not store the sign-in session");
  }
  if (profileCountFor(userId) !== "1") fail("profile row missing after sign-in");
  return { signedIn: signedIn, session: session };
}

async function main() {
  var rejected = boot("sign-up", decoyFields({
    username: { value: "Bad-Name" },
    email: { value: "bad@example.com" },
    password: { value: "s3cret-pass" }
  }));
  submit(rejected);
  await waitSettled(rejected);
  if (rejected.calls.length !== 0) fail("username outside ^[a-z0-9_]{3,32}$ was sent");
  if (statusTextOf(rejected).indexOf("Username") === -1) fail("bad username was not refused on the page");
  console.log("username outside ^[a-z0-9_]{3,32}$: refused before the request");

  var userA = usernameOf("a");
  var userB = usernameOf("b");
  var emailA = userA + "@example.com";
  var emailB = userB + "@example.com";
  var passwordA = nodeCrypto.randomBytes(16).toString("hex");
  var passwordB = nodeCrypto.randomBytes(16).toString("hex");
  var newPassword = nodeCrypto.randomBytes(16).toString("hex");
  makeSecrets(userA, emailA, passwordA);

  var signupPage = await signUp(userA, emailA, passwordA);
  var signup = assertSignupHeld(signupPage, emailA, passwordA, userA);
  console.log("sign-up: no session until email confirmation");

  var confirmMessages = await waitMessages(emailA, 1);
  await followConfirmation(confirmMessages);
  if (profileCountFor(signup.userId) !== "0") fail("profile row was written before sign-in");

  var first = await assertSignedInProfile(emailA, passwordA, signup.userId, userA);
  console.log("sign-in after confirmation: session returned");
  console.log("profile write on sign-in: {id, username}");

  seedMailbox(signup.userId);
  console.log("mailbox ciphertext seeded in the database");
  console.log("device public key: 32-byte base64url");
  console.log("private key: not stored");

  var forgot = boot("forgot", decoyFields({ email: { value: emailA } }));
  submit(forgot);
  await waitSettled(forgot);
  forgot.calls.forEach(function (call) { assertShape(call, "forgot"); });
  var recover = callsTo(forgot, "/auth/v1/recover");
  if (recover.length !== 1) fail("forgot did not request one recovery email");
  if (recover[0].method !== "POST") fail("forgot is not a POST");
  var redirect = "";
  try { redirect = new URL(recover[0].url).searchParams.get("redirect_to") || ""; }
  catch (err) { redirect = ""; }
  if (!redirect.endsWith("/account/reset")) fail("recovery redirect does not end in /account/reset");
  if (new URL(redirect).pathname !== "/account/reset") fail("recovery redirect path is not /account/reset");
  var recoverBody = parsed(recover[0]);
  if (keysOf(recoverBody) !== "email" || !recoverBody || recoverBody.email !== emailA) {
    fail("forgot body is not the email");
  }
  if (recover[0].status < 200 || recover[0].status >= 300) fail("recovery request was refused");
  assertNoSecrets(
    String(recover[0].responseText || "") + "\n" + String(recover[0].responseHeaders || ""),
    "recovery response"
  );
  if (callsTo(forgot, "/auth/v1/user").length !== 0) fail("forgot changed a password");
  if (callsTo(forgot, "/rest/").length !== 0) fail("forgot read or wrote a table");
  console.log("forgot: recovery redirect ends in /account/reset");
  console.log("recovery response omits ciphertext, device public key, and mesh token");

  var landing = await recoveryLanding(emailA);
  if (!landing || !landing.hash || !landing.token) {
    fail("reset page reads the recovery session from the URL hash. The recovery email did not land on that session.");
  }
  console.log("recovery mail omits ciphertext, device public key, and mesh token");
  console.log("recovery redirect omits ciphertext, device public key, and mesh token");
  console.log("recovery email redirect ends in /account/reset");

  var resetPage = boot("reset", decoyFields({
    "new-password": { value: newPassword }
  }), landing.hash);
  var recovery = resetPage.document._ids.form._recovery || { token: "", type: "" };
  if (resetPage.location.hash) fail("reset page left the recovery session in the URL hash");
  if (!recovery.token || recovery.type !== "recovery" || recovery.token !== landing.token) {
    fail("reset page did not read the recovery session from the URL hash");
  }
  if (recovery.error) fail("reset page read an error instead of a recovery session");
  console.log("reset page read the recovery session from the URL hash");
  submit(resetPage);
  await waitSettled(resetPage);
  resetPage.calls.forEach(function (call) { assertShape(call, "reset"); });
  var userCalls = callsTo(resetPage, "/auth/v1/user");
  if (userCalls.length !== 1) fail("reset page did not send one password update");
  if (userCalls[0].method !== "PUT") fail("reset page password update is not a PUT");
  var resetBody = parsed(userCalls[0]);
  if (keysOf(resetBody) !== "password" || !resetBody || resetBody.password !== newPassword) {
    fail("reset page did not submit the new-password field");
  }
  if (userCalls[0].headers.Authorization !== "Bearer " + recovery.token) {
    fail("reset page did not use the recovery session from the URL hash");
  }
  if (userCalls[0].status < 200 || userCalls[0].status >= 300) fail("reset was refused " + userCalls[0].status);
  if (resetPage.document._ids.status.className.indexOf("error") !== -1) fail("reset failed: " + statusTextOf(resetPage));
  if (resetPage.assigned.join(",") !== "/account/sign-in?reset=1") fail("reset page did not return to sign in");
  if (callsTo(resetPage, "/rest/").length !== 0) fail("reset read or wrote a table");
  assertNoSecrets(
    String(userCalls[0].responseText || "") + "\n" + String(userCalls[0].responseHeaders || ""),
    "reset response"
  );
  if (String(userCalls[0].responseText || "").indexOf("ciphertext") !== -1) {
    fail("reset response mentions ciphertext");
  }
  console.log("reset: new password submitted from the new-password field");
  console.log("reset response omits ciphertext, device public key, and mesh token");

  var signedNew = await assertSignedInProfile(emailA, newPassword, first.session.id, userA);
  console.log("sign-in with the new password: session returned");
  console.log("profile write on sign-in: {id, username}");

  var signedOld = await signIn(emailA, passwordA);
  var oldTokenCalls = callsTo(signedOld, "/auth/v1/token");
  if (oldTokenCalls.length !== 1) fail("sign-in with the old password was not sent");
  if (oldTokenCalls[0].status >= 200 && oldTokenCalls[0].status < 300) fail("sign-in with the old password was accepted");
  if (sessionFromTokenCall(oldTokenCalls[0])) fail("sign-in with the old password returned a session");
  if (storedSession(signedOld)) fail("sign-in with the old password stored a session");
  if (signedOld.assigned.length !== 0) fail("sign-in with the old password continued into the account");
  if (callsTo(signedOld, "/rest/v1/profiles").length !== 0) fail("sign-in with the old password wrote a profile");
  if (signedOld.document._ids.status.className.indexOf("error") === -1) {
    fail("sign-in with the old password was not refused on the page");
  }
  console.log("sign-in with the old password: no session");
  console.log("old password failure: no profile write");

  var ownBox = await selectRows(signedNew.signedIn, "/rest/v1/mailbox?select=ciphertext");
  if (ownBox.url.indexOf(mail) !== -1 || ownBox.url.indexOf("/api/v1/message") !== -1) {
    fail("owner ciphertext read used the email");
  }
  if (ownBox.url.indexOf("/rest/v1/mailbox") === -1) fail("owner ciphertext read was not the database");
  if (!ownBox.rows.some(function (row) { return row.ciphertext === marker; })) {
    fail("owner could not read their ciphertext from the database");
  }
  var ownKey = await selectRows(signedNew.signedIn, "/rest/v1/devices?select=public_key");
  if (!ownKey.rows.some(function (row) { return row.public_key === publicKey; })) {
    fail("owner could not read their device public key from the database");
  }
  console.log("owner ciphertext read: database, not the email");

  var secondPage = await signUp(userB, emailB, passwordB);
  var secondSignup = assertSignupHeld(secondPage, emailB, passwordB, userB);
  var secondMessages = await waitMessages(emailB, 1);
  await followConfirmation(secondMessages);
  if (profileCountFor(secondSignup.userId) !== "0") fail("second profile row was written before sign-in");
  var second = await assertSignedInProfile(emailB, passwordB, secondSignup.userId, userB);
  if (second.session.username !== userB) fail("second sign-in metadata did not keep the username");

  function rejectLeak(result, label) {
    if (String(result.text || "").indexOf(marker) !== -1) fail(label + " returned mailbox ciphertext");
    if (String(result.text || "").indexOf(publicKey) !== -1) fail(label + " returned the device public key");
    if (String(result.text || "").indexOf(SENTINEL_TOKEN) !== -1) fail(label + " returned a mesh token");
  }

  var seenB = await selectRows(second.signedIn, "/rest/v1/profiles?select=id,username");
  rejectLeak(seenB, "second user profile select");
  var seenIds = seenB.rows.map(function (row) { return row.id; });
  if (seenIds.indexOf(first.session.id) !== -1 || seenIds.join(",") !== second.session.id) {
    fail("second user can select the first user's profile");
  }
  var filtered = await selectRows(
    second.signedIn,
    "/rest/v1/profiles?id=eq." + encodeURIComponent(first.session.id) + "&select=id,username"
  );
  rejectLeak(filtered, "second user profile select");
  if (filtered.rows.length !== 0) fail("second user can select the first profile by id");

  var devicesFiltered = await selectRows(
    second.signedIn,
    "/rest/v1/devices?user_id=eq." + encodeURIComponent(first.session.id) + "&select=id,user_id,public_key"
  );
  rejectLeak(devicesFiltered, "second user device select");
  if (devicesFiltered.rows.length !== 0) fail("second user can select the first user's device");
  var devicesOpen = await selectRows(second.signedIn, "/rest/v1/devices?select=id,user_id,public_key");
  rejectLeak(devicesOpen, "second user device select");
  if (devicesOpen.rows.some(function (row) { return row.user_id === first.session.id || row.public_key === publicKey; })) {
    fail("second user can select the first user's device");
  }

  var boxFiltered = await selectRows(
    second.signedIn,
    "/rest/v1/mailbox?user_id=eq." + encodeURIComponent(first.session.id) + "&select=id,ciphertext"
  );
  rejectLeak(boxFiltered, "second user mailbox select");
  if (boxFiltered.rows.length !== 0) fail("second user can select the first user's mailbox");
  var boxOpen = await selectRows(second.signedIn, "/rest/v1/mailbox?select=id,ciphertext");
  rejectLeak(boxOpen, "second user mailbox select");
  if (boxOpen.rows.some(function (row) { return row.ciphertext === marker; })) {
    fail("second user can select the first user's mailbox");
  }
  console.log("second user: cannot select the first user's profile, device, or mailbox");

  allCalls.forEach(function (call) {
    assertShape(call, "account page");
    var raw = JSON.stringify(call.headers || {}) + "\n" + String(call.body || "") + "\n" + call.url;
    if (raw.indexOf(marker) !== -1) fail("page request carries mailbox ciphertext");
    if (raw.indexOf(publicKey) !== -1) fail("page request carries the device public key");
    if (raw.indexOf(privateKey) !== -1) fail("page request carries a private key");
  });
  console.log("requests to port 8899: none");
  console.log("requests carrying a mesh token: none");
  console.log("service role on page requests: none");

  try {
    var meshAfter = fs.statSync(meshDir).mtimeMs;
    if (meshBefore == null) fail("~/.mesh was created during the proof");
    if (meshAfter !== meshBefore) fail("~/.mesh was written during the proof");
  } catch (err) {
    if (meshBefore != null) fail("~/.mesh disappeared during the proof");
  }
  console.log("~/.mesh write: none");
  console.log("recovery-mail-leak: OK");
}

main().catch(function (err) {
  fail(err && err.stack ? err.stack : err);
});
NODE

# Explicit restore before exit so the committed file stays confirmations-off
# even if the EXIT trap later races with another stop/start.
restore_config
if grep -q 'enable_confirmations = true' "$CONFIG"; then
  # Only fail if the email section still shows true; sms may also have the key.
  if awk '
    /^\[/{sec=$0}
    sec=="[auth.email]" && $0 ~ /^enable_confirmations[[:space:]]*=[[:space:]]*true/ { found=1 }
    END { exit found?0:1 }
  ' "$CONFIG"; then
    echo "FAIL: email confirmations were left enabled in config.toml"
    exit 1
  fi
fi
echo "email confirmations restored to off"
