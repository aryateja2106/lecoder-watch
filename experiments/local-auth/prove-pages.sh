#!/bin/sh
# Drive web/account/account.js against a Supabase stack that is already
# running on this machine. The page script keeps its own fetch; this file
# only supplies a fake document and points window.MESH_ACCOUNT at the local
# API URL and anon key from `supabase status`. Those values are never written
# into the repo. This is not a scripts/check-*.sh file: check-all.sh runs
# every check, and those CI machines do not have this stack.
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
    .replace(/(apikey|authorization|access_token|refresh_token|bearer)\s*[:=]\s*\S+/gi, "$1=REDACTED");
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

function boot(pageName, fields) {
  var calls = [];
  var assigned = [];
  var document = makeDocument(pageName);
  document._ids.form.elements = fields;
  var location = {
    origin: ORIGIN,
    hash: "",
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

// account.js writes {id, username} and has no profile-select control.
// The select uses the session that script stored and the fetch it was given.
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
  if (statusTextOf(page).length && page.document._ids.status.className.indexOf("error") !== -1) {
    fail("sign-in failed: " + statusTextOf(page));
  }
  return page;
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

  var signupSession = sessionFromTokenCall(signupCalls[0]);
  var signupProfiles = callsTo(signup, "/rest/v1/profiles");
  if (!signupSession) {
    if (signupProfiles.length !== 0) fail("profile write did not wait for sign-in");
    if (callsTo(signup, "/auth/v1/token").length !== 0) fail("sign-up signed in when there was no session");
    if (statusTextOf(signup).indexOf("sign in") === -1) fail("sign-up did not say the username is saved on sign-in");
    console.log("email confirmation: no session yet; profile write waited until sign-in");
  } else {
    if (signupProfiles.length !== 1) fail("sign-up returned a session but did not write the profile");
    assertProfileWrite(signupProfiles[0], signupSession.id, userA);
    if (signupProfiles[0].headers.Authorization !== "Bearer " + signupSession.token) {
      fail("sign-up profile write did not use the signup session");
    }
    console.log("sign-up returned a session, so the profile write did not wait");
    console.log("profile write on sign-up: {id, username}");
  }

  var signedIn = await signIn(emailA, passwordA);
  var tokenCalls = callsTo(signedIn, "/auth/v1/token");
  if (tokenCalls.length !== 1) fail("sign-in did not send one token request");
  var tokenBody = parsed(tokenCalls[0]);
  if (tokenCalls[0].method !== "POST") fail("sign-in is not a POST");
  if (tokenCalls[0].url.indexOf("grant_type=password") === -1) fail("sign-in is not a password grant");
  if (keysOf(tokenBody) !== "email,password") fail("sign-in body is not email and password");
  if (!tokenBody || tokenBody.email !== emailA || tokenBody.password !== passwordA) {
    fail("sign-in did not send email and password");
  }
  if (JSON.stringify(tokenBody).indexOf("should-not-be-sent") !== -1) fail("sign-in sent the username");
  var sessionA = sessionFromTokenCall(tokenCalls[0]);
  if (!sessionA) fail("sign-in did not return a session");
  if (sessionA.username !== userA) fail("sign-in metadata did not keep the username");
  var signInProfiles = callsTo(signedIn, "/rest/v1/profiles");
  if (signInProfiles.length !== 1) fail("sign-in did not write the profile");
  assertProfileWrite(signInProfiles[0], sessionA.id, userA);
  if (signInProfiles[0].headers.Authorization !== "Bearer " + sessionA.token) {
    fail("sign-in profile write did not use the sign-in bearer");
  }
  var tokenAt = signedIn.calls.indexOf(tokenCalls[0]);
  var profileAt = signedIn.calls.indexOf(signInProfiles[0]);
  if (!(tokenAt >= 0 && profileAt > tokenAt)) fail("profile write did not follow sign-in");
  var kept = storedSession(signedIn);
  if (!kept || kept.token !== sessionA.token || kept.id !== sessionA.id || kept.username !== userA) {
    fail("page script did not store the sign-in session");
  }
  console.log("sign-in: email and password");
  console.log("profile write: {id, username}");

  var ownRows = await selectProfiles(signedIn, "id=eq." + encodeURIComponent(sessionA.id) + "&select=id,username");
  if (ownRows.length !== 1 || ownRows[0].id !== sessionA.id || ownRows[0].username !== userA) {
    fail("owner could not select their own profile");
  }
  if (keysOf(ownRows[0]) !== "id,username") fail("profile select was not {id, username}");

  var signupB = await signUp(userB, emailB, passwordB);
  if (callsTo(signupB, "/auth/v1/signup").length !== 1) fail("second sign-up did not send one signup request");
  var signedB = await signIn(emailB, passwordB);
  var tokenB = sessionFromTokenCall(callsTo(signedB, "/auth/v1/token")[0] || {});
  if (!tokenB || tokenB.username !== userB) fail("second sign-in did not return that user");
  var profileB = callsTo(signedB, "/rest/v1/profiles");
  if (profileB.length !== 1) fail("second sign-in did not write a profile");
  assertProfileWrite(profileB[0], tokenB.id, userB);
  var keptB = storedSession(signedB);
  if (!keptB || keptB.id !== tokenB.id) fail("second page script did not store its session");

  var seenB = await selectProfiles(signedB, "select=id,username");
  var seenIds = seenB.map(function (row) { return row.id; });
  if (seenIds.indexOf(sessionA.id) !== -1 || seenIds.join(",") !== tokenB.id) {
    fail("second user can select the first user's profile");
  }
  var filtered = await selectProfiles(signedB, "id=eq." + encodeURIComponent(sessionA.id) + "&select=id,username");
  if (filtered.length !== 0) fail("second user can select the first profile by id");
  console.log("second user: cannot select the first user's profile");

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
  if (callsTo(forgot, "/auth/v1/user").length !== 0) fail("forgot changed a password");
  if (callsTo(forgot, "/rest/").length !== 0) fail("forgot read or wrote a table");

  var deadline = Date.now() + 20000;
  var sawReset = false;
  while (Date.now() < deadline && !sawReset) {
    var listingRes = await fetch(mail + "/api/v1/messages");
    var listing = await listingRes.json();
    var messages = listing.messages || [];
    for (var i = 0; i < messages.length; i++) {
      var recipients = (messages[i].To || []).map(function (person) {
        return String(person.Address || "").toLowerCase();
      });
      if (recipients.indexOf(emailA.toLowerCase()) === -1) continue;
      var messageRes = await fetch(mail + "/api/v1/message/" + messages[i].ID);
      var message = await messageRes.json();
      var text = String(message.HTML || "") + "\n" + String(message.Text || "");
      if (text.indexOf("/account/reset") !== -1 || text.indexOf("%2Faccount%2Freset") !== -1) sawReset = true;
    }
    if (!sawReset) await delay(500);
  }
  if (!sawReset) fail("recovery email redirect did not end in /account/reset");
  console.log("forgot: recovery redirect ends in /account/reset");

  allCalls.forEach(function (call) { assertShape(call, "account page"); });
  console.log("requests to port 8899: none");
  console.log("requests carrying a mesh token: none");
  console.log("account-pages-local-auth: OK");
}

main().catch(function (err) {
  fail(err && err.stack ? err.stack : err);
});
NODE
