#!/bin/sh
# check-account-flow.sh — drive web/account/account.js with a fake document
# and a fake fetch. Node built-ins only. No Supabase project, no live host,
# and no key.
#
# A missing client config may probe same-origin /api/account-config. That
# probe is how this deploy learns the account service is not configured.
# A not-ready or failed probe must show the setup sentence and must not
# be followed by any other request.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JS="$ROOT/web/account/account.js"

if [ ! -f "$JS" ]; then
  echo "FAIL: check-account-flow.sh: web/account/account.js is missing"
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: check-account-flow.sh: node is required"
  exit 1
fi

node - "$JS" << 'NODE'
"use strict";

var fs = require("fs");
var vm = require("vm");

var source = fs.readFileSync(process.argv[2], "utf8");
var failures = 0;

function bad(msg) {
  failures += 1;
  console.log("FAIL: check-account-flow.sh: " + msg);
}

function flush() {
  return new Promise(function (resolve) { setImmediate(resolve); }).then(function () {
    return new Promise(function (resolve) { setImmediate(resolve); });
  });
}

var SETUP = "Account setup is not finished on this deploy";
var STUB = "https://account.stub.test";
var ANON = "anon-key-public";
var USER_ID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
var EMAIL = "ada@example.com";
var PASSWORD = "s3cret-pass";
var USERNAME = "ada_lane";
var NEW_PASSWORD = "newer-pass";
var SENTINEL_TOKEN = "mesh-token-sentinel";
var SENTINEL_IP = "10.1.2.3";
var SENTINEL_HOST = "kitchen.local";
var ORIGIN = "https://mesh.example.test";

function response(status, body) {
  var text = "";
  if (body != null && body !== "") text = typeof body === "string" ? body : JSON.stringify(body);
  return {
    ok: status >= 200 && status < 300,
    status: status,
    text: function () { return Promise.resolve(text); }
  };
}

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
  setup.textContent = SETUP;
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
  var del = el();
  del._listeners = [];
  del.addEventListener = function (type, fn) {
    this._listeners.push({ type: type, fn: fn });
  };
  var empty = el();
  var list = el();
  list.hidden = true;
  var ids = {
    setup: setup,
    status: status,
    form: page === "home" ? null : form,
    "delete-account": del,
    "devices-empty": empty,
    "device-labels": list
  };
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

function storageOf(initial) {
  var map = new Map();
  if (initial) {
    Object.keys(initial).forEach(function (key) { map.set(key, initial[key]); });
  }
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
  if (extra) {
    Object.keys(extra).forEach(function (key) { fields[key] = extra[key]; });
  }
  return fields;
}

