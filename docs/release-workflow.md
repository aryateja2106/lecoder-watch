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

## Every release

Either the script (needs the issuer id explicitly):

```bash
ASC_KEY_ID=Y4MR7X24UL ASC_ISSUER_ID=<uuid> sh scripts/release-testflight.sh
```

or `asc`, which already holds the credentials in the keychain and needs no issuer id:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
asc publish testflight --app 6803438426 --project MeshWatch.xcodeproj --scheme MeshWatch \
  --version 0.1.0 --build-number "$(date +%Y%m%d%H%M)" --configuration Release \
  --upload-only --wait --output json
```

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
- First build: **0.1.0 (202608201519)**, processingState VALID

## Gotchas already paid for

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
