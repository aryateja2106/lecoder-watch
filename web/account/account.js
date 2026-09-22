/* Website account. Identity only: username, email, password.
   A filled config.js is used as-is. When that config is missing or its
   url or anon key is empty, the page asks /api/account-config. If that
   request fails or is not ready, the setup message shows and this file
   returns before any Supabase call.
   Password reset reads the recovery session from the URL hash and
   writes a new password. It does not read or write devices or a mailbox.
   Deleting an account removes that identity. It does not rotate mesh
   tokens and does not reach a machine.
   The signed-in home page reads device label and platform only.
   Pairing still happens on the machine. */
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

  var deployedConfig = null;
  var deployedConfigLoad = null;

  function readAccountConfig(c) {
    if (!c || typeof c.url !== "string" || typeof c.anonKey !== "string") return null;
    var url = c.url.trim().replace(/\/+$/, "");
    var key = c.anonKey.trim();
    if (!url || !key) return null;
    if (url.indexOf("https://") !== 0 && url.indexOf("http://") !== 0) return null;
    return { url: url, anonKey: key };
  }

  function meshAccountConfig() {
    return readAccountConfig(window.MESH_ACCOUNT) || deployedConfig;
  }

  function loadAccountConfig() {
    var existing = meshAccountConfig();
    if (existing) return Promise.resolve(existing);
    if (deployedConfigLoad) return deployedConfigLoad;
    deployedConfigLoad = fetch("/api/account-config", {
      method: "GET",
      credentials: "omit",
      cache: "no-store",
      headers: { Accept: "application/json" }
    }).then(function (res) {
      return res.text().then(function (text) {
        var data = null;
        if (text) {
          try { data = JSON.parse(text); } catch (e) { data = null; }
        }
        if (!res.ok || !data || data.ready !== true) return null;
        var cfg = readAccountConfig(data);
        if (!cfg) return null;
        deployedConfig = cfg;
        return cfg;
      }, function () {
        return null;
      });
    }, function () {
      return null;
    });
    return deployedConfigLoad;
  }

  function meshAccountCall(path, opts) {
    return loadAccountConfig().then(function (cfg) {
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
        if (session) saveSession(session);
        var profile = session ? saveProfile(session, session.username) : Promise.resolve(null);
        return profile.then(function (saved) {
          if (saved && saved.ok === false) {
            setStatus("Signed in, but the username was not saved on your profile. " + errorText(saved.data), "error");
            return;
          }
          window.location.assign("/account/home");
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

  var SESSION_KEY = "mesh.account.session";

  function loadSession() {
    try {
      var raw = sessionStorage.getItem(SESSION_KEY);
      if (!raw) return null;
      var data = JSON.parse(raw);
      if (!data || typeof data.token !== "string" || !data.token) return null;
      return { token: data.token, id: data.id || "", username: data.username || "" };
    } catch (e) {
      return null;
    }
  }

  function saveSession(session) {
    if (!session || !session.token) return;
    try {
      sessionStorage.setItem(SESSION_KEY, JSON.stringify({
        token: session.token,
        id: session.id || "",
        username: session.username || ""
      }));
    } catch (e) {}
  }

  function clearSession() {
    try { sessionStorage.removeItem(SESSION_KEY); } catch (e) {}
  }

  function deleteAccount() {
    return loadAccountConfig().then(function (cfg) {
      if (!cfg) {
        meshAccountShowSetup();
        return Promise.resolve(null);
      }
      var session = loadSession();
      if (!session) {
        setStatus("Sign in before deleting an account.", "error");
        return Promise.resolve(null);
      }
      if (!window.confirm("Delete this website account? Machines stay paired until token rotation is run locally.")) {
        return Promise.resolve(null);
      }
      var button = document.getElementById("delete-account");
      if (button) button.disabled = true;
      setStatus("Deleting the account…");
      return fetch("/api/delete-account", {
        method: "POST",
        credentials: "same-origin",
        headers: {
          Accept: "application/json",
          Authorization: "Bearer " + session.token
        }
      }).then(function (res) {
        return res.text().then(function (text) {
          if (res.status === 401) {
            clearSession();
            setStatus("Sign in again before deleting an account.", "error");
            if (button) button.disabled = false;
            return;
          }
          if (!res.ok) {
            setStatus("The account could not be deleted.", "error");
            if (button) button.disabled = false;
            return;
          }
          clearSession();
          setStatus("Account deleted. The next sign-in fails. Machines were not changed.", "ok");
        });
      }, function () {
        setStatus("The account could not be deleted.", "error");
        if (button) button.disabled = false;
      });
    });
  }

  var page = document.body.getAttribute("data-account");
  if (meshAccountConfig()) meshAccountHideSetup();
  else meshAccountShowSetup();

  if (page === "sign-in" && new URLSearchParams(window.location.search).get("reset") === "1") {
    setStatus("Password updated. Sign in with the new one. This did not change anything on your machines.", "ok");
  }

  function showDeviceLabels(rows) {
    var empty = document.getElementById("devices-empty");
    var list = document.getElementById("device-labels");
    if (!list) return;
    while (list.firstChild) list.removeChild(list.firstChild);
    var count = 0;
    var data = Object.prototype.toString.call(rows) === "[object Array]" ? rows : [];
    for (var i = 0; i < data.length; i++) {
      var row = data[i];
      if (!row || typeof row !== "object") continue;
      var label = typeof row.label === "string" ? row.label.trim() : "";
      var platform = typeof row.platform === "string" ? row.platform.trim() : "";
      if (!label && !platform) continue;
      var li = document.createElement("li");
      var name = document.createElement("span");
      name.className = "device-label";
      name.textContent = label;
      var kind = document.createElement("span");
      kind.className = "device-platform";
      kind.textContent = platform;
      li.appendChild(name);
      li.appendChild(kind);
      list.appendChild(li);
      count++;
    }
    if (count > 0) {
      list.hidden = false;
      if (empty) empty.hidden = true;
    } else {
      list.hidden = true;
      if (empty) empty.hidden = false;
    }
  }

  function readDeviceLabels(session) {
    if (!session || typeof session.id !== "string" || !session.id) {
      showDeviceLabels([]);
      return Promise.resolve(null);
    }
    return meshAccountCall(
      "/rest/v1/devices?select=label,platform&user_id=eq." + encodeURIComponent(session.id),
      { method: "GET", token: session.token }
    ).then(function (res) {
      if (!res || res.ok !== true || Object.prototype.toString.call(res.data) !== "[object Array]") {
        showDeviceLabels([]);
        return null;
      }
      showDeviceLabels(res.data);
      return null;
    });
  }

  function paintSignedIn() {
    if (page !== "home") return;
    var signedIn = loadSession();
    if (meshAccountConfig() && signedIn) {
      var who = signedIn.username ? "Signed in as " + signedIn.username + "." : "Signed in.";
      setStatus(who + " Deleting this account does not change your machines.", "ok");
    } else if (meshAccountConfig()) {
      setStatus("Sign in before deleting an account.", "error");
    }
  }

  loadAccountConfig().then(function (cfg) {
    if (!cfg) {
      meshAccountShowSetup();
      return;
    }
    meshAccountHideSetup();
    paintSignedIn();
    if (page === "home") {
      var signedIn = loadSession();
      if (signedIn) readDeviceLabels(signedIn);
    }
  });

  if (page === "home") {
    var del = document.getElementById("delete-account");
    if (del) del.addEventListener("click", function () { deleteAccount(); });
  }

  var form = document.getElementById("form");
  if (!form) return;
  if (page === "reset") form._recovery = recoveryFromUrl();
  form.addEventListener("submit", function (ev) {
    ev.preventDefault();
    loadAccountConfig().then(function (cfg) {
      if (!cfg) {
        meshAccountShowSetup();
        return;
      }
      if (page === "sign-up") signUp(form);
      else if (page === "sign-in") signIn(form);
      else if (page === "forgot") forgot(form);
      else if (page === "reset") resetPassword(form);
    });
  });
})();
