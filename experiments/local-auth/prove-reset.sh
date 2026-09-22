#!/bin/sh
# Drive web/account/account.js forgot and reset against a Supabase stack
# that is already running on this machine. The reset page reads the recovery
# session from the URL hash and submits the field name="new-password".
# The page script keeps its own fetch. The anon key is read from
# `supabase status` at runtime and is never written into the repo.
# This is not a scripts/check-*.sh file: check-all.sh runs every check,
# and those CI machines do not have this stack.
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
SQL="$ROOT/supabase/account/001_identity.sql"
JS="$ROOT/web/account/account.js"

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

node - "$STATUS" "$SQL" "$JS" << 'NODE'
"use strict";

var fs = require("fs");
var vm = require("vm");
var http = require("http");
var https = require("https");
var nodeCrypto = require("crypto");
var child = require("child_process");

var statusPath = process.argv[2];
var sqlPath = process.argv[3];
var jsPath = process.argv[4];
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
  if (key === "API_URL" || key === "ANON_KEY" || key === "DB_URL" || key === "MAILPIT_URL") {
    env[key] = value;
  }
});

var hidden = [];

function fail(message) {
  console.log("FAIL: " + redact(message));
  process.exit(1);
}

function redact(text) {
  var out = String(text || "")
    .replace(/postgres(?:ql)?:\/\/\S+/gi, "postgresql://REDACTED")
    .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, "REDACTED_JWT")
    .replace(/(apikey|authorization|access_token|refresh_token|bearer)\s*[:=]\s*\S+/gi, "$1=REDACTED");
  hidden.forEach(function (secret) {
    if (secret && secret.length >= 8) out = out.split(secret).join("REDACTED");
  });
  return out;
}

var api = String(env.API_URL || "").replace(/\/+$/, "");
var anon = String(env.ANON_KEY || "");
var db = String(env.DB_URL || "");
var mail = String(env.MAILPIT_URL || "").replace(/\/+$/, "");
if (!api || !anon || !db || !mail) {
  fail("local status did not include API_URL, ANON_KEY, DB_URL, and MAILPIT_URL");
}
var blob = api + " " + db + " " + mail;
if (blob.indexOf("supabase.co") !== -1 || blob.indexOf("zmisjteztezaqfflwbgf") !== -1) {
  fail("refusing a non-local stack");
}
if (!/^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(api)) fail("API_URL is not a local loopback address");
if (!/^https?:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(mail)) fail("MAILPIT_URL is not a local loopback address");

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