function boot(opts) {
  var calls = [];
  var assigned = [];
  var confirms = [];
  var document = makeDocument(opts.page);
  if (document._ids.form && opts.fields) document._ids.form.elements = opts.fields;
  var location = {
    origin: opts.origin || ORIGIN,
    hash: opts.hash || "",
    pathname: "/account/" + opts.page,
    search: opts.search || "",
    assign: function (url) { assigned.push(String(url)); }
  };
  var history = {
    replaceState: function () { location.hash = ""; }
  };
  var windowObj = {
    location: location,
    confirm: function (message) {
      confirms.push(String(message));
      return opts.confirm !== false;
    }
  };
  if (Object.prototype.hasOwnProperty.call(opts, "config")) windowObj.MESH_ACCOUNT = opts.config;
  var fetchImpl = function (url, init) {
    var options = init || {};
    var call = {
      url: String(url),
      method: options.method || "GET",
      headers: options.headers || {},
      body: Object.prototype.hasOwnProperty.call(options, "body") ? options.body : undefined,
      credentials: options.credentials
    };
    calls.push(call);
    if (opts.probe === "reject") {
      return Promise.reject(new Error("offline"));
    }
    try {
      return Promise.resolve(opts.route(call));
    } catch (err) {
      return Promise.reject(err);
    }
  };
  windowObj.fetch = fetchImpl;
  var sessionStorage = storageOf(opts.storage);
  var sandbox = {
    document: document,
    window: windowObj,
    history: history,
    sessionStorage: sessionStorage,
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
  return flush().then(function () {
    return {
      calls: calls,
      assigned: assigned,
      confirms: confirms,
      document: document,
      storage: sessionStorage,
      location: location
    };
  });
}

function submit(page) {
  var form = page.document._ids.form;
  if (!form) throw new Error("no form");
  var listeners = form._listeners.filter(function (item) { return item.type === "submit"; });
  if (listeners.length !== 1) throw new Error("expected one submit listener");
  listeners[0].fn({ preventDefault: function () {} });
}

function clickDelete(page) {
  var button = page.document._ids["delete-account"];
  var listeners = button._listeners.filter(function (item) { return item.type === "click"; });
  if (listeners.length !== 1) throw new Error("expected one delete listener");
  listeners[0].fn({});
}

function accountCalls(calls) {
  return calls.filter(function (call) { return call.url !== "/api/account-config"; });
}

function parsed(call) {
  if (call.body == null) return null;
  return JSON.parse(String(call.body));
}

function isEmail(value) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function walkBody(value, label, seen) {
  if (value == null) return;
  if (typeof value === "string") {
    if (value.indexOf(SENTINEL_TOKEN) !== -1) bad(label + " body includes a mesh token");
    if (value.indexOf(SENTINEL_IP) !== -1 || value.indexOf("10.1.2.3") !== -1) bad(label + " body includes an ip");
    if (value.indexOf(SENTINEL_HOST) !== -1 || value.indexOf("mac.local") !== -1) bad(label + " body includes a hostname");
    if (value.indexOf("account.stub.test") !== -1 || value.indexOf("mesh.example.test") !== -1) {
      bad(label + " body includes a hostname");
    }
    if (value.indexOf("service_role") !== -1) bad(label + " body includes a service role");
    if (!isEmail(value)) {
      if (/\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b/.test(value)) {
        bad(label + " body includes an ip");
      }
      if (/^(?:[a-z0-9-]+\.)+[a-z]{2,}$/i.test(value)) bad(label + " body includes a hostname");
    }
    return;
  }
  if (typeof value !== "object") return;
  if (seen.has(value)) return;
  seen.add(value);
  if (Array.isArray(value)) {
    value.forEach(function (item) { walkBody(item, label, seen); });
    return;
  }
  Object.keys(value).forEach(function (key) {
    if (/^(token|ip|hostname|host|mac|apns|tailnet)$/i.test(key)) bad(label + " body key " + key);
    walkBody(value[key], label, seen);
  });
}

function assertClean(call, label) {
  var url = call.url || "";
  if (url.indexOf("supabase.co") !== -1 || url.indexOf("supabase.com") !== -1) {
    bad(label + " called a Supabase host");
  }
  var headerText = JSON.stringify(call.headers || {});
  if (headerText.indexOf("service_role") !== -1) bad(label + " request carries a service role");
  if (call.body == null) return;
  var raw = String(call.body);
  if (raw.indexOf(SENTINEL_TOKEN) !== -1) bad(label + " body includes a mesh token");
  if (raw.indexOf(SENTINEL_IP) !== -1) bad(label + " body includes an ip");
  if (raw.indexOf(SENTINEL_HOST) !== -1 || raw.indexOf("mac.local") !== -1) bad(label + " body includes a hostname");
  if (raw.indexOf("service_role") !== -1) bad(label + " body includes a service role");
  try {
    walkBody(JSON.parse(raw), label, new Set());
  } catch (err) {
    bad(label + " body is not json");
  }
}

function assertSetup(page, label) {
  var setup = page.document._ids.setup;
  if (!setup || setup.hidden !== false) bad(label + " hides the setup sentence");
  if (!setup || setup.textContent !== SETUP) bad(label + " does not show the setup sentence");
}

function routeMissing(call) {
  if (call.url === "/api/account-config" && call.method === "GET") {
    return response(404, { ready: false });
  }
  call.unexpected = true;
  return response(500, { message: "unexpected" });
}

function userPayload(username) {
  return {
    id: USER_ID,
    email: EMAIL,
    user_metadata: { username: username || "" },
    host: SENTINEL_HOST,
    ip: SENTINEL_IP,
    token: SENTINEL_TOKEN
  };
}

function routeConfigured(state) {
  return function (call) {
    if (call.url === "/api/account-config") {
      call.unexpected = true;
      return response(500, { message: "config probe despite client config" });
    }
    if (call.url === "/api/delete-account") return response(200, { ok: true });
    if (call.url.indexOf(STUB + "/auth/v1/signup") === 0) {
      var signup = parsed(call);
      state.username = signup && signup.data ? signup.data.username : "";
      return response(200, userPayload(state.username));
    }
    if (call.url.indexOf(STUB + "/auth/v1/token") === 0) {
      return response(200, {
        access_token: "user-access-token",
        token_type: "bearer",
        user: userPayload(state.username)
      });
    }
    if (call.url.indexOf(STUB + "/auth/v1/recover") === 0) return response(200, {});
    if (call.url.indexOf(STUB + "/auth/v1/user") === 0) return response(200, { id: USER_ID });
    if (call.url.indexOf(STUB + "/rest/v1/profiles") === 0) return response(201, "");
    if (call.url.indexOf(STUB + "/rest/v1/devices") === 0) return response(200, []);
    call.unexpected = true;
    return response(500, { message: "unexpected" });
  };
}

function configured() {
  return { url: STUB, anonKey: ANON };
}

function assertNoUnexpected(page, label) {
  page.calls.forEach(function (call) {
    if (call.unexpected) bad(label + " unexpected request " + call.method + " " + call.url);
    assertClean(call, label);
  });
}

async function scenario(name, fn) {
  var before = failures;
  try {
    await fn();
  } catch (err) {
    bad(name + " threw: " + (err && err.stack ? err.stack : err));
  }
  if (failures === before) console.log("ok: " + name);
}

function keysOf(value) {
  return Object.keys(value || {}).sort();
}

async function main() {
  await scenario("missing config shows the setup sentence and makes no account request", async function () {
    var pages = ["sign-up", "sign-in", "forgot", "reset", "home"];
    for (var i = 0; i < pages.length; i++) {
      var name = pages[i];
      var page = await boot({
        page: name,
        fields: decoyFields({
          username: { value: USERNAME },
          email: { value: EMAIL },
          password: { value: PASSWORD },
          "new-password": { value: NEW_PASSWORD }
        }),
        route: routeMissing
      });
      assertSetup(page, name);
      if (accountCalls(page.calls).length !== 0) bad(name + " called the account service without config");
      if (page.calls.length !== 1 || page.calls[0].url !== "/api/account-config" || page.calls[0].method !== "GET") {
        bad(name + " did not limit itself to the same-origin config probe");
      }
      if (page.calls[0] && (page.calls[0].body != null || page.calls[0].headers.Authorization)) {
        bad(name + " config probe carried a body or a bearer");
      }
      if (name === "home") clickDelete(page);
      else submit(page);
      await flush();
      assertSetup(page, name + " after submit");
      if (accountCalls(page.calls).length !== 0) bad(name + " called the account service after the setup sentence");
      if (page.calls.length !== 1) bad(name + " made another network call after the setup sentence");
      assertNoUnexpected(page, name);
    }

    var empty = await boot({
      page: "sign-up",
      config: { url: "", anonKey: "" },
      fields: decoyFields({
        username: { value: USERNAME },
        email: { value: EMAIL },
        password: { value: PASSWORD }
      }),
      route: routeMissing
    });
    assertSetup(empty, "empty config");
    submit(empty);
    await flush();
    if (accountCalls(empty.calls).length !== 0 || empty.calls.length !== 1) {
      bad("empty config called the account service");
    }
    assertNoUnexpected(empty, "empty config");

    var offline = await boot({
      page: "sign-up",
      probe: "reject",
      fields: decoyFields({
        username: { value: USERNAME },
        email: { value: EMAIL },
        password: { value: PASSWORD }
      }),
      route: routeMissing
    });
    assertSetup(offline, "offline config");
    submit(offline);
    await flush();
    if (offline.calls.some(function (call) { return call.url !== "/api/account-config"; })) {
      bad("a failed config probe was followed by another request");
    }
    assertNoUnexpected(offline, "offline config");
  });

  var state = { username: "" };

  await scenario("sign-up sends username, email, and password and defers the profile until sign-in", async function () {
    var page = await boot({
      page: "sign-up",
      config: configured(),
      fields: decoyFields({
        username: { value: USERNAME },
        email: { value: EMAIL },
        password: { value: PASSWORD }
      }),
      route: routeConfigured(state)
    });
    if (page.document._ids.setup.hidden !== true) bad("sign-up shows the setup sentence when config is present");
    submit(page);
    await flush();
    var signup = page.calls.filter(function (call) { return call.url.indexOf("/auth/v1/signup") !== -1; });
    if (signup.length !== 1) bad("sign-up did not send one signup request");
    else {
      var body = parsed(signup[0]);
      if (!body || body.email !== EMAIL || body.password !== PASSWORD) bad("sign-up did not send email and password");
      if (!body || !body.data || body.data.username !== USERNAME) bad("sign-up did not send username");
      if (keysOf(body).join(",") !== "data,email,password") bad("sign-up body is not username, email, and password");
      if (keysOf(body && body.data).join(",") !== "username") bad("sign-up metadata is not the username");
      if (signup[0].method !== "POST") bad("sign-up is not a POST");
    }
    if (page.calls.some(function (call) { return call.url.indexOf("/rest/v1/profiles") !== -1; })) {
      bad("sign-up wrote a profile when the stub returned no session");
    }
    if (page.calls.some(function (call) { return call.url.indexOf("/auth/v1/token") !== -1; })) {
      bad("sign-up signed in when the stub returned no session");
    }
    var status = page.document._ids.status.textContent || "";
    if (status.indexOf("sign in") === -1) bad("sign-up did not say the username is saved on sign-in");
    assertNoUnexpected(page, "sign-up");
    if (state.username !== USERNAME) bad("stub did not observe the signup username");
  });

  await scenario("sign-in is email and password, then saves {id, username}", async function () {
    var page = await boot({
      page: "sign-in",
      config: configured(),
      fields: decoyFields({
        email: { value: EMAIL },
        password: { value: PASSWORD },
        username: { value: "should-not-be-sent" }
      }),
      route: routeConfigured(state)
    });
    submit(page);
    await flush();
    var token = page.calls.filter(function (call) { return call.url.indexOf("/auth/v1/token") !== -1; });
    if (token.length !== 1) bad("sign-in did not send one token request");
    else {
      var body = parsed(token[0]);
      if (!body || body.email !== EMAIL || body.password !== PASSWORD) bad("sign-in did not send email and password");
      if (keysOf(body).join(",") !== "email,password") bad("sign-in body is not email and password");
      if (token[0].url.indexOf("grant_type=password") === -1) bad("sign-in is not a password grant");
      if (token[0].method !== "POST") bad("sign-in is not a POST");
    }
    var profiles = page.calls.filter(function (call) { return call.url.indexOf("/rest/v1/profiles") !== -1; });
    if (profiles.length !== 1) bad("sign-in did not save the username");
    else {
      var body = parsed(profiles[0]);
      if (keysOf(body).join(",") !== "id,username") bad("profile write is not {id, username} only");
      if (!body || body.id !== USER_ID || body.username !== USERNAME) bad("profile write did not keep the signup username");
      if (profiles[0].method !== "POST") bad("profile write is not a POST");
      var auth = profiles[0].headers.Authorization || "";
      if (auth !== "Bearer user-access-token") bad("profile write did not use the sign-in bearer");
    }
    var tokenAt = page.calls.findIndex(function (call) { return call.url.indexOf("/auth/v1/token") !== -1; });
    var profileAt = page.calls.findIndex(function (call) { return call.url.indexOf("/rest/v1/profiles") !== -1; });
    if (!(tokenAt >= 0 && profileAt > tokenAt)) bad("username was not saved on the later sign-in");
    if (page.assigned.length !== 1 || page.assigned[0] !== "/account/home") bad("sign-in did not continue to the account home");
    assertNoUnexpected(page, "sign-in");
  });

  await scenario("forgot requests a recovery email whose redirect ends in /account/reset", async function () {
    var page = await boot({
      page: "forgot",
      config: configured(),
      fields: decoyFields({ email: { value: EMAIL } }),
      route: routeConfigured({ username: "" })
    });
    submit(page);
    await flush();
    var recover = page.calls.filter(function (call) { return call.url.indexOf("/auth/v1/recover") !== -1; });
    if (recover.length !== 1) bad("forgot did not request one recovery email");
    else {
      var redirect = "";
      try { redirect = new URL(recover[0].url).searchParams.get("redirect_to") || ""; }
      catch (err) { redirect = ""; }
      if (!redirect.endsWith("/account/reset")) bad("recovery redirect does not end in /account/reset");
      try {
        if (new URL(redirect).pathname !== "/account/reset") bad("recovery redirect path is not /account/reset");
      } catch (err) {
        bad("recovery redirect is not a url");
      }
      var body = parsed(recover[0]);
      if (keysOf(body).join(",") !== "email" || !body || body.email !== EMAIL) bad("forgot body is not the email");
      if (recover[0].method !== "POST") bad("forgot is not a POST");
    }
    if (page.calls.some(function (call) { return call.url.indexOf("/auth/v1/user") !== -1; })) {
      bad("forgot changed a password");
    }
    assertNoUnexpected(page, "forgot");
  });

  await scenario("reset sets a new password only when a recovery session is present", async function () {
    var absent = ["", "#access_token=not-recovery&type=signup"];
    for (var i = 0; i < absent.length; i++) {
      var page = await boot({
        page: "reset",
        config: configured(),
        hash: absent[i],
        fields: decoyFields({ "new-password": { value: NEW_PASSWORD } }),
        route: routeConfigured({ username: "" })
      });
      submit(page);
      await flush();
      if (page.calls.some(function (call) { return call.url.indexOf("/auth/v1/user") !== -1; })) {
        bad("reset changed a password without a recovery session");
      }
      var status = page.document._ids.status.textContent || "";
      if (status.indexOf("recovery session") === -1) bad("reset did not say a recovery session is required");
      if (page.assigned.length !== 0) bad("reset left the page without a recovery session");
      assertNoUnexpected(page, "reset without recovery");
    }

    var ready = await boot({
      page: "reset",
      config: configured(),
      hash: "#access_token=recovery-access-token&type=recovery",
      fields: decoyFields({ "new-password": { value: NEW_PASSWORD } }),
      route: routeConfigured({ username: "" })
    });
    submit(ready);
    await flush();
    var updates = ready.calls.filter(function (call) { return call.url.indexOf("/auth/v1/user") !== -1; });
    if (updates.length !== 1) bad("reset did not set the new password with a recovery session");
    else {
      var body = parsed(updates[0]);
      if (keysOf(body).join(",") !== "password" || !body || body.password !== NEW_PASSWORD) {
        bad("reset body is not the new password");
      }
      if (updates[0].method !== "PUT") bad("reset did not update the user");
      if (updates[0].headers.Authorization !== "Bearer recovery-access-token") {
        bad("reset did not use the recovery session bearer");
      }
    }
    if (ready.calls.some(function (call) { return call.url.indexOf("/rest/") !== -1; })) {
      bad("reset read or wrote a table");
    }
    if (ready.assigned.length !== 1 || ready.assigned[0] !== "/account/sign-in?reset=1") {
      bad("reset did not return to sign-in");
    }
    assertNoUnexpected(ready, "reset");
  });

  await scenario("delete calls the site function with the bearer and no service role", async function () {
    var page = await boot({
      page: "home",
      config: configured(),
      route: routeConfigured({ username: "" }),
      confirm: true
    });
    if (page.calls.length !== 0) bad("home called the network before delete");
    page.storage.setItem("mesh.account.session", JSON.stringify({
      token: "user-access-token",
      id: USER_ID,
      username: USERNAME,
      meshToken: SENTINEL_TOKEN,
      ip: SENTINEL_IP,
      hostname: SENTINEL_HOST
    }));
    page.storage.setItem("mesh.token", SENTINEL_TOKEN);
    clickDelete(page);
    await flush();
    var deletes = page.calls.filter(function (call) { return call.url === "/api/delete-account"; });
    if (deletes.length !== 1) bad("delete did not call the site delete function");
    else {
      var call = deletes[0];
      if (call.method !== "POST") bad("delete is not a POST");
      if (call.headers.Authorization !== "Bearer user-access-token") bad("delete did not send the session bearer");
      if (call.body != null) bad("delete sent a body");
      if (call.headers.apikey) bad("delete sent an apikey");
      var flat = JSON.stringify(call);
      if (flat.indexOf("service_role") !== -1 || flat.indexOf("SUPABASE_SERVICE_ROLE") !== -1) {
        bad("delete browser request carries a service role");
      }
      if (flat.indexOf(SENTINEL_TOKEN) !== -1 || flat.indexOf(SENTINEL_IP) !== -1 || flat.indexOf(SENTINEL_HOST) !== -1) {
        bad("delete browser request carries a mesh token, an ip, or a hostname");
      }
      if (call.url.indexOf("/auth/v1/admin") !== -1) bad("delete called the admin API from the browser");
    }
    if (page.calls.length !== 1) bad("delete made more than the site function call");
    assertNoUnexpected(page, "delete");
  });

  if (failures) process.exit(1);
  console.log("check-account-flow: OK");
}

main().catch(function (err) {
  console.log("FAIL: check-account-flow.sh: " + (err && err.stack ? err.stack : err));
  process.exit(1);
});
NODE
