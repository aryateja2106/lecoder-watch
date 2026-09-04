# Local-first ADE: two routes from a prompt to an app on your phone

An agent working through `mesh` — Claude Code, Codex, Cursor, or anything else pointed at
this Mac — can end a coding session with a real app on the user's iPhone, home screen icon
and all, without a cloud build service and without the user creating any new account. This
document is the architecture; `install/payload/share/skills/native-app-builder/SKILL.md`
and `install/payload/share/skills/pwa-local-app-builder/SKILL.md` are the two skills that
implement it, and `install/payload/share/skills/apple-native-apis/SKILL.md` is the
framework reference an agent reaches for while writing the app itself.

---

## The core idea

This Mac is the build machine. Nothing here is a hosted CI service or a cloud build
pipeline — `xcodebuild` and a static file server both run locally, and the only thing that
ever leaves the Mac is whatever the app itself does over the network (nothing, for a
purely local-first app).

## Two routes

```
                            User prompt
                  ("Build a habit tracker...")
                                │
                                ▼
                       Agent (Claude Code / Codex / Cursor / ...)
                                │
          ┌─────────────────────┴─────────────────────┐
          ▼                                            ▼
       Route 1                                      Route 2
 [has an Apple Developer account]           [no developer account, or wants it now]
          │                                            │
  XcodeGen (project.yml)                     Static site: index.html, app.js,
  xcodebuild (debug, no archive)             styles.css, manifest.webmanifest
  mesh apps add <slug>  (also packages .ipa)  IndexedDB / OPFS for local data
  mesh apps install <slug>                   mesh apps publish <dir> --slug S --name N
  (devicectl to a paired iPhone,                       │
   or simctl to a simulator), or                        │
  Install on the phone → itms-services://               │
  (mesh apps ota --enable: Tailscale HTTPS)             ▼
          │                                   http://<mac-lan-ip>:8899/a/<slug>-<key>/
          ▼                                   Safari → Share → Add to Home Screen
   App on the device's home screen
```

### Route 1: native (Apple Developer account)

`native-app-builder` scaffolds a SwiftUI app with XcodeGen, builds it with `xcodebuild
-configuration Debug -destination 'generic/platform=iOS' ... -allowProvisioningUpdates
-allowProvisioningDeviceRegistration` (no archive, no export — that pipeline is for
TestFlight, not "put this on my phone"), registers the built `.app` with `mesh apps add`,
and installs it with `mesh apps install`.

Installing has two routes from the same build. Local: `xcrun devicectl device install
app` against a paired, currently-connected iPhone, or `xcrun simctl install booted`
against a simulator with `--sim` — the phone on the same network or a USB cable, exactly
like running an app from Xcode does. Wireless: Apple's own `itms-services://` installer,
which needs only a manifest and the `.ipa` on HTTPS with a public certificate. `mesh apps
add` packages every device build as an `.ipa`; `mesh apps ota --enable` maps `/a/` of the
machine's Tailscale name (`https://<machine>.<tailnet>.ts.net`, a real Let's Encrypt
certificate, reachable only from the tailnet) onto meshd's `/a/`; the phone's Install
button then hands iOS the link and iOS does the rest — from the office, from the road, no
cable, nobody at the Mac. The device must be in the signing profile (the one-time Xcode
pairing) and have Developer Mode on. `mesh apps ota --url https://…` if you already
terminate HTTPS in front of the machine with something else (Caddy, cloudflared).

### What a Linux machine can and cannot do

Serving is the same everywhere: meshd on a Linux VPS serves `/a/…` exactly as on a Mac, and
`tailscale serve` works there too (`tailscale cert` uses a DNS challenge, so the box needs
no open ports). Compiling is not: a native iOS build needs Xcode, so a Linux machine takes
an `.ipa` a Mac in the mesh built — `mesh apps add <slug> --ipa app.ipa --bundle-id … --name
… --app-version …` — and serves it. Since the phone installs from whichever machine holds
the `.ipa`, in practice the Mac that built it just serves it; the Linux route exists for a
mesh whose always-on machine is a VPS. Web apps (Route 2) need no Mac at all and are the
route for a Linux-only mesh. Building iOS apps *on* Linux is what
[xtool](https://github.com/xtool-org/xtool) sets out to do (SwiftPM, user-supplied
Xcode.xip for the SDK, signs with an Apple Developer account); it is not wired in here and
has not been proven on this project — a candidate, not a route.

