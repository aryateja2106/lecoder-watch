---
name: pwa-local-app-builder
description: Autonomous Progressive Web App (PWA) builder for Route 2 (users without an Apple Developer account, or who just want something running in under a minute). Builds a standalone static web app using local browser storage (IndexedDB / OPFS), iOS Safari Add to Home Screen optimization, and hosts it on the LAN via `mesh apps publish` — with an honest, tested account of what works offline and what needs the user's own HTTPS domain.
---

# Route 2: Progressive Web App (PWA) Builder (local-first storage)

Do not start here from a bare "build me an app": run the `app-brief` skill first and come
here only when the brief chose **web** (no Apple developer account, or the user wants it in
a minute). Build one app, once — never a native app "as well" unless asked. The icon
(`apple-touch-icon`, 180×180) is mandatory, not optional.

Use this skill when the user has no Apple Developer account, or just wants an app running
immediately without any signing or device pairing at all. Zero fees, zero provisioning
profiles, zero Xcode.

---

## 1. What this actually gets you (read before promising anything)

- **Immediate:** `mesh apps publish` hosts the app on this Mac and prints a LAN URL. Open
  it in Safari on the phone, tap **Share → Add to Home Screen**, and it runs full-screen
  with its own icon, no browser chrome.
- **Data stays local:** everything the app stores lives in the phone's own `IndexedDB` (or
  `OPFS` for larger/binary data) — nothing is sent anywhere, because there is nowhere
  configured to send it to.
- **Offline is conditional, and this is the part to be honest about:** a Service Worker
  (`sw.js`) — the thing that lets a PWA open with no network at all — only registers on a
  page served over **HTTPS or `localhost`**. `mesh apps publish` serves the app over plain
  `http://<lan-ip>:8899/...`, which is neither. So:
  - The app **works** over that LAN URL any time the Mac is on and reachable — this is
    the common case for "an app I use around the house."
  - The app does **not** work with the Mac off, asleep, or off the network, and does not
    install a true offline cache, because the service worker never registers on plain
    HTTP.
  - **True offline-anywhere** needs the app served over HTTPS the user actually owns —
    see §7 for the one-command options. Do not tell a user "this works offline" unless
    it is hosted that way.

---

## 2. Directory structure

```
<app-dir>/
├── index.html               # entrypoint with Apple PWA meta tags
├── app.js                   # application logic + IndexedDB local storage layer
├── styles.css                # UI styles
├── manifest.webmanifest     # PWA manifest (standalone, theme color, icons)
├── sw.js                    # service worker for offline caching (HTTPS/localhost only)
├── icon-192.png              # Android / desktop icon
└── icon-180.png              # Apple touch icon for iPhone / iPad Home Screen
```

`<app-dir>` can live anywhere (a scratch/build directory is fine) — `mesh apps publish`
copies it into `~/.mesh/apps/<slug>/site/`, so the source location doesn't matter once
published.

---

## 3. `index.html` — iOS meta tags + install banner

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <title>{{APP_NAME}}</title>

  <!-- iOS Safari standalone / Add to Home Screen support -->
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="{{APP_NAME}}">
  <link rel="apple-touch-icon" href="icon-180.png">

  <!-- PWA web manifest -->
  <link rel="manifest" href="manifest.webmanifest">
  <meta name="theme-color" content="#0a0a0c">

  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <div id="app"></div>

  <!-- In-app Add to Home Screen guidance (shown until installed) -->
  <div id="install-banner" class="install-banner hidden">
    <div class="banner-content">
      <p>Install this app on your iPhone: long-press the address bar, tap <strong>Share</strong> <span class="share-icon">⎋</span>, then <strong>Add to Home Screen</strong></p>
      <button onclick="dismissBanner()">Dismiss</button>
    </div>
  </div>

  <script src="app.js"></script>
  <script>
    // Registers only on HTTPS or localhost — silently does nothing over a plain LAN
    // http:// origin, which is expected. See SKILL.md §1 before promising "offline".
    if ('serviceWorker' in navigator) {
      window.addEventListener('load', () => {
        navigator.serviceWorker.register('sw.js').catch(() => { /* not a secure context; fine */ });
      });
    }

    if (window.navigator.standalone === true || window.matchMedia('(display-mode: standalone)').matches) {
      document.getElementById('install-banner')?.remove();
    } else {
      document.getElementById('install-banner')?.classList.remove('hidden');
    }

    function dismissBanner() {
      document.getElementById('install-banner')?.remove();
    }
  </script>
