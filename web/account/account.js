/* Website account. Identity only: username, email, password.
   A missing or empty config.js shows the setup message and returns
   before fetch, so this file does not call the network.
   Password reset reads the recovery session from the URL hash and
   writes a new password. It does not read or write devices or a mailbox. */
(function () {
  var SETUP = "Account setup is not finished on this deploy";

  function meshAccountShowSetup() {
    var el = document.getElementById("setup");
    if (!el) return;
    el.hidden = false;
    el.textContent = SETUP;
  }

  function meshAccountHideSetup() {
    var el = document.getElementById("setup");
    if (el) el.hidden = true;
  }

  function meshAccountConfig() {
    var c = window.MESH_ACCOUNT;
    if (!c || typeof c.url !== "string" || typeof c.anonKey !== "string") return null;
    var url = c.url.trim().replace(/\/+$/, "");
    var key = c.anonKey.trim();
    if (!url || !key) return null;
    if (url.indexOf("https://") !== 0 && url.indexOf("http://") !== 0) return null;
    return { url: url, anonKey: key };
  }

  function meshAccountCall(path, opts) {
    var cfg = meshAccountConfig();
    if (!cfg) {
      meshAccountShowSetup();
      return Promise.resolve(null);
    }
    opts = opts || {};
    var headers = {
      apikey: cfg.anonKey,
      Authorization: "Bearer " + cfg.anonKey,
      "Content-Type": "application/json",
      Accept: "application/json"
    };
    if (opts.token) headers.Authorization = "Bearer " + opts.token;
    if (opts.prefer) headers.Prefer = opts.prefer;
    return fetch(cfg.url + path, {
      method: opts.method || "POST",
      headers: headers,
      credentials: "omit",
      body: Object.prototype.hasOwnProperty.call(opts, "body") ? JSON.stringify(opts.body) : undefined
    }).then(function (res) {
      return res.text().then(function (text) {
        var data = null;
        if (text) {
          try { data = JSON.parse(text); } catch (e) { data = { message: text }; }
        }
        return { ok: res.ok, status: res.status, data: data };
      });
    });
  }

  function setStatus(text, kind) {
    var el = document.getElementById("status");
    if (!el) return;
    el.textContent = text || "";
    el.className = "status" + (kind ? " " + kind : "");
  }

  function errorText(data) {
    if (!data) return "The account service refused the request.";
    if (typeof data.error_description === "string" && data.error_description) return data.error_description;
    if (typeof data.msg === "string" && data.msg) return data.msg;
    if (typeof data.message === "string" && data.message) return data.message;
    if (typeof data.error === "string" && data.error) return data.error;
    return "The account service refused the request.";
  }

  function usernameOk(value) {
    return /^[a-z0-9_]{3,32}$/.test(value);
  }

  function field(form, name) {
    var el = form.elements[name];
    return el ? String(el.value || "").trim() : "";
  }

  function sessionOf(data) {
    if (!data || !data.access_token) return null;
    var user = data.user || {};
    var id = user.id || "";
    if (!id) return null;
    var meta = user.user_metadata || {};
    return { token: data.access_token, id: id, username: meta.username || "" };
  }

  function saveProfile(session, username) {
    var name = username || session.username;
    if (!session || !name) return Promise.resolve({ ok: true, skipped: true });
    return meshAccountCall("/rest/v1/profiles?on_conflict=id", {
      token: session.token,
      prefer: "resolution=merge-duplicates,return=minimal",
      body: { id: session.id, username: name }
    });
  }

  function withButton(form, work) {
    var button = form.querySelector("button[type=submit]");
    if (button) button.disabled = true;
    return Promise.resolve()
      .then(work)
      .then(function () {
        if (button) button.disabled = false;
      }, function (err) {
        if (button) button.disabled = false;
        setStatus(err && err.message ? err.message : "Something went wrong.", "error");
      });
  }

  function signUp(form) {
    if (!meshAccountConfig()) {
      meshAccountShowSetup();
      return;
    }
    var username = field(form, "username");
    var email = field(form, "email");
    var password = field(form, "password");
    if (!usernameOk(username)) {
      setStatus("Username must be 3–32 characters: a–z, 0–9, underscore.", "error");
      return;
    }
    if (!email || email.indexOf("@") === -1) {
      setStatus("Enter an email address.", "error");
      return;
    }
    if (!password) {
      setStatus("Enter a password.", "error");
      return;
    }
    setStatus("Creating the account…");
    withButton(form, function () {
      return meshAccountCall("/auth/v1/signup", {
        body: { email: email, password: password, data: { username: username } }
      }).then(function (res) {
        if (!res) return;
        if (!res.ok) {
          setStatus(errorText(res.data), "error");
          return;
        }
        var session = sessionOf(res.data);
        if (!session) {
          setStatus("Check your email to confirm, then sign in. The username is saved with the login and written to your profile on sign-in. Nothing about your machines was stored.", "ok");
          return;
        }
        return saveProfile(session, username).then(function (saved) {
          if (saved && saved.ok === false) {
            setStatus("The login exists, but the username was not saved. " + errorText(saved.data), "error");
            return;
          }
          setStatus("Account created. It identifies you on this website and does not hold mesh tokens, addresses, or a host list.", "ok");
        });
      });
    });
  }

  function signIn(form) {
    if (!meshAccountConfig()) {
      meshAccountShowSetup();
      return;
    }
    var email = field(form, "email");
    var password = field(form, "password");
    if (!email || !password) {
      setStatus("Enter your email and password.", "error");
      return;
    }
    setStatus("Signing in…");
    withButton(form, function () {
      return meshAccountCall("/auth/v1/token?grant_type=password", {
        body: { email: email, password: password }
      }).then(function (res) {
        if (!res) return;
        if (!res.ok) {
          setStatus(errorText(res.data), "error");
          return;
        }
        var session = sessionOf(res.data);
        var profile = session ? saveProfile(session, session.username) : Promise.resolve(null);
        return profile.then(function (saved) {
          if (saved && saved.ok === false) {
            setStatus("Signed in, but the username was not saved on your profile. " + errorText(saved.data), "error");
            return;
          }
          setStatus("Signed in. This account does not copy your machines onto this device.", "ok");
        });
      });
    });
  }

  function forgot(form) {
    if (!meshAccountConfig()) {
      meshAccountShowSetup();
      return;
    }
    var email = field(form, "email");
    if (!email || email.indexOf("@") === -1) {
      setStatus("Enter an email address.", "error");
      return;
    }
    var redirectTo = window.location.origin + "/account/reset";
    setStatus("Sending the reset email…");
    withButton(form, function () {
      return meshAccountCall("/auth/v1/recover?redirect_to=" + encodeURIComponent(redirectTo), {
        body: { email: email }
      }).then(function (res) {
        if (!res) return;
        if (!res.ok) {
          setStatus(errorText(res.data), "error");
          return;
        }
        setStatus("If that email can receive mail, a reset link is on its way. The link only sets a new password.", "ok");
      });
    });
  }

  function recoveryFromUrl() {
    var hash = new URLSearchParams((window.location.hash || "").replace(/^#/, ""));
    var error = hash.get("error_description") || hash.get("error") || "";
    var token = hash.get("access_token") || "";
    var type = hash.get("type") || "";
    if (window.location.hash) {
      history.replaceState(null, "", window.location.pathname + window.location.search);
    }
    return { error: error, token: type === "recovery" ? token : "", type: type };
  }

  function resetPassword(form) {
    var recovery = form._recovery || { token: "" };
    if (recovery.error) {
      setStatus(recovery.error, "error");
      return;
    }
    if (!recovery.token) {
      setStatus("Open the reset link from your email. This page does not change a password without that recovery session.", "error");
      return;
    }
    if (!meshAccountConfig()) {
      meshAccountShowSetup();
      return;
    }
    var password = field(form, "new-password");
    if (!password) {
      setStatus("Enter a new password.", "error");
      return;
    }
    setStatus("Updating the password…");
    withButton(form, function () {
      return meshAccountCall("/auth/v1/user", {
        method: "PUT",
        token: recovery.token,
        body: { password: password }
      }).then(function (res) {
        if (!res) return;
        if (!res.ok) {
          setStatus(errorText(res.data), "error");
          return;
        }
        window.location.assign("/account/sign-in?reset=1");
      });
    });
  }

  var page = document.body.getAttribute("data-account");
  if (meshAccountConfig()) meshAccountHideSetup();
  else meshAccountShowSetup();

  if (page === "sign-in" && new URLSearchParams(window.location.search).get("reset") === "1") {
    setStatus("Password updated. Sign in with the new one. This did not change anything on your machines.", "ok");
  }

  var form = document.getElementById("form");
  if (!form) return;
  if (page === "reset") form._recovery = recoveryFromUrl();
  form.addEventListener("submit", function (ev) {
    ev.preventDefault();
    if (page === "sign-up") signUp(form);
    else if (page === "sign-in") signIn(form);
    else if (page === "forgot") forgot(form);
    else if (page === "reset") resetPassword(form);
  });
})();
