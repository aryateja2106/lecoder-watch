---
name: native-app-builder
description: Autonomous native Apple app builder for Route 1 (users with an Apple Developer account). Scaffolds SwiftUI apps with XcodeGen, builds a debug .app with xcodebuild, installs it straight to a paired iPhone (devicectl) or a simulator (simctl), and emits the APP_READY signal. No hardcoded team or bundle prefix — both come from `mesh apps config`.
---

# Route 1: Native Apple App Builder (paired iPhone or simulator)

Use this skill when a user wants a real native iOS app — not a web app — and has (or is
willing to get) a free or paid Apple Developer account. It is for a working app on a
device today, not a store submission: no archive, no export, no TestFlight upload unless
the user explicitly asks for one.

---

## Before this skill: the brief

Do not start here from a bare "build me an app". Run the `app-brief` skill first: it asks
the few questions that decide the design, records the user's preferences, and picks native
or web on purpose. Come here only when the brief chose **native**. Build one app, once —
never a web app "as well", never background jobs or parallel workers the user cannot see
from a phone, never a test loop left running.

## 0. Before anything: get the Team ID and bundle prefix

Never hardcode a Development Team or a bundle prefix. Run this first:

```sh
mesh apps config
```

- If it prints a Team ID and a prefix, use them.
- If either is unset, ask the user for it (an Apple Developer Team ID is a 10-character
  alphanumeric string, found at developer.apple.com/account under Membership — a free
  account has one too), then save it so future builds don't ask again:
  ```sh
  mesh apps config --team <TEAMID> --prefix <com.example>
  ```

Everything below assumes `$TEAM` and `$PREFIX` are these two values, and `$SLUG` is a
short lowercase-hyphen name for the app (`^[a-z0-9][a-z0-9-]{1,40}$` — same rule `mesh
apps` enforces).

---

## 1. One-time requirements (tell the user honestly if any are missing)

- An Apple Developer account (free tier is enough for on-device installs; no paid
  membership required for what this skill does).
- The target iPhone has Developer Mode turned on (Settings → Privacy & Security →
  Developer Mode) and has been paired with this Mac at least once in Xcode → Devices and
  Simulators (a "Trust This Computer" prompt on the phone the first time).
  Alternative: skip the phone and build straight to a Simulator with `--sim` — no developer
  account requirement at all in that case, and no signing step.
- For the cable/Wi-Fi route: the phone on the same Wi-Fi as the Mac, or a USB cable.
- For the wireless route (install from anywhere, no cable, no Mac in front of the user):
  the Mac on the user's Tailscale tailnet with `mesh apps ota --enable` run once (it
  prints the HTTPS name it serves from). Check with `mesh apps ota` — "on" or "off" is the
  whole answer. If it is off and `tailscale` is installed, run `mesh apps ota --enable`;
  if it is off and there is no Tailscale, say so and use the cable/Wi-Fi route.

Both routes start from the same device build. The wireless one is Apple's own
`itms-services://` installer: `mesh apps add` packages the device build as an `.ipa`, meshd
serves the manifest at `/a/<slug>-<key>/manifest.plist` over the Tailscale HTTPS name, and
the phone's Install button hands that link to iOS. The device must already be in the
signing profile — which is what the one-time Xcode pairing does — and have Developer
Mode on.

---

## 2. Scaffold with XcodeGen

Write a `project.yml` next to the app's source. Keep it minimal — one target, SwiftUI,
iOS 17+:

```yaml
name: {{APP_NAME}}
options:
  bundleIdPrefix: {{PREFIX}}
  deploymentTarget:
    iOS: "17.0"
settings:
  base:
    DEVELOPMENT_TEAM: "{{TEAM}}"
    CODE_SIGN_STYLE: Automatic
    SWIFT_VERSION: "5.0"
targets:
  {{APP_NAME}}:
    type: application
    platform: iOS
    sources:
      - path: Sources
    info:
      path: Info.plist
      properties:
        CFBundleDisplayName: "{{APP_NAME}}"
        CFBundleShortVersionString: "1.0"
        CFBundleVersion: "1"
        UILaunchScreen: {}
```

`bundleIdPrefix` + the target name gives the full bundle id
(`{{PREFIX}}.{{APP_NAME}}`, lowercased as XcodeGen requires) — don't also hardcode
`CFBundleIdentifier` unless the app needs a bundle id that differs from its target name.

Write the SwiftUI source under `Sources/`. See the `apple-native-apis` skill for the
frameworks available (Live Activities, widgets, notifications, Siri, WatchConnectivity)
and this app's own code for working examples.

