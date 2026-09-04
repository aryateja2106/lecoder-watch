---
name: pwa-local-app-builder
description: Autonomous Progressive Web App (PWA) builder for Route 2 (users without an Apple Developer account). Builds standalone web apps using local browser storage (IndexedDB / OPFS / SQLite), offline service workers, and iOS Safari Add to Home Screen optimization with zero developer fees or signing requirements.
---

# Route 2: Autonomous Progressive Web App (PWA) Builder (Local-First Storage)

Use this skill when building applications for users who do not have an Apple Developer account, or when the user requests a local-first, zero-setup web application that can be installed directly onto their iPhone, iPad, Mac, or desktop Home Screen.

---

## 1. Value Proposition & Core Architecture

- **Zero Apple Fees / Zero Accounts:** Requires no Apple Developer Program enrollment, no provisioning profiles, and no certificates.
- **True App Experience:** Configured with iOS Safari standalone mode (`display: "standalone"`) to hide browser chrome and run full-screen from the home screen icon.
- **Local-First Data Ownership:** All data is stored directly on the user's device using `IndexedDB`, browser `localStorage`, or client-side `WASM SQLite` / Origin Private File System (OPFS).
- **100% Offline Capable:** A Service Worker (`sw.js`) caches all assets, styles, and logic so the app opens instantly even with no internet connection.

---

## 2. Directory Structure of a Generated PWA

```
~/.mesh/apps/<slug>/ (or ./apps/<slug>/)
├── index.html               # Main entrypoint with Apple PWA meta tags
├── app.js                   # Application logic + IndexedDB local storage layer
├── style.css                # Polished modern mobile UI styles
├── manifest.webmanifest     # PWA manifest (standalone, theme color, icons)
├── sw.js                    # Service worker for offline caching
├── icon-192.png             # Android / Desktop icon
└── icon-180.png             # Apple Touch Icon for iPhone / iPad Home Screen
```

---

## 3. Mandatory iOS PWA Meta Tags in `index.html`

In the `<head>` of `index.html`, include these essential tags for iOS home screen installation:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <title>{{APP_NAME}}</title>

  <!-- iOS Safari Standalone / Add to Home Screen Support -->
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="{{APP_NAME}}">
  <link rel="apple-touch-icon" href="icon-180.png">

  <!-- PWA Web Manifest -->
  <link rel="manifest" href="manifest.webmanifest">
  <meta name="theme-color" content="#0a0a0c">

  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div id="app"></div>

  <!-- In-app Add to Home Screen Guidance Banner (Shown if not yet added) -->
  <div id="install-banner" class="install-banner hidden">
    <div class="banner-content">
      <p>Install this app on your iPhone: tap <strong>Share</strong> <span class="share-icon">⎋</span> then <strong>Add to Home Screen</strong></p>
      <button onclick="dismissBanner()">Dismiss</button>
    </div>
  </div>

  <script src="app.js"></script>
  <script>
    // Register Service Worker
    if ('serviceWorker' in navigator) {
      window.addEventListener('load', () => {
        navigator.serviceWorker.register('sw.js');
      });
    }

    // Detect if already installed as standalone
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

## 4. `manifest.webmanifest` Template

```json
{
  "name": "{{APP_NAME}}",
  "short_name": "{{APP_SHORT_NAME}}",
  "start_url": "./index.html",
  "display": "standalone",
  "background_color": "#0a0a0c",
  "theme_color": "#0a0a0c",
  "icons": [
    {
      "src": "icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any maskable"
    }
  ]
}
```

---

## 5. Offline Service Worker (`sw.js`)

```javascript
const CACHE_NAME = '{{APP_SLUG}}-v1';
const ASSETS = [
  './',
  './index.html',
  './app.js',
  './style.css',
  './manifest.webmanifest',
  './icon-180.png',
  './icon-192.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Stale-while-revalidate strategy
self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      const fetchPromise = fetch(event.request).then((networkResponse) => {
        if (networkResponse && networkResponse.status === 200) {
          const clone = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return networkResponse;
      }).catch(() => cachedResponse);

      return cachedResponse || fetchPromise;
    })
  );
});
```

---

## 6. Local Browser Storage Engine (`IndexedDB`)

Provide persistent structured storage inside `app.js` using native `indexedDB`:

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
      request.onsuccess = (e) => {
        this.db = e.target.result;
        resolve(this);
      };
      request.onerror = (e) => reject(e.target.error);
    });
  }

  async getAll() {
    return new Promise((resolve) => {
      const tx = this.db.transaction(this.storeName, 'readonly');
      const store = tx.objectStore(this.storeName);
      const req = store.getAll();
      req.onsuccess = () => resolve(req.result || []);
    });
  }

  async put(item) {
    return new Promise((resolve) => {
      const tx = this.db.transaction(this.storeName, 'readwrite');
      const store = tx.objectStore(this.storeName);
      store.put(item);
      tx.oncomplete = () => resolve(item);
    });
  }

  async delete(id) {
    return new Promise((resolve) => {
      const tx = this.db.transaction(this.storeName, 'readwrite');
      const store = tx.objectStore(this.storeName);
      store.delete(id);
      tx.oncomplete = () => resolve();
    });
  }
}
```

---

## 7. Mandatory Completion Signal

When the PWA files are generated and tested locally, the agent MUST emit this exact HTML comment on its own line:

```html
<!-- PWA_READY slug="<app-slug>" name="<Display Name>" url="http://localhost:7777/apps/<app-slug>/" -->
```

Followed by a brief explanation:
1. What the app does.
2. How to preview it immediately.
3. How to add it to the iPhone Home Screen (Share -> Add to Home Screen).
