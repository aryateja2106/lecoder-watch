"use strict";

/* Delete the signed-in auth user. Profiles, devices, and mailbox rows
   cascade from that user. Mesh tokens stay on the machines; this
   function never contacts one and never logs the session or the keys. */

function send(res, status, body) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.end(JSON.stringify(body));
}

function bearer(header) {
  if (typeof header !== "string") return "";
  var match = /^Bearer\s+(\S+)$/.exec(header.trim());
  return match ? match[1] : "";
}

function envValue(name) {
  var value = process.env[name];
  if (typeof value !== "string") return "";
  return value.trim();
}

module.exports = async function deleteAccount(req, res) {
  if (!req || req.method !== "POST") {
    send(res, 405, { error: "Method not allowed." });
    return;
  }

  var url = envValue("SUPABASE_URL");
  var anonKey = envValue("SUPABASE_ANON_KEY");
  var serviceKey = envValue("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) {
    send(res, 500, { error: "Account deletion is unavailable." });
    return;
  }

  var header = req.headers && (req.headers.authorization || req.headers.Authorization);
  var token = bearer(header);
  if (!token) {
    send(res, 401, { error: "Sign in required." });
    return;
  }

  var base = url.replace(/\/+$/, "");
  var userId = "";
  try {
    var got = await fetch(base + "/auth/v1/user", {
      method: "GET",
      redirect: "error",
      headers: {
        apikey: anonKey,
        Authorization: "Bearer " + token,
        Accept: "application/json"
      }
    });
    if (!got.ok) {
      send(res, 401, { error: "Sign in required." });
      return;
    }
    var payload = await got.json();
    userId = payload && typeof payload.id === "string" ? payload.id : "";
  } catch (err) {
    send(res, 401, { error: "Sign in required." });
    return;
  }

  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(userId)) {
    send(res, 401, { error: "Sign in required." });
    return;
  }

  try {
    var deleted = await fetch(base + "/auth/v1/admin/users/" + userId, {
      method: "DELETE",
      redirect: "error",
      headers: {
        apikey: serviceKey,
        Authorization: "Bearer " + serviceKey,
        Accept: "application/json"
      }
    });
    await deleted.arrayBuffer();
    if (!deleted.ok) {
      send(res, 500, { error: "Account deletion is unavailable." });
      return;
    }
  } catch (err) {
    send(res, 500, { error: "Account deletion is unavailable." });
    return;
  }

  send(res, 200, { ok: true });
};
