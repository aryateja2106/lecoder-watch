# Shipping to TestFlight / App Store

The repeatable path for this app and the next one. Tooling: [`asc`](https://github.com/rorkai/App-Store-Connect-CLI)
(`brew upgrade asc`, currently 4.9.4) plus **`scripts/release-testflight-asc.sh`**, which is
the only supported way to put a build in front of anyone.

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
`check-all.sh` (which includes the smoke test that launches the app), archives Release,
uploads, **adds the build to a group and then proves it is in that group**, and writes
*What to Test* from `CHANGELOG.md`'s Unreleased block.

### The four gates, and the four escape hatches

Each gate is here because something already shipped past its absence. Each hatch exists so a
deliberate exception is possible, and each is deliberately awkward enough to be a decision
rather than a reflex. **None of them should appear in a script or an alias.**

| Gate | What stops the release | Hatch |
|---|---|---|
| **Clean tree** | `git status --porcelain` is non-empty | `MESH_ALLOW_DIRTY=1` |
| **No version downgrade** | App Store Connect already holds a *higher* marketing version | `MESH_ALLOW_VERSION_DOWNGRADE=1` |
| **Version check ran at all** | App Store Connect would not answer within 90s | `MESH_SKIP_VERSION_CHECK=1` |
| **The app launches** | `check-ios-smoke.sh` failed **or skipped** | none — release from a machine with a current Xcode |

- **Clean tree.** An uncommitted tree means the binary testers install was built from source
  that exists on one laptop: no diff to read, no revert to make, and no way to tell whether
  a fix you are looking at is even in the build people have.
- **No version downgrade.** This one used to print `WARNING` and upload anyway. That is
  precisely how the 1.0 → 0.5.0 rename went out: the script *saw* the downgrade, said so,
  and shipped it — and a warning inside a hundred lines of release output is a thing nobody
  reads. Every tester had to delete and reinstall, which wipes the Keychain, which un-paired
  every machine they had added. There is no undo. It is now `exit 1`.
- **The app launches.** The script exports `MESH_SMOKE_REQUIRED=1` for its check run, so
  `check-ios-smoke.sh` cannot report "no simulator here" as exit 0 the way it may on a
  laptop. There is intentionally no hatch: a release that has not launched the app is the
  thing that produced 0.5.0.

The smoke test runs **once**, inside `check-all.sh`. The script used to also invoke it
separately, which meant two `xcodebuild test` runs against the same simulator; the second
gets its runner killed before it connects and is reported `INCONCLUSIVE` (exit 1). A release
that fails on its own duplicate gate teaches you to re-run until it passes, which is how a
real failure gets waved through. Do not add the second invocation back.

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

**The script now runs that query itself and fails on the answer.** `asc publish testflight
--group` exits 0 whether or not the build landed in the group, so after each distribution
`release-testflight-asc.sh` asks the *group* what builds it holds and refuses to call the
release finished unless this build id is in the reply — including an unreadable reply, which
is unproven, not fine. This replaced a best-effort `|| true` state print. The zero-group
trap has caught this project twice, and both times the first report came from a person
saying "I can't find the update", days later.

**Run without `--external` and the script ends with a loud banner** naming the build the
public link is still serving, because an internal-only release leaves that link exactly
where it was and every list view will keep showing the newest build as healthy regardless.

Other things that are true and not obvious:

- `asc testflight review submit --build-id <ID> --confirm` submits for Beta App Review from
  the command line. The web UI is not required.
- `asc publish testflight --build <ID> --group <ID>` distributes a build **that already
  exists** — no rebuild, no re-upload. This is how you fix a build that went up in no group.
- Build numbers must be unique forever; the scripts use a UTC `YYYYMMDDHHMM` stamp.
- **Never let the marketing version go backwards.** App Store Connect allows it and iOS
  punishes it: a tester on a higher version reads the new build as older and may be asked
  to delete and reinstall, which wipes the Keychain and un-pairs every machine they had
  added. The script **stops** when it detects this (it used to only warn — see the gate
  table above). See [updating.md](updating.md).
- **The published links are checked too.** `scripts/check-links.sh` fetches the install
  one-liner and the TestFlight join link — plus every `install`/`testflight.apple.com` URL
  in `README.md` and `docs/updating.md`, so new ones are covered without anyone remembering
  — and fails on anything that is not 2xx/3xx. It skips when the machine is offline, unless
  `MESH_LINKS_REQUIRED=1` (which CI sets) makes offline a failure. `mesh.lesearch.ai` once
  had no DNS at all while the README kept telling people to `curl` it.

### The build must survive being launched

`scripts/release-testflight-asc.sh` will not upload a build that cannot open. It runs
`scripts/check-ios-smoke.sh`, which installs the app on a simulator, visits every tab and
opens the pairing sheet.

This exists because 0.5.0 shipped an app that closed itself on every screen containing a
text box, and **every check in `scripts/` was green** while it did. The cause was
`UITextField.appearance().smartQuotesType = .no` — iOS replays a stored appearance
instruction onto each text field as it appears, and replaying an input-trait setter
throws. Nothing that reads source code can see that; the check meant to guard the area
was grepping for that exact line and *requiring* it.

The rule that follows: **a check that greps for a mechanism proves intent, not
behaviour.** Anything that can only fail at runtime needs something that runs.

Run by hand it still exits 0 with a SKIP when the machine has no iOS 26+ simulator — a
laptop that cannot test this reports "not covered here", never a false green. **In every
place where the green tick is read as "the app was launched", that skip is a failure
instead**: `MESH_SMOKE_REQUIRED=1` is set by the release script and by CI's `apps` job. On
success the check prints the simulator name and runtime it ran on.

### The older paths (retired — do not use)

**`scripts/release-testflight.sh` is a shim.** It prints why it was retired and `exec`s
`release-testflight-asc.sh` with the same arguments, so the name still works and lands on
the gated path. What it used to do had **no group assignment** (the zero-group trap in its
purest form — the build reached nobody), **no version check** (the 1.0 → 0.5.0 downgrade
that un-paired every tester), and **no smoke test** (0.5.0 shipped unlaunchable). Three
holes in a second implementation of the same job was not worth fixing twice; deleting the
file would have sent muscle memory and older runbooks to "No such file", which teaches
nothing.

**Never upload with `--upload-only` by hand.** That flag is what puts a build in zero
groups: it processes, goes `VALID`, and is installable by nobody while every list view shows
it healthy. `release-testflight-asc.sh` uses it *internally* and then immediately adds the
build to a group and verifies the membership — the flag is only safe as one half of that
pair. A raw `asc publish testflight … --upload-only` used to be documented here as an
alternative path; it is not one, and it is the single command most likely to produce a
release nobody can install.

Two facts worth keeping from that era: `asc` holds the issuer id in the keychain and never
prints it, so `xcodebuild` invoked directly cannot use `-authenticationKeyPath` (it demands
`-authenticationKeyIssuerID` alongside) — plain `-allowProvisioningUpdates` works instead,
covered by Xcode's signed-in account, which is what probe archives use. And the watch app is
embedded in the iOS app, so **one upload ships both**.

To inspect state:

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

### Upgrading `asc` makes every release hang until you click a Keychain dialog

`brew upgrade asc` gives the binary a new code signature, and that **invalidates the
macOS Keychain ACL** on the stored API key. Every `asc` call that decrypts the key then
raises *"asc wants to use your confidential information stored in ... in your keychain"*.

In an interactive terminal you click it and move on. In a non-interactive one — a script,
CI, an agent session — nothing can answer, and the command hangs **forever** with no
output and no error.

Measured 2026-08-27: `asc` went 4.6.0 → 4.9.4 at 16:17; releases started hanging at 16:20.
It looked exactly like App Store Connect being down. It was not — `curl
https://api.appstoreconnect.apple.com/v1/apps` answered 401 in 0.8s throughout.

How to tell them apart in ten seconds:

```bash
asc auth status                 # instant even when broken: reads metadata, no key decrypt
sample $(pgrep -n asc) 3        # hung call: SecItemCopyMatching -> CSSM_DecryptDataFinal -> mach_msg
pgrep -lf SecurityAgent         # a dialog is waiting for a click
```

The fix is one click: run any `asc` command **from a real terminal** and choose
**Always Allow**. Do that immediately after every `brew upgrade asc`, before a release.



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
