#!/bin/sh
# check-account-handlers.sh — call the website account handlers with a fake
# Node response and a stubbed fetch. No Supabase host, no live network,
# and no env values in the output.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CFG="$ROOT/web/api/account-config.js"
DEL="$ROOT/web/api/delete-account.js"

if [ ! -f "$CFG" ] || [ ! -f "$DEL" ]; then
  echo "FAIL: check-account-handlers.sh: account handler is missing"
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: check-account-handlers.sh: node is required"
  exit 1
fi

# Drop deploy credentials before Node starts so a developer shell cannot
# leak into the handlers or into a failure line.
env -u SUPABASE_URL -u SUPABASE_ANON_KEY -u SUPABASE_SERVICE_ROLE_KEY \
  node - "$CFG" "$DEL" << 'NODE'
"use strict";

var fs = require("fs");

var pathCfg = process.argv[2];
var pathDel = process.argv[3];
var failures = 0;
var print = console.log.bind(console);

var io = {
  armed: false,
  logged: false,
  log: console.log,
  info: console.info,
  warn: console.warn,
  error: console.error,
  debug: console.debug,
  stdout: process.stdout.write.bind(process.stdout),
  stderr: process.stderr.write.bind(process.stderr)
};

function bad(msg) {
  failures += 1;
  print("FAIL: check-account-handlers.sh: " + msg);
}

function armQuiet() {
  io.logged = false;
  io.armed = true;
  ["log", "info", "warn", "error", "debug"].forEach(function (name) {
    console[name] = function () { io.logged = true; };
  });
  process.stdout.write = function () { io.logged = true; return true; };
  process.stderr.write = function () { io.logged = true; return true; };
}

function disarmQuiet() {
  if (!io.armed) return;
  console.log = io.log;
  console.info = io.info;
  console.warn = io.warn;
  console.error = io.error;
  console.debug = io.debug;
  process.stdout.write = io.stdout;
  process.stderr.write = io.stderr;
  io.armed = false;
}

var URL = "https://account.stub.test";
var ANON = "anon-key-public";
var SERVICE = "service-role-secret";
var BEARER = "session-bearer-stub";
var USER_ID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
var MESH_TOKEN = "mesh-token-sentinel";
var MACHINE = "http://machine.local:8899";

var calls = [];

function fakeHttp(status, payload) {
  return {
    ok: status >= 200 && status < 300,
    status: status,
    json: function () { return Promise.resolve(payload); },
    arrayBuffer: function () { return Promise.resolve(new ArrayBuffer(0)); },
    text: function () { return Promise.resolve(JSON.stringify(payload)); }
  };
}

function installFetch(mode) {
  calls = [];
  function stub(url, opts) {
    var call = {
      url: String(url),
      method: opts && opts.method ? String(opts.method) : "GET",
      headers: opts && opts.headers ? opts.headers : {},
      redirect: opts ? opts.redirect : undefined
    };
    calls.push(call);
    if (mode === "throw") return Promise.reject(new Error("stub-verify-failed"));
    if (mode === "user-fail") return Promise.resolve(fakeHttp(401, {}));
    if (mode === "bad-id") return Promise.resolve(fakeHttp(200, { id: "not-a-uuid" }));
    if (mode === "missing-id") return Promise.resolve(fakeHttp(200, {}));
    if (mode === "ok") {
      if (call.method === "DELETE") return Promise.resolve(fakeHttp(200, {}));
      return Promise.resolve(fakeHttp(200, { id: USER_ID }));
    }
    return Promise.resolve(fakeHttp(599, {}));
  }
  global.fetch = stub;
  globalThis.fetch = stub;
}

function fakeRes() {
  return {
    statusCode: 0,
    headers: {},
    body: "",
    setHeader: function (name, value) {
      this.headers[String(name).toLowerCase()] = String(value);
    },
    end: function (chunk) {
      this.body = chunk == null ? "" : String(chunk);
    }
  };
}

function clearEnv() {
  delete process.env.SUPABASE_URL;
  delete process.env.SUPABASE_ANON_KEY;
  delete process.env.SUPABASE_SERVICE_ROLE_KEY;
  delete process.env.MESHD_TOKEN;
  delete process.env.MESH_TOKEN;
  delete process.env.MESH_HOST;
}