async function selectProfiles(page, query) {
  var session = storedSession(page);
  if (!session || !session.token) fail("page script did not keep a sign-in session");
  var response = await page.fetch(api + "/rest/v1/profiles?" + query, {
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
    fail("profile select failed " + response.status);
  }
  return rows;
}

function usernameOf(prefix) {
  var name = prefix + nodeCrypto.randomBytes(4).toString("hex");
  if (!/^[a-z0-9_]{3,32}$/.test(name)) fail("generated username does not match the profile pattern");
  return name;
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

function assertLoopback(url, label) {
  var parsed;
  try { parsed = new URL(url); } catch (err) { fail(label + " URL was not absolute"); }
  if (parsed.hostname !== "127.0.0.1" && parsed.hostname !== "localhost") fail(label + " left the local stack");
  if (parsed.port === "8899" || url.indexOf(":8899") !== -1) fail(label + " called port 8899");
  if (url.indexOf("supabase.co") !== -1 || url.indexOf("zmisjteztezaqfflwbgf") !== -1) fail(label + " left the local stack");
  return parsed;
}

function requestOnce(url) {
  return new Promise(function (resolve, reject) {
    var parsed = assertLoopback(url, "recovery redirect");
    var lib = parsed.protocol === "https:" ? https : http;
    var req = lib.get({
      hostname: parsed.hostname,
      port: parsed.port,
      path: parsed.pathname + parsed.search,
      headers: { Accept: "text/html" }
    }, function (res) {
      var chunks = [];
      res.on("data", function (chunk) { chunks.push(chunk); });
      res.on("end", function () {
        resolve({
          status: res.statusCode || 0,
          location: res.headers.location || "",
          body: Buffer.concat(chunks).toString("utf8")
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
  var parsed = assertLoopback(url, "recovery email redirect");
  var bare = url.split("#")[0];
  if (!bare.endsWith("/account/reset") || parsed.pathname !== "/account/reset") {
    fail("recovery email redirect does not end in /account/reset");
  }
  var hash = new URLSearchParams((parsed.hash || "").replace(/^#/, ""));
  var token = hash.get("access_token") || "";
  var type = hash.get("type") || "";
  if (token && type === "recovery" && !hash.get("error") && !hash.get("error_description")) {
    return { hash: parsed.hash, token: token };
  }
  if (parsed.searchParams.get("code") || (token && type !== "recovery")) {
    fail("reset page reads the recovery session from the URL hash (access_token with type=recovery). This redirect does not provide that session, so the page cannot set a password without a code change.");
  }
  return null;
}

async function chase(startUrl, marker) {
  var current = startUrl;
  var followed = false;
  for (var hop = 0; hop < 4; hop++) {
    var parsedNow = assertLoopback(current, "recovery redirect");
    if (parsedNow.pathname === "/account/reset") {
      if (!followed && !parsedNow.hash) return null;
      return judgeLanding(current);
    }
    var res = await requestOnce(current);
    var redirectBlob = String(res.location || "") + "\n" + String(res.body || "");
    if (redirectBlob.indexOf(marker) !== -1) fail("reset redirect returned mailbox plaintext");
    if (!(res.status >= 300 && res.status < 400 && res.location)) return null;
    current = new URL(res.location, current).href;
    followed = true;
  }
  fail("recovery email redirect did not end in /account/reset");
}

async function recoveryLanding(email, marker) {
  var deadline = Date.now() + 20000;
  var tried = Object.create(null);
  while (Date.now() < deadline) {
    var listingRes = await fetch(mail + "/api/v1/messages");
    var listing = await listingRes.json();
    var messages = listing.messages || [];
    for (var i = 0; i < messages.length; i++) {
      var recipients = (messages[i].To || []).map(function (person) {
        return String(person.Address || "").toLowerCase();
      });
      if (recipients.indexOf(email.toLowerCase()) === -1) continue;
      var messageRes = await fetch(mail + "/api/v1/message/" + messages[i].ID);
      var message = await messageRes.json();
      var text = decodeMail(String(message.HTML || "") + "\n" + String(message.Text || ""));
      if (text.indexOf(marker) !== -1) fail("recovery mail returned mailbox plaintext");
      if (text.indexOf("/account/reset") === -1 && text.indexOf("%2Faccount%2Freset") === -1) continue;
      var urls = text.match(/https?:\/\/[^\s"'<>]+/g) || [];
      for (var u = 0; u < urls.length; u++) {
        var url = urls[u].replace(/[),.;]+$/, "");
        if (tried[url]) continue;
        tried[url] = true;
        var parsed = assertLoopback(url, "recovery mail");
        if (parsed.pathname.indexOf("/verify") === -1) continue;
        var landed = await chase(url, marker);
        if (landed && landed.token) return landed;
      }
    }
    await delay(500);
  }
  fail("recovery email redirect did not end in /account/reset");
}

async function seedMailbox(page, userId, marker) {
  var session = storedSession(page);
  if (!session || session.id !== userId) fail("mailbox seed has no signed-in session");
  async function call(method, path, body) {
    var headers = {
      apikey: anon,
      Authorization: "Bearer " + session.token,
      Accept: "application/json"
    };
    var init = { method: method, headers: headers };
    if (body != null) {
      headers["Content-Type"] = "application/json";
      headers.Prefer = "return=representation";
      init.body = JSON.stringify(body);
    }
    var recorded = { url: api + path, method: method, headers: headers, body: init.body };
    assertShape(recorded, "mailbox seed");
    var response = await fetch(api + path, init);
    var text = await response.text();
    if (response.status < 200 || response.status >= 300) fail("mailbox seed failed " + response.status);
    return text ? JSON.parse(text) : null;
  }
  var devices = await call("POST", "/rest/v1/devices", {
    user_id: userId,
    label: "wrist",
    platform: "web",
    public_key: "pub-" + userId
  });
  if (!Array.isArray(devices) || !devices[0] || !devices[0].id) fail("mailbox seed did not create a device");
  var deviceId = devices[0].id;
  var rows = await call("POST", "/rest/v1/mailbox", {
    user_id: userId,
    recipient_device_id: deviceId,
    sender_device_id: deviceId,
    ciphertext: marker,
    expires_at: "2030-01-01T00:00:00Z"
  });
  if (!Array.isArray(rows) || !rows[0] || rows[0].ciphertext !== marker) fail("mailbox seed was not stored");
  var own = await call("GET", "/rest/v1/mailbox?select=ciphertext", null);
  var saw = Array.isArray(own) && own.some(function (row) { return row && row.ciphertext === marker; });
  if (!saw) fail("owner could not read mailbox plaintext");
}

function containsPlaintext(text, marker) {
  return String(text || "").indexOf(marker) !== -1;
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
  var marker = "sealed-" + nodeCrypto.randomBytes(16).toString("hex");
  hidden.push(passwordA, passwordB, newPassword, marker);

  var signup = await signUp(userA, emailA, passwordA);
  var signupCalls = callsTo(signup, "/auth/v1/signup");
  if (signupCalls.length !== 1) fail("sign-up did not send one signup request");
  var signupBody = parsed(signupCalls[0]);
  if (signupCalls[0].method !== "POST") fail("sign-up is not a POST");
  if (keysOf(signupBody) !== "data,email,password") fail("sign-up body is not username, email, and password");
  if (!signupBody || signupBody.email !== emailA || signupBody.password !== passwordA) {
    fail("sign-up did not send email and password");
  }
  if (keysOf(signupBody.data) !== "username" || signupBody.data.username !== userA) {
    fail("sign-up did not send username");
  }
  if (signupCalls[0].status < 200 || signupCalls[0].status >= 300) fail("sign-up was refused");
  if (signup.document._ids.status.className.indexOf("error") !== -1) fail("sign-up failed: " + statusTextOf(signup));
  console.log("sign-up: sent username, email, and password");

  var signedIn = await signIn(emailA, passwordA);
  if (signedIn.document._ids.status.className.indexOf("error") !== -1) fail("sign-in failed: " + statusTextOf(signedIn));
  var tokenCalls = callsTo(signedIn, "/auth/v1/token");
  if (tokenCalls.length !== 1) fail("sign-in did not send one token request");
  var tokenBody = parsed(tokenCalls[0]);
  if (tokenCalls[0].method !== "POST") fail("sign-in is not a POST");
  if (tokenCalls[0].url.indexOf("grant_type=password") === -1) fail("sign-in is not a password grant");
  if (keysOf(tokenBody) !== "email,password") fail("sign-in body is not email and password");
  if (!tokenBody || tokenBody.email !== emailA || tokenBody.password !== passwordA) {
    fail("sign-in did not send email and password");
  }
  var sessionA = sessionFromTokenCall(tokenCalls[0]);
  if (!sessionA) fail("sign-in did not return a session");
  if (sessionA.username !== userA) fail("sign-in metadata did not keep the username");
  var signInProfiles = callsTo(signedIn, "/rest/v1/profiles");
  if (signInProfiles.length !== 1) fail("sign-in did not write the profile");
  assertProfileWrite(signInProfiles[0], sessionA.id, userA);
  var kept = storedSession(signedIn);
  if (!kept || kept.token !== sessionA.token || kept.id !== sessionA.id || kept.username !== userA) {
    fail("page script did not store the sign-in session");
  }
  console.log("profile write: {id, username}");

  var signupB = await signUp(userB, emailB, passwordB);
  if (callsTo(signupB, "/auth/v1/signup").length !== 1) fail("second sign-up did not send one signup request");
  var signedB = await signIn(emailB, passwordB);
  if (signedB.document._ids.status.className.indexOf("error") !== -1) fail("second sign-in failed: " + statusTextOf(signedB));
  var tokenB = sessionFromTokenCall(callsTo(signedB, "/auth/v1/token")[0] || {});
  if (!tokenB || tokenB.username !== userB) fail("second sign-in did not return that user");
  var profileB = callsTo(signedB, "/rest/v1/profiles");
  if (profileB.length !== 1) fail("second sign-in did not write a profile");
  assertProfileWrite(profileB[0], tokenB.id, userB);

  async function assertIsolated() {
    var seenB = await selectProfiles(signedB, "select=id,username");
    var seenIds = seenB.map(function (row) { return row.id; });
    if (seenIds.indexOf(sessionA.id) !== -1 || seenIds.join(",") !== tokenB.id) {
      fail("second user can select the first user's profile");
    }
    var filtered = await selectProfiles(signedB, "id=eq." + encodeURIComponent(sessionA.id) + "&select=id,username");
    if (filtered.length !== 0) fail("second user can select the first profile by id");
  }
  await assertIsolated();
  console.log("second user: cannot select the first user's profile");

  await seedMailbox(signedIn, sessionA.id, marker);

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
  if (containsPlaintext(recover[0].responseText, marker)) fail("recovery response returned mailbox plaintext");
  if (callsTo(forgot, "/auth/v1/user").length !== 0) fail("forgot changed a password");
  if (callsTo(forgot, "/rest/").length !== 0) fail("forgot read or wrote a table");
  console.log("forgot: recovery redirect ends in /account/reset");
  console.log("recovery response contains mailbox plaintext: no");

  var landing = await recoveryLanding(emailA, marker);
  if (!landing || !landing.hash || !landing.token) {
    fail("reset page reads the recovery session from the URL hash. The recovery email did not land on that session, so the page cannot set a password without a code change.");
  }
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
  if (containsPlaintext(userCalls[0].responseText, marker) || String(userCalls[0].responseText || "").indexOf("ciphertext") !== -1) {
    fail("reset returned mailbox plaintext");
  }
  console.log("reset: new password submitted from the new-password field");
  console.log("reset response contains mailbox plaintext: no");

  var signedNew = await signIn(emailA, newPassword);
  if (signedNew.document._ids.status.className.indexOf("error") !== -1) {
    fail("sign-in with the new password failed: " + statusTextOf(signedNew));
  }
  var newTokenCalls = callsTo(signedNew, "/auth/v1/token");
  if (newTokenCalls.length !== 1) fail("sign-in with the new password did not send one token request");
  var newSession = sessionFromTokenCall(newTokenCalls[0]);
  if (!newSession) fail("sign-in with the new password did not return a session");
  if (newSession.id !== sessionA.id || newSession.username !== userA) {
    fail("sign-in with the new password did not return the same account");
  }
  var newProfiles = callsTo(signedNew, "/rest/v1/profiles");
  if (newProfiles.length !== 1) fail("sign-in with the new password did not write the profile");
  assertProfileWrite(newProfiles[0], sessionA.id, userA);
  var keptNew = storedSession(signedNew);
  if (!keptNew || keptNew.id !== sessionA.id || keptNew.username !== userA || keptNew.token !== newSession.token) {
    fail("page script did not store the new sign-in session");
  }
  console.log("sign-in with the new password: session returned");
  console.log("profile write: {id, username}");

  var signedOld = await signIn(emailA, passwordA);
  var oldTokenCalls = callsTo(signedOld, "/auth/v1/token");
  if (oldTokenCalls.length !== 1) fail("sign-in with the old password was not sent");
  if (oldTokenCalls[0].status >= 200 && oldTokenCalls[0].status < 300) fail("sign-in with the old password was accepted");
  if (sessionFromTokenCall(oldTokenCalls[0])) fail("sign-in with the old password returned a session");
  if (storedSession(signedOld)) fail("sign-in with the old password stored a session");
  if (signedOld.assigned.length !== 0) fail("sign-in with the old password continued into the account");
  if (callsTo(signedOld, "/rest/v1/profiles").length !== 0) fail("sign-in with the old password wrote a profile");
  if (signedOld.document._ids.status.className.indexOf("error") === -1) fail("sign-in with the old password was not refused on the page");
  console.log("sign-in with the old password: no session");

  await assertIsolated();
  console.log("second user: cannot select the first user's profile");

  allCalls.forEach(function (call) { assertShape(call, "account page"); });
  var profileWrites = allCalls.filter(function (call) {
    return call.method === "POST" && call.url.indexOf("/rest/v1/profiles") !== -1;
  });
  if (profileWrites.length === 0) fail("no profile write was observed");
  profileWrites.forEach(function (call) {
    var body = parsed(call);
    if (keysOf(body) !== "id,username") fail("profile write is not {id, username} only");
  });
  console.log("requests to port 8899: none");
  console.log("requests carrying a mesh token: none");
  console.log("requests carrying a service role: none");
  console.log("local-password-reset: OK");
}

main().catch(function (err) {
  fail(err && err.stack ? err.stack : err);
});
NODE