```sh
xcodegen generate
```

---

## 3. Build (debug, no archive, no export)

A debug build with automatic signing is all that's needed to run on a paired device or a
simulator — skip `xcodebuild archive` and export entirely, that pipeline exists for
TestFlight/App Store, not for "put this on my phone":

```sh
xcodebuild \
  -scheme "{{APP_NAME}}" \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM={{TEAM}} \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build
```

`-allowProvisioningDeviceRegistration` registers a connected device on the account
automatically if it isn't already — needed the first time a new phone is used with a free
account's auto-generated provisioning profile.

The built app lands at:

```
build/Build/Products/Debug-iphoneos/{{APP_NAME}}.app
```

If the build fails on signing, the most common cause is a Team ID that doesn't match an
account actually signed into Xcode on this Mac — check with `security find-identity -v
-p codesigning`, or open Xcode once and sign in under Settings → Accounts.

---

## 4. Register the app with mesh

```sh
mesh apps add {{SLUG}} --name "{{APP_NAME}}" \
  --app build/Build/Products/Debug-iphoneos/{{APP_NAME}}.app \
  --bundle-id {{PREFIX}}.{{APP_NAME}}
```

This remembers the path and metadata under `~/.mesh/apps/{{SLUG}}/` and, because it is a
device build, also packages it as `{{SLUG}}.ipa` there for the wireless route. Re-running
it after a rebuild keeps the same install link. When wireless install is on, the command
prints the link (`install wirelessly: https://…/a/{{SLUG}}-<key>/`); include that link in
your final message.

---

## 5. Install it

Wireless install on (`mesh apps ota` says "on"): you are done after step 4 — the phone's
Apps screen (and the card your APP_READY line produces) shows Install, and iOS installs
it from the link. Say so; do not also push it over a cable. Verify by fetching the
manifest yourself:

```sh
curl -sf "$(mesh apps ota --json | sed -n 's/.*"otaBase":"\([^"]*\)".*/\1/p')/a/{{SLUG}}-$(sed -n 's/.*"key": "\([0-9a-f]*\)".*/\1/p' ~/.mesh/apps/{{SLUG}}/meta.json)/manifest.plist" | plutil -lint -s -
```

Wireless install off: push it from this Mac —

```sh
mesh apps install {{SLUG}}
```

This finds the first paired, connected iPhone and runs `xcrun devicectl device install
app` against it. To target a simulator instead (no device, no signing headaches, good for
a quick look):

```sh
mesh apps install {{SLUG}} --sim
```

(runs `xcrun simctl install booted` against whatever simulator is currently booted). To
pick a specific device when more than one is paired:

```sh
mesh apps install {{SLUG}} --device <udid>
```

(`udid` from Xcode → Devices and Simulators, or `xcrun devicectl list devices`).

---

## 6. TestFlight / App Store — only if asked

Nothing above uploads anywhere. If the user explicitly asks for TestFlight or an App
Store submission, that is a different, heavier pipeline (archive, export, `asc` upload,
Beta App Review) — this skill does not do it automatically. Ask before spending the time,
and check whether this repo already has a release script (`scripts/release-testflight.sh`
in LeSearch Mesh itself, for example) before writing a new one.

---

## 6b. Definition of done — no iconless, nameless, blank apps

Every app this skill produces must have, before `mesh apps install`:

1. **An icon.** Run the bundled generator; pick a symbol and a color that fit the app:
   ```sh
   sh ~/.agents/skills/native-app-builder/scripts/make-appicon.sh Sources/Assets.xcassets checkmark.circle.fill 1FA463 0B6B3A
   ```
   Then make sure `project.yml` points the target at it (`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`).
2. **A display name** a person would say (`CFBundleDisplayName`), and a bundle id derived from
   it under the configured prefix.
3. **Empty states** that tell the user what to do first. No blank screens.
4. **Every must-have from the brief** built, or listed as skipped with the reason, in the
   completion message. Widgets and Live Activities come from the `apple-native-apis` skill.
5. **Tests run once**, green. If something fails, fix it and run once more; never leave a
   loop running.

## 7. Completion signal

Once the app is really installable — `mesh apps install` succeeded, or the wireless
manifest fetched and linted clean — (not just "the build compiled"; see AGENTS.md's rule
about verifying by running), emit this exact line on its own line:

```html
<!-- APP_READY slug="{{SLUG}}" name="{{APP_NAME}}" -->
```

followed by a 1–2 sentence summary of what the app does. A client watching for this marker
renders an install/open card from it — the sentinel has to be exact and on its own line,
not folded into a paragraph.