function setEnv(url, anon, service) {
  clearEnv();
  if (url !== undefined) process.env.SUPABASE_URL = url;
  if (anon !== undefined) process.env.SUPABASE_ANON_KEY = anon;
  if (service !== undefined) process.env.SUPABASE_SERVICE_ROLE_KEY = service;
  process.env.MESHD_TOKEN = MESH_TOKEN;
  process.env.MESH_TOKEN = MESH_TOKEN;
  process.env.MESH_HOST = MACHINE;
}

function parsed(res) {
  try { return JSON.parse(res.body); }
  catch (err) { return null; }
}

function cache(res, label) {
  if (res.headers["cache-control"] !== "no-store") bad(label + " cache");
}

function bodyHas(res, value) {
  if (typeof value !== "string" || value.trim() === "") return false;
  var body = String(res.body);
  return body.indexOf(value) !== -1 || body.indexOf(value.trim()) !== -1;
}

function responseHas(res, value) {
  if (typeof value !== "string" || value.trim() === "") return false;
  var blob = String(res.body);
  Object.keys(res.headers).forEach(function (key) {
    blob += "\n" + res.headers[key];
  });
  return blob.indexOf(value) !== -1 || blob.indexOf(value.trim()) !== -1;
}

function callCarries(call, secret) {
  if (!secret) return false;
  var blob = call.method + "\n" + call.url;
  var headers = call.headers || {};
  Object.keys(headers).forEach(function (key) {
    blob += "\n" + key + ": " + headers[key];
  });
  return blob.indexOf(secret) !== -1;
}

function assertNoMachine(list) {
  list.forEach(function (call) {
    var url = String(call.url);
    if (url.indexOf("8899") !== -1) bad("handler requested port 8899");
    if (url.indexOf("machine.local") !== -1) bad("handler requested a machine");
    if (callCarries(call, MESH_TOKEN)) bad("handler sent a mesh token");
    if (url.indexOf("https://account.stub.test/") !== 0) bad("handler requested an unexpected host");
  });
}

function assertNoSecrets(res, label) {
  if (bodyHas(res, SERVICE) || responseHas(res, SERVICE)) bad(label + " echoed the service role");
  if (bodyHas(res, BEARER) || responseHas(res, BEARER)) bad(label + " echoed the bearer");
  if (String(res.body).indexOf("SUPABASE_SERVICE_ROLE_KEY") !== -1) {
    bad(label + " included the service role name");
  }
}

clearEnv();
installFetch("deny");

var deleteSrc = "";
try {
  deleteSrc = fs.readFileSync(pathDel, "utf8");
} catch (err) {
  bad("could not read delete-account.js");
  process.exit(1);
}
if (deleteSrc.indexOf("console.") !== -1) bad("delete-account.js contains console.");
if (deleteSrc.indexOf("8899") !== -1) bad("delete-account.js mentions port 8899");

var accountConfig;
var deleteAccount;
try {
  accountConfig = require(pathCfg);
  deleteAccount = require(pathDel);
} catch (err) {
  bad("could not load handlers");
  process.exit(1);
}
if (typeof accountConfig !== "function") bad("account-config.js does not export a function");
if (typeof deleteAccount !== "function") bad("delete-account.js does not export a function");

function callConfig(method) {
  var res = fakeRes();
  var req = { headers: {} };
  if (method !== undefined) req.method = method;
  armQuiet();
  try {
    accountConfig(req, res);
  } finally {
    disarmQuiet();
  }
  if (io.logged) bad("account-config logged");
  if (calls.length !== 0) bad("account-config made a request");
  return res;
}

function assertNotReady(res, label) {
  if (res.statusCode !== 404) bad(label + " status");
  if (res.body !== '{"ready":false}') bad(label + " body");
  var body = parsed(res);
  if (!body || body.ready !== false || Object.keys(body).length !== 1) bad(label + " payload");
  cache(res, label);
  assertNoSecrets(res, label);
}

function assertNotAllowed(res) {
  if (res.statusCode !== 405) bad("non-get status");
  cache(res, "non-get");
  assertNoSecrets(res, "non-get");
  if (bodyHas(res, URL) || bodyHas(res, ANON)) bad("non-get leaked config");
}

