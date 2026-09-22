"use strict";

/* Public client config for the website account pages. SUPABASE_URL and
   the anon key live in the deploy environment so the repo never stores
   them. This route only reads those two names, never calls Supabase,
   and never logs the values. */

function send(res, status, body) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.end(JSON.stringify(body));
}

function envValue(name) {
  var value = process.env[name];
  if (typeof value !== "string") return "";
  return value.trim();
}

module.exports = function accountConfig(req, res) {
  if (!req || req.method !== "GET") {
    send(res, 405, { error: "Method not allowed." });
    return;
  }

  var url = envValue("SUPABASE_URL");
  var anonKey = envValue("SUPABASE_ANON_KEY");
  if (!url || !anonKey) {
    send(res, 404, { ready: false });
    return;
  }

  send(res, 200, { ready: true, url: url, anonKey: anonKey });
};