One-time requirements, told to the user honestly rather than assumed: an Apple Developer
account (free tier works — no paid membership needed to run a debug build on your own
phone), the phone's Developer Mode turned on, and the phone paired with this Mac at least
once in Xcode → Devices and Simulators.

Team ID and bundle-id prefix are never hardcoded anywhere in the skill or the generated
`project.yml` — they come from `mesh apps config --team <ID> --prefix <com.example>`
(stored in `~/.mesh/apps.json`, mode 600), or the skill asks the user for them the first
time.

### Route 2: PWA (no developer account required)

`pwa-local-app-builder` writes a plain static site — no build step, no framework required
— with the iOS PWA meta tags Safari needs (`apple-mobile-web-app-capable`,
`apple-touch-icon`, `viewport-fit=cover`) and an in-app banner walking the user through
Share → Add to Home Screen. Data is local-only, in `IndexedDB` (or the Origin Private File
System / a WASM SQLite build for larger or binary data) — nothing is sent anywhere.

`mesh apps publish <dir> --slug <slug> --name "<Name>"` copies the site to
`~/.mesh/apps/<slug>/site/` and prints the URL the daemon serves it at:
`http://<mac-lan-ip>:8899/a/<slug>-<key>/`. The random suffix in the path is what stands
in for authentication on that one route — a browser page load cannot set an
`Authorization` header, so the daemon serves this specific path without a bearer token,
and the skill is explicit that nothing containing a real secret should be published there.

**The honest part: offline.** A Service Worker — the mechanism that lets a PWA open with
zero network at all — only ever registers on a page served over HTTPS or `localhost`. The
LAN URL `mesh apps publish` prints is plain HTTP on neither, so:

- The app **works** any time the Mac is on, awake, and reachable on the same network —
  which covers the common "an app I use around the house" case fine.
- The app does **not** work with the Mac off or unreachable, and does not get a true
  offline cache, because the service worker never registers on plain HTTP.
- **Offline-anywhere** needs the app hosted on HTTPS the user actually owns. The skill
  gives one-command options for that as an optional next step — GitHub Pages, Cloudflare
  Pages (`wrangler pages deploy`), or Vercel — all free static hosts, none requiring a
  purchase or an account tied to this tool.

Do not claim "works offline" for a plain LAN-published app. It doesn't, and the reason is
a real browser security boundary, not a bug to route around.

---

## The completion signal

Both skills end a successful run with an HTML comment on its own line, which a client
watching the agent's output parses into an install/open card:

```html
<!-- APP_READY slug="<slug>" name="<Display Name>" -->
<!-- PWA_READY slug="<slug>" name="<Display Name>" url="<the printed url>" -->
```

Emit it only after the underlying `mesh apps install` / `mesh apps publish` call has
actually succeeded — not after the build merely compiled. See `AGENTS.md`'s rule about
verifying by running: a feature that compiles green and is never actually exercised is
indistinguishable, from a transcript, from one that works.

---

## The one daemon underneath both routes

Everything above eventually talks to `meshd`, the one control-plane daemon on this Mac
(default port 8899, documented in full in `AGENTS.md` under "The daemon API, in one
place"). Every route except `GET /health` and the served PWA paths requires
`Authorization: Bearer <token>`; the token lives in `~/.mesh/token` on the Mac and the
Keychain on a paired phone or watch. There is no `localhost:7777` daemon anywhere in this
codebase — if a piece of sample code or documentation ever names that port, it is wrong
and should be fixed, not copied.
