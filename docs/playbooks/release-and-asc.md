# Releasing to TestFlight, and driving `asc`

Full narrative detail lives in [`docs/release-workflow.md`](../release-workflow.md) and
[`docs/updating.md`](../updating.md) — this file is the condensed, imperative version:
what to run, which env var means what, and the `asc` traps that have each cost a release.

## There is exactly ONE gated path

```sh
sh scripts/release-testflight-asc.sh              # build, upload, INTERNAL testers only
sh scripts/release-testflight-asc.sh --external    # ...and submit for Beta App Review (public link)
sh scripts/release-testflight-asc.sh --dry-run     # print what it would do, touch nothing
```

**`scripts/release-testflight.sh` is a shim.** It prints why it was retired and `exec`s
into `release-testflight-asc.sh` with the same arguments — the name still works, but it now
lands on the gated path. Never resurrect what it used to do by hand; the three things it
lacked (group assignment, version check, smoke test) are each a real incident described
below. **Never call `asc publish testflight --upload-only` directly** — see "The trap this
script exists to remove."

## The env hatches, and when each is legitimate

Four gates stop the release script. Each hatch is deliberately awkward to type — clearing
one should be a decision, not a reflex, and none of them belongs in an alias or a wrapper
script.

| Env var | Bypasses | Legitimate when |
|---|---|---|
| `MESH_ALLOW_DIRTY=1` | The clean-working-tree gate (`git status --porcelain` non-empty) | Almost never. An uncommitted tree means the shipped binary traces to nothing — no diff to read if it misbehaves, no revert to make. Commit or stash first. |
| `MESH_ALLOW_VERSION_DOWNGRADE=1` | The version-downgrade gate | Only after you have *decided*, with full knowledge, that testers on a higher pre-release version get forced to delete-and-reinstall (which wipes the app Keychain and un-pairs every machine they had). This is exactly what the 1.0 → 0.5.0 rename did to every tester at once. Prefer bumping `MARKETING_VERSION` in `project.yml` above whatever App Store Connect already holds instead. |
| `MESH_SKIP_VERSION_CHECK=1` | The "could we even ask App Store Connect" gate, when the 90s bounded probe times out | Only after confirming *by hand* in the TestFlight UI that the version you're shipping is not a downgrade. The script tries to tell you which cause it hit (a hung `asc` Keychain dialog vs. Apple itself unreachable) — read that before reaching for this. |
| `MESH_SMOKE_REQUIRED=1` | Nothing — it *tightens* a gate, it does not loosen one | The release script sets this itself, always. There is **no hatch** for the smoke-test gate: a skip ("no simulator here") becomes a hard failure instead of a silent pass. Fix is "run this on a machine with a current Xcode," never an env var. |
| `MESH_LINKS_REQUIRED=1` | The "offline machine reports link-check as skipped" allowance, inside `scripts/check-links.sh` | Only on a machine that is genuinely expected to have network — CI sets this so a runner with no connectivity is a broken runner, not a pass. Don't set it on a laptop that might be offline; that turns "no wifi" into a false release failure. |

## The trap this script exists to remove: `--upload-only` lands the build in ZERO groups

`asc publish testflight --upload-only` stops right after the upload. The build **processes,
goes `VALID`, and belongs to no beta group at all** — reachable by nobody, not external
testers, not internal ones, not you — while every list view in App Store Connect shows it
as a healthy build. This happened for real: build `202608270920` sat `VALID` in zero groups
on 2026-08-27, and the first sign was a person saying "I can't find the update," days later.

The script's own internal use of `--upload-only` is safe only because it is immediately
followed by adding the build to a group **and verifying the membership landed**:

```sh
asc testflight groups links view --group-id "$GROUP_ID" --type builds
```