async function callDelete(req) {
  var res = fakeRes();
  var threw = false;
  armQuiet();
  try {
    await deleteAccount(req, res);
  } catch (err) {
    threw = true;
  } finally {
    disarmQuiet();
  }
  if (threw) bad("delete-account threw");
  if (io.logged) bad("delete-account logged");
  return res;
}

async function main() {
  var configMissing = [
    ["url unset", undefined, ANON],
    ["url empty", "", ANON],
    ["url blank", " \n\t ", ANON],
    ["anon unset", URL, undefined],
    ["anon empty", URL, ""],
    ["anon blank", URL, "  "],
    ["both unset", undefined, undefined],
    ["both empty", "", ""],
    ["both blank", " \t", " \n"]
  ];

  configMissing.forEach(function (row) {
    installFetch("deny");
    setEnv(row[1], row[2], SERVICE);
    assertNotReady(callConfig("GET"), row[0]);
  });

  installFetch("deny");
  setEnv(URL, ANON, SERVICE);
  var ready = callConfig("GET");
  if (ready.statusCode !== 200) bad("ready status");
  var readyBody = parsed(ready);
  var readyKeys = readyBody ? Object.keys(readyBody).sort().join(",") : "";
  if (ready.body !== JSON.stringify({ ready: true, url: process.env.SUPABASE_URL, anonKey: process.env.SUPABASE_ANON_KEY })) {
    bad("ready body");
  }
  if (!readyBody || readyBody.ready !== true || readyKeys !== "anonKey,ready,url") bad("ready payload");
  if (!readyBody || readyBody.url !== process.env.SUPABASE_URL || readyBody.anonKey !== process.env.SUPABASE_ANON_KEY) {
    bad("ready payload mismatch");
  }
  cache(ready, "ready");
  assertNoSecrets(ready, "ready");

  ["POST", "PUT", "DELETE", "PATCH", "HEAD", "get", undefined].forEach(function (method) {
    installFetch("deny");
    setEnv(URL, ANON, SERVICE);
    assertNotAllowed(callConfig(method));
    installFetch("deny");
    setEnv(undefined, undefined, SERVICE);
    assertNotAllowed(callConfig(method));
  });

  var deleteMissing = [
    ["delete url unset", undefined, ANON, SERVICE],
    ["delete url empty", "", ANON, SERVICE],
    ["delete url blank", "  ", ANON, SERVICE],
    ["delete anon unset", URL, undefined, SERVICE],
    ["delete anon empty", URL, "", SERVICE],
    ["delete anon blank", URL, "\t", SERVICE],
    ["delete service unset", URL, ANON, undefined],
    ["delete service empty", URL, ANON, ""],
    ["delete service blank", URL, ANON, " \n"],
    ["delete all unset", undefined, undefined, undefined],
    ["delete all blank", " ", " ", " "]
  ];

  for (var i = 0; i < deleteMissing.length; i += 1) {
    var missing = deleteMissing[i];
    installFetch("ok");
    setEnv(missing[1], missing[2], missing[3]);
    var missingRes = await callDelete({
      method: "POST",
      headers: {
        authorization: "Bearer " + BEARER,
        "x-mesh-token": MESH_TOKEN
      }
    });
    if (missingRes.statusCode !== 500) bad(missing[0] + " status");
    if (
      bodyHas(missingRes, process.env.SUPABASE_URL) ||
      bodyHas(missingRes, process.env.SUPABASE_ANON_KEY) ||
      bodyHas(missingRes, process.env.SUPABASE_SERVICE_ROLE_KEY) ||
      bodyHas(missingRes, URL) ||
      bodyHas(missingRes, ANON) ||
      bodyHas(missingRes, SERVICE) ||
      bodyHas(missingRes, BEARER)
    ) bad(missing[0] + " body contained a configured value");
    if (calls.length !== 0) bad(missing[0] + " made a request");
    assertNoMachine(calls);
    assertNoSecrets(missingRes, missing[0]);
  }

  var noBearer = [
    { method: "POST" },
    { method: "POST", headers: {} },
    { method: "POST", headers: { authorization: "" } },
    { method: "POST", headers: { authorization: "Bearer" } },
    { method: "POST", headers: { authorization: "Bearer " } },
    { method: "POST", headers: { Authorization: "Basic abc" } },
    { method: "POST", headers: { authorization: "bearer " + BEARER } }
  ];

  for (var n = 0; n < noBearer.length; n += 1) {
    installFetch("ok");
    setEnv(URL, ANON, SERVICE);
    var denied = await callDelete(noBearer[n]);
    if (denied.statusCode !== 401) bad("missing bearer status");
    if (calls.length !== 0) bad("missing bearer made a request");
    assertNoMachine(calls);
    assertNoSecrets(denied, "missing bearer");
    if (bodyHas(denied, URL) || bodyHas(denied, ANON) || bodyHas(denied, SERVICE)) {
      bad("missing bearer body contained a configured value");
    }
  }

  var failed = ["user-fail", "throw", "bad-id", "missing-id"];
  for (var f = 0; f < failed.length; f += 1) {
    var mode = failed[f];
    installFetch(mode);
    setEnv(URL, ANON, SERVICE);
    var failedRes = await callDelete({
      method: "POST",
      headers: {
        authorization: "Bearer " + BEARER,
        "x-mesh-token": MESH_TOKEN
      }
    });
    if (failedRes.statusCode !== 401) bad(mode + " status");
    if (calls.length !== 1) bad(mode + " request count");
    else {
      if (calls[0].method !== "GET" || calls[0].url !== URL + "/auth/v1/user") bad(mode + " verify endpoint");
      if (calls[0].redirect !== "error") bad(mode + " verify redirect");
      if (calls[0].headers.apikey !== ANON) bad(mode + " verify apikey");
      if (calls[0].headers.Authorization !== "Bearer " + BEARER) bad(mode + " verify authorization");
      if (callCarries(calls[0], SERVICE)) bad(mode + " sent the service role");
    }
    if (calls.some(function (call) {
      return call.method === "DELETE" || String(call.url).indexOf("/auth/v1/admin/") !== -1;
    })) bad(mode + " called admin delete");
    assertNoMachine(calls);
    assertNoSecrets(failedRes, mode);
  }

  installFetch("ok");
  setEnv(URL, ANON, SERVICE);
  var deleted = await callDelete({
    method: "POST",
    headers: {
      authorization: "Bearer " + BEARER,
      "x-mesh-token": MESH_TOKEN
    }
  });
  if (deleted.statusCode !== 200) bad("delete status");
  if (deleted.body !== '{"ok":true}') bad("delete body");
  var deletedBody = parsed(deleted);
  if (!deletedBody || deletedBody.ok !== true || Object.keys(deletedBody).length !== 1) bad("delete payload");
  cache(deleted, "delete");
  if (calls.length !== 2) bad("delete request count");
  else {
    if (calls[0].method !== "GET" || calls[0].url !== URL + "/auth/v1/user") bad("verify endpoint");
    if (calls[1].method !== "DELETE" || calls[1].url !== URL + "/auth/v1/admin/users/" + USER_ID) {
      bad("admin delete endpoint");
    }
    if (calls[0].redirect !== "error" || calls[1].redirect !== "error") bad("delete redirect");
    if (calls[0].headers.apikey !== ANON) bad("verify apikey");
    if (calls[0].headers.Authorization !== "Bearer " + BEARER) bad("verify authorization");
    if (calls[1].headers.apikey !== SERVICE) bad("admin apikey");
    if (calls[1].headers.Authorization !== "Bearer " + SERVICE) bad("admin authorization");
    if (callCarries(calls[0], SERVICE)) bad("service role sent on verify");
    if (!callCarries(calls[1], SERVICE)) bad("service role missing on admin delete");
    if (String(calls[1].url).indexOf(SERVICE) !== -1) bad("service role in admin url");
    if (calls[0].headers.apikey === SERVICE || String(calls[0].headers.Authorization || "").indexOf(SERVICE) !== -1) {
      bad("service role sent outside admin delete");
    }
  }
  assertNoMachine(calls);
  assertNoSecrets(deleted, "delete");
  if (bodyHas(deleted, URL) || bodyHas(deleted, ANON)) bad("delete body contained a configured value");

  if (failures) process.exit(1);
  print("check-account-handlers: OK");
}

main().catch(function () {
  disarmQuiet();
  print("FAIL: check-account-handlers.sh: handler check failed");
  process.exit(1);
});
NODE