</body>
</html>
```

---

## 4. `manifest.webmanifest`

```json
{
  "name": "{{APP_NAME}}",
  "short_name": "{{APP_SHORT_NAME}}",
  "start_url": "./index.html",
  "display": "standalone",
  "background_color": "#0a0a0c",
  "theme_color": "#0a0a0c",
  "icons": [
    { "src": "icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any maskable" }
  ]
}
```

---

## 5. `sw.js` — offline cache (only takes effect once HTTPS-hosted)

```javascript
const CACHE_NAME = '{{APP_SLUG}}-v1';
const ASSETS = [
  './',
  './index.html',
  './app.js',
  './styles.css',
  './manifest.webmanifest',
  './icon-180.png',
  './icon-192.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))))
  );
  self.clients.claim();
});

// Stale-while-revalidate: serve from cache instantly, refresh in the background.
self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request).then((cached) => {
      const fetchPromise = fetch(event.request).then((res) => {
        if (res && res.status === 200) {
          const clone = res.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return res;
      }).catch(() => cached);
      return cached || fetchPromise;
    })
  );
});
```

---

## 6. Local storage (`app.js`) — `IndexedDB`

```javascript
class LocalStorageDB {
  constructor(dbName = '{{APP_SLUG}}_db', storeName = 'records') {
    this.dbName = dbName;
    this.storeName = storeName;
    this.db = null;
  }

  async init() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(this.dbName, 1);
      request.onupgradeneeded = (e) => {
        const db = e.target.result;
        if (!db.objectStoreNames.contains(this.storeName)) {
          db.createObjectStore(this.storeName, { keyPath: 'id' });
        }
      };
      request.onsuccess = (e) => { this.db = e.target.result; resolve(this); };
      request.onerror = (e) => reject(e.target.error);
    });
  }

  async getAll() {
    return new Promise((resolve) => {
      const store = this.db.transaction(this.storeName, 'readonly').objectStore(this.storeName);
      const req = store.getAll();
      req.onsuccess = () => resolve(req.result || []);
    });
  }

  async put(item) {
    return new Promise((resolve) => {
      const tx = this.db.transaction(this.storeName, 'readwrite');
      tx.objectStore(this.storeName).put(item);
      tx.oncomplete = () => resolve(item);
    });
  }

  async delete(id) {
    return new Promise((resolve) => {
      const tx = this.db.transaction(this.storeName, 'readwrite');
      tx.objectStore(this.storeName).delete(id);
      tx.oncomplete = () => resolve();
    });
  }
}
```

For larger or binary data (files, media, a whole SQLite database in the browser), use the
Origin Private File System (`navigator.storage.getDirectory()`) or a WASM SQLite build
instead of `IndexedDB` — same local-only guarantee, better fit for anything file-shaped.

---

## 7. Publish

```sh
mesh apps publish <app-dir> --slug {{APP_SLUG}} --name "{{APP_NAME}}"
```

This copies `<app-dir>` to `~/.mesh/apps/{{APP_SLUG}}/site/` and prints a URL like:

```
http://192.168.1.23:8899/a/{{APP_SLUG}}-a1b2c3d4/
```

Open that in Safari on the phone (same Wi-Fi as the Mac), then long-press the address bar
→ **Share → Add to Home
Screen**. The random suffix in the path is the only thing standing in for auth on this
route — the page is served without a bearer token because a browser page load cannot set
an `Authorization` header, so don't publish anything containing a real secret.

### Optional: your own HTTPS host, for real offline

If the user wants the app to work with the Mac off — hand them one of these. All three are
free static hosts, and each is one command once the CLI is installed and logged in:

```sh
# GitHub Pages (needs a GitHub repo)
gh repo create <name> --public --source=<app-dir> --push
# then enable Pages for that repo (Settings -> Pages -> deploy from branch)

# Cloudflare Pages
npx wrangler pages deploy <app-dir> --project-name <name>

# Vercel
npx vercel deploy <app-dir> --prod
```

Whichever they pick, re-publish the same `<app-dir>` there — the service worker will
register for real on that origin, and the app becomes installable and offline-capable
independent of this Mac.

---

## 8. Completion signal

Once `mesh apps publish` has actually run and printed a URL (not just "the files are
written" — verify by actually running the command and reading its output), emit this
exact line on its own line:

```html
<!-- PWA_READY slug="{{APP_SLUG}}" name="{{APP_NAME}}" url="<the printed url>" -->
```

followed by:
1. What the app does, in one or two sentences.
2. The exact URL to open on the phone.
3. Share → Add to Home Screen, and — only if it was actually deployed to the user's own
   HTTPS host per §7 — that it also works offline.