`asc builds groups list --build-id` is marked **experimental and has reported zero groups
for a build that was demonstrably in one** — don't trust it. `groups links view` (asking
the *group* what it holds, not asking the *build* what groups it's in) is the authoritative
query, and it's what the script polls before calling the release done. `asc publish
testflight --group` itself exits 0 whether or not the build actually landed in the group —
its exit code alone is not evidence.

## Internal vs. external — the two audiences differ completely

| Group | Who gets it | Gate |
|---|---|---|
| **Internal** | App Store Connect team members, up to 100 | None — installable the moment processing finishes |
| **External** (the public join link) | anyone holding the link | **Beta App Review** — hours to a day, not instant |

A build sitting at `externalBuildState: READY_FOR_BETA_SUBMISSION` has been uploaded,
processed, and validated, and is **reaching nobody**. `IN_BETA_TESTING` is the state that
means friends actually have it. Check before telling anyone a release shipped:

```sh
asc testflight distribution view --build-id "$BUILD_ID"
```

Running the script **without** `--external` leaves the public link exactly where it was —
every list view still shows the newest build as healthy regardless of who can install it.
The script prints a loud banner naming the build the public link is still serving when you
release internal-only; read it, don't scroll past it.

## `asc` traps that have each cost time

- **Upgrading `asc` breaks its own Keychain access until you click through it once.**
  `brew upgrade asc` re-signs the binary, which invalidates the macOS Keychain ACL on the
  stored API key. Every subsequent `asc` call that needs the key raises a "wants to use
  your confidential information" dialog — in an interactive terminal you click **Always
  Allow** and move on; in a non-interactive one (a script, CI, an agent session) **nothing
  answers it and the command hangs forever with no output and no error.** It looks exactly
  like App Store Connect being down. It is not:
  ```sh
  asc auth status                 # instant even when broken — reads metadata, no key decrypt
  curl -s -o /dev/null -w '%{http_code}\n' -m 15 https://api.appstoreconnect.apple.com/v1/apps
  pgrep -lf SecurityAgent          # a dialog is waiting for a click, right now
  ```
  Fix, once, immediately after every `brew upgrade asc`: run any `asc` command from a real
  terminal and choose **Always Allow**, before you next try to release.
- **Version-string downgrade forces a delete-and-reinstall, which wipes the app's
  Keychain.** iOS reads a lower marketing version as *older* than what a tester already
  has and may refuse an in-place update — deleting and reinstalling to take the "new" build
  un-pairs every machine the tester had added, with no undo. This is why the downgrade gate
  is a hard `exit 1` now, not a `WARNING` — it used to print the warning and ship anyway,
  and that is precisely how the 1.0 → 0.5.0 rename went out.
- **Every app extension needs `CFBundleDisplayName` in its own `Info.plist`.** Processing
  otherwise fails with **90360**, once per extension.
  `INFOPLIST_KEY_CFBundleDisplayName` does **not** substitute — that build setting is only
  honored when `GENERATE_INFOPLIST_FILE: YES`, and this project sets it `NO` project-wide.
  Put the literal key in the plist.
- **A deleted App ID can never be reused.** Apple's error ("An App ID with Identifier ...
  is not available") reads like someone else took the name. It didn't — pick a different
  suffix.
- **The APNs environment comes from the provisioning profile, not the build config.**
  TestFlight/App Store builds are always signed `aps-environment = production`; a device
  token minted under one of those is rejected by the *sandbox* gateway with
  `BadDeviceToken`. `Shared/APNsEnvironment.swift` reads the embedded profile at runtime
  rather than guessing from a compile-time flag — don't reintroduce a guess.
- **`asc` never prints the issuer ID**, so raw `xcodebuild -authenticationKeyPath` cannot
  be used without also supplying `-authenticationKeyIssuerID` — which you don't have. Plain
  `-allowProvisioningUpdates` (covered by Xcode's own signed-in account) is what
  `release-testflight-asc.sh` uses instead; see [xcode-cli.md](xcode-cli.md).
- **Published links are checked automatically, not just assumed.** `scripts/check-links.sh`
  fetches the install one-liner, the TestFlight join link, and every other `install` /
  `testflight.apple.com` URL harvested out of `README.md` and `docs/updating.md`, and fails
  on anything that isn't 2xx/3xx. `mesh.lesearch.ai` once had no DNS at all while the
  README kept telling people to `curl` it — this is the check that would have caught it.

## Checking state instead of assuming it shipped

```sh
asc builds list --app 6803438426 --limit 5
asc testflight distribution view --build-id <BUILD_ID>
asc testflight groups list --app 6803438426
asc testflight groups links view --group-id <GROUP_ID> --type builds
```

This app: App Store Connect id **6803438426** (`LeSearch Mesh`,
`com.lecoder.meshwatch`), internal TestFlight group id
**f0b2cc09-9776-409c-865a-4706e881bccd**, public link
`https://testflight.apple.com/join/pVYPTxc7`. Build numbers are UTC `YYYYMMDDHHMM`
stamps, minted fresh per upload — they can never be reused or go backwards.
