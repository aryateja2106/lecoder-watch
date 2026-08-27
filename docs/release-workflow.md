# Shipping to TestFlight / App Store

The repeatable path for this app and the next one. Tooling: [`asc`](https://github.com/rorkai/App-Store-Connect-CLI)
(`brew upgrade asc`, currently 4.6.0) plus `scripts/release-testflight.sh`.

## Why not sideload

A development-signed build re-verifies its certificate with Apple on every fresh
install — that is the **"Unable to Verify App"** dead end where the app never launches —
and each re-sign makes iOS treat it as a new app identity and **reset its privacy
grants**, including Local Network. Without Local Network nothing on a `100.64/10`
tailnet is reachable, so the app looks like every machine is offline. TestFlight builds
are Apple-signed: neither happens, and other people can install them.

## One-time: the App Store Connect API key

You do **not** need a new key for this project — `Y4MR7X24UL` already works and is
stored in the keychain (`asc auth status`). These are the steps for a future one.

1. App Store Connect → **Users and Access** → **Integrations** → **App Store Connect
   API** → **Team Keys**.
2. **⊕** → name it after the machine that will hold it (e.g. `macbook-ci`).
3. **Access role**: pick the least that works.
   - **Developer** — read-only for most things. Not enough.
   - **App Manager** — enough for everything here: bundle IDs, capabilities,
     certificates, profiles, TestFlight, uploading builds. **Use this.**
   - **Admin** — only if you also need to manage users or agreements.
4. **Download the `.p8` once.** Apple never shows it again. Note the **Key ID** and the
   **Issuer ID** (the UUID at the top of the page — one per team, shared by all keys).
5. Register it:
   ```bash
   asc auth login --name "macbook-ci" --key-id <KEYID> --issuer-id <UUID> \
     --private-key ~/Downloads/AuthKey_<KEYID>.p8 --network
   asc doctor
   ```
   `--network` makes it prove the credentials against the API instead of only checking
   the JWT locally. Credentials go to the system keychain, so the `.p8` can then be
   moved into the vault and deleted from Downloads.

Keys are per **team**, not per app. One key ships every app on the team.

## Per app, once

1. **Bundle IDs** — one per target. A watch app needs its own.
   ```bash
   asc bundle-ids create --identifier com.example.app            --name "Example" --platform UNIVERSAL
   asc bundle-ids create --identifier com.example.app.watchkitapp --name "Example Watch" --platform UNIVERSAL
   ```
2. **Capabilities** — the API will not infer them from your entitlements, and a
   wildcard App ID **cannot** hold `aps-environment` at all.
   ```bash
   asc bundle-ids list                       # find the internal id
   asc bundle-ids capabilities add --bundle <ID> --capability PUSH_NOTIFICATIONS
   asc bundle-ids capabilities list --bundle <ID>
   ```
3. **App record** — Apple's API cannot create these; it needs a web session with your
   Apple ID and 2FA. Either use App Store Connect → Apps → **＋** → New App, or:
   ```bash
   asc web auth login --apple-id you@example.com     # prompts for password + 2FA
   asc web apps create --name "Example" --bundle-id com.example.app --sku EXAMPLE001
   ```
   The App Store **name is globally unique and reserving it takes it out of
   circulation** — do not spend a name you want for a different product.

## Every release — use the script

```bash
sh scripts/release-testflight-asc.sh              # ship to yourself + internal testers
```

```bash
sh scripts/release-testflight-asc.sh --external   # …and to the public link, via Beta App Review
```

`--dry-run` prints what it would do and touches nothing. It regenerates the project, runs
`check-all.sh`, archives Release, uploads, **adds the build to a group**, and writes
*What to Test* from `CHANGELOG.md`'s Unreleased block.

### The trap the script exists to remove

**`--upload-only` leaves the build in no group at all.** It processes, goes `VALID`, and is
installable by *nobody* — not external testers, not internal ones, not you. Every list view
shows a healthy build. This is the whole answer to "I can't find the update in TestFlight":
on 2026-08-27 build `202608270920` was uploaded and valid and sitting in zero groups.

A build only reaches people once it is **added to a group**, and the two kinds differ:

| Group | Who | Gate |
|---|---|---|
| **Internal** | App Store Connect team members, ≤100 | none — installable as soon as processing ends |
| **External** (the public link) | anyone with the link | **Beta App Review** |

`externalBuildState: READY_FOR_BETA_SUBMISSION` means uploaded, processed, valid, and
reaching nobody. `IN_BETA_TESTING` is the one that means your friends have it.

### Checking, rather than assuming

```bash
asc testflight distribution view --build-id "$BUILD_ID"
```

```bash
asc testflight groups links view --group-id "$GROUP_ID" --type builds
```

**`asc builds groups list --build-id` is marked experimental and reported zero groups for a
build that was demonstrably in one.** Use `groups links view` above; it is authoritative.

Other things that are true and not obvious:

- `asc testflight review submit --build-id <ID> --confirm` submits for Beta App Review from
  the command line. The web UI is not required.
- `asc publish testflight --build <ID> --group <ID>` distributes a build **that already
  exists** — no rebuild, no re-upload. This is how you fix a build that went up in no group.
- Build numbers must be unique forever; the scripts use a UTC `YYYYMMDDHHMM` stamp.
- **Never let the marketing version go backwards.** App Store Connect allows it and iOS
  punishes it: a tester on a higher version reads the new build as older and may be asked
  to delete and reinstall, which wipes the Keychain and un-pairs every machine they had
  added. The script warns when it detects this. See [updating.md](updating.md).

### The older paths

The `xcodebuild` script (needs the issuer id explicitly):

```bash
ASC_KEY_ID=Y4MR7X24UL ASC_ISSUER_ID=<uuid> sh scripts/release-testflight.sh
```

or `asc`, which already holds the credentials in the keychain and needs no issuer id:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer asc publish testflight --app 6803438426 --project MeshWatch.xcodeproj --scheme MeshWatch --version 0.2.0 --build-number "$(date +%Y%m%d%H%M)" --configuration Release --upload-only --wait --output json
```

`asc` holds the issuer id in the keychain and never prints it, so `xcodebuild` invoked
directly cannot use `-authenticationKeyPath` (it demands `-authenticationKeyIssuerID`
alongside). Plain `-allowProvisioningUpdates` works instead — Xcode's signed-in account
covers it — which is what `scripts/release-testflight.sh` and the probe archives use.

Which runs the self-checks, archives Release, and exports straight to App Store
Connect. Build numbers are a UTC timestamp because App Store Connect refuses a reused
one. The watch app is embedded in the iOS app, so **one upload ships both**.

Then:

```bash
asc builds list --app <APP_ID>          # processing takes ~5-15 min
asc testflight groups list --app <APP_ID>
```

- **Internal testers** (anyone on your team, up to 100) install immediately, no review.
  This is the fast path.
- **External testers** (friends) need a one-time **Beta App Review**. Expect questions
  for this app in particular: it injects keystrokes into a computer and sets
  `NSAllowsArbitraryLoads`. Have an explanation ready — it talks only to daemons the
  user installs on their own machines over their own Tailscale network.

## This app

- App Store Connect app id **6803438426** (`LeSearch Mesh`, `com.lecoder.meshwatch`)
- Internal TestFlight group **f0b2cc09-9776-409c-865a-4706e881bccd**
- Bundle IDs: app `com.lecoder.meshwatch` · watch `…watchkitapp` ·
  iOS widget `…widgets` · watch complication `…watchkitapp.glance`
- App Group `group.com.lecoder.meshwatch` — Xcode creates and assigns it itself once
  `APP_GROUPS` is on both watch bundle IDs; there is no `asc` command for it.
- Release notes come from the top section of `CHANGELOG.md`.

## Gotchas already paid for

- **Every app extension needs `CFBundleDisplayName` in its Info.plist** or processing
  fails with **90360**, once per extension. `INFOPLIST_KEY_CFBundleDisplayName` does
  *not* supply it here: that build setting is only read when `GENERATE_INFOPLIST_FILE`
  is `YES`, and this project sets it to `NO` project-wide. Put the key in the plist.
- **A deleted App ID cannot be reused.** Apple answers "An App ID with Identifier … is
  not available", which reads like someone else took it. Pick a different suffix.
- **The APNs environment comes from the provisioning profile, not the build config.**
  TestFlight and App Store builds are signed `aps-environment = production`; a token
  from one of those is rejected by the sandbox gateway with `BadDeviceToken`. The app
  reads its own embedded profile (`Shared/APNsEnvironment.swift`) rather than guessing.

- **Two Xcodes, and using the wrong one wastes a build number.**
  - *Installing to the devices* needs **Xcode 27 beta** — they run iOS/watchOS 27 and
    26.6 only has the 26.5 SDK.
  - *Uploading to App Store Connect* needs the **stable Xcode**. A beta-built upload is
    accepted and then fails processing with **90534 Unsupported SDK or Xcode version**.
    Verified both ways.
- **iPad in `TARGETED_DEVICE_FAMILY` demands all four orientations** or processing fails
  with **90474**. A portrait-only phone app should declare `"1"`, not `"1,2"`.
- **Declare `ITSAppUsesNonExemptEncryption`** in the Info.plist or every build stops and
  asks about export compliance before testers can install.
- **`xcodebuild` must be told the API key** for automatic signing to create
  distribution certificates and profiles: `-allowProvisioningUpdates`
  `-authenticationKeyPath` `-authenticationKeyID` `-authenticationKeyIssuerID`.
- **Info.plist must reference `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`**
  or every archive stamps `1.0 (1)` and the second upload is rejected as a duplicate.
- **A clean build is what makes Xcode create an explicit App ID.** With a cached
  wildcard profile it silently drops entitlements it cannot satisfy — `aps-environment`
  vanishes and push fails with no error. Check with
  `codesign -d --entitlements :- path/to/App.app`.
