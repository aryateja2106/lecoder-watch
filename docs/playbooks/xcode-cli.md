# Driving Xcode from the command line

Everything here is `sh`/`xcodebuild`/`xcodegen`. There is no reason to open Xcode's GUI for
a build, a check, or a release — only for the physical-device Developer Mode dance (see
[device-install.md](device-install.md)) and for signing changes that need a human's Apple
ID session.

## `project.yml` is the source of truth — never hand-edit `MeshWatch.xcodeproj`

`MeshWatch.xcodeproj` is generated and **gitignored**. It does not exist until you run:

```sh
xcodegen generate
```

Any change made through Xcode's UI (a build setting, a new file reference, a signing
selection) that is not also reflected in `project.yml` is **silently discarded the next
time anyone runs `xcodegen generate`** — which is every build, every check, and every CI
run. This has specifically bitten signing: `project.yml` sets

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: "B5B87F7AXF"
    CODE_SIGN_STYLE: Automatic
```

at the project level. If you ever need to change the team, use
`scripts/set-development-team.sh <TEAM_ID>` (it edits `project.yml` and re-runs
`xcodegen generate`) or edit `project.yml` directly — never the Xcode UI alone.

Run `xcodegen generate` after **any** edit to `project.yml`, and as the first step of any
build, check, or release script that doesn't already do it (`check-ios-smoke.sh` and
`release-testflight-asc.sh` both do).

## Choosing the Xcode: `DEVELOPER_DIR`

Two Xcodes matter on this machine, and using the wrong one either fails outright or wastes
a build number:

| Xcode | Path | Use for |
|---|---|---|
| Stable | `/Applications/Xcode.app/Contents/Developer` (26.6, SDK 26.5) | Simulator builds, CI, **every App Store Connect upload** |
| Beta | `/Applications/Xcode-beta.app/Contents/Developer` (27.0, SDK 27.0) | Installing to Arya's physical iPhone 15 Pro / Apple Watch Series 9, both running OS 27 |

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project MeshWatch.xcodeproj ...
```

`DEVELOPER_DIR` needs no password, unlike `xcode-select -s`, so prefer it in scripts and
agent sessions. Both directions are hard failures if you get them backwards:

- **Stable Xcode against the OS-27 devices**: 26.6 only carries the 26.5 SDK and cannot
  deploy to a device running a newer OS at all.
- **Beta Xcode uploaded to App Store Connect**: the upload is accepted and then fails
  processing with **90534 Unsupported SDK or Xcode version** — verified the hard way, and
  it costs the build number (App Store Connect build numbers can never be reused).
  `scripts/release-testflight-asc.sh` pins this for you:
  `export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"` —
  do not override it when releasing.

## Scheme names — copy these exactly, including the space

```
MeshWatch              # the iOS app (embeds the watch app + iOS widget extension)
MeshWatch Watch App    # the watchOS app (embeds WatchWidgets)
MeshDesktop             # the macOS menu-bar app
```

`MeshWatch Watch App` has a literal space in it — quote it as one argument
(`-scheme "MeshWatch Watch App"`), never split it, and see the zsh word-splitting warning
in `AGENTS.md` rule 7 if you're building the destination string separately too.

## Generic vs. device/simulator-id destinations

**Generic** destinations build for a platform without picking one concrete target. Use
these for compiling and for CI — they need no device or simulator to be booted, and they
are what every unsigned build in this repo uses:

```sh
xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project MeshWatch.xcodeproj -scheme 'MeshWatch Watch App' \
  -destination 'generic/platform=watchOS Simulator' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project MeshWatch.xcodeproj -scheme MeshDesktop \
  -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

**A concrete `id=` destination** is required the moment you need to actually *run* or
*test* something — a booted simulator UDID or a device UDID:

```sh
xcodebuild test -project MeshWatch.xcodeproj -scheme MeshWatch \
  -destination "id=$SIM_UDID" -derivedDataPath build/Smoke

xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch \
  -destination "platform=iOS,id=$DEVICE_UDID" -allowProvisioningUpdates build
```

`generic/platform=iOS` (no `Simulator` suffix, no id) also exists and compiles a
device-signed build without targeting one specific device — useful to catch signing
problems before you have a UDID in hand, but it cannot install or launch anything. See
[device-install.md](device-install.md) for the full device flow.

Never build the destination string in a variable and pass it unquoted (`$dest` instead of
`"$dest"`) — see `AGENTS.md` rule 7: it silently fell back to "first of multiple matching
destinations," which built for a device when the intent was the simulator, and still
printed `** BUILD SUCCEEDED **`.

## `-allowProvisioningUpdates`

Needed whenever `xcodebuild` has to create or renew a signing certificate or provisioning
profile itself (installing to a fresh device, archiving for a new bundle ID). Pair it with
explicit API-key auth when running non-interactively:

```sh
xcodebuild archive -project MeshWatch.xcodeproj -scheme MeshWatch \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER_ID" \
  ...
```

**`asc` (the CLI used for releases) never prints the issuer ID** — it keeps it in the
system keychain — so a script that shells out to `asc` cannot construct
`-authenticationKeyIssuerID` and must not try. `scripts/release-testflight-asc.sh` instead
runs bare `-allowProvisioningUpdates`, which works because it is covered by Xcode's own
signed-in account, and lets `asc` handle everything upload-side. Only reach for the
explicit three-flag form when you are driving `xcodebuild` directly outside `asc` (e.g. a
probe archive) and have the key material on disk yourself.

## Where build logs go, and reading `EXIT` from the file

Follow the pattern already used by `check-ios-smoke.sh` and `release-testflight-asc.sh`:
write to a `mktemp -t <descriptive-name>` file, run the command, capture its real exit
code, and only then read the log — see iron rule 2 in [README.md](README.md) for why
piping straight into `tail` is unsafe.

```sh
log="$(mktemp -t mesh-build)"
if xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch \
     -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
     CODE_SIGNING_ALLOWED=NO build >"$log" 2>&1; then
  echo "OK"
  rm -f "$log"
else
  echo "FAIL — last 40 lines:"
  tail -40 "$log"
  echo "full log: $log"
  exit 1
fi
```

Do not let the log vanish on failure (no bare `rm -f` before checking the exit code) and
do not delete it before printing a path someone else can open. `check-ios-smoke.sh` keeps
the log file on every non-zero exit specifically so the path survives past the current
shell.
