# TestFlight with `asc`

How a 0.5.0 build actually reaches a phone. Tooling is
[`asc`](https://github.com/rorkai/App-Store-Connect-CLI) (`brew upgrade asc`).
This is the command-level companion to [release-workflow.md](release-workflow.md)
and [updating.md](updating.md). Run `asc --help` and `asc <cmd> --help` when a
flag disagrees with this file — the CLI is the source of truth.

App: **LeSearch Mesh** · App Store Connect id **6803438426** · bundle
`com.lecoder.meshwatch`.

## One-time on this Mac

```sh
brew upgrade asc          # 4.9.x as of 2026-08-27; docs in this repo were written against it
asc auth status           # key Y4MR7X24UL in the system keychain is enough
asc doctor
```

You do not pass the issuer id to `asc` — it is already in the keychain.
`scripts/release-testflight.sh` still needs `ASC_KEY_ID` and `ASC_ISSUER_ID`
because it shells out to `xcodebuild -authenticationKeyIssuerID`.

## See what testers actually have

```sh
asc builds list --app 6803438426 --limit 8 --pretty
asc builds list --app 6803438426 --version 0.5.0 --pretty
asc testflight groups list --app 6803438426 --pretty
asc testflight distribution view --build-id <BUILD_ID> --pretty
```

Read `internalBuildState` and `externalBuildState` on the distribution view.
They are not the same channel:

| State | Who can install |
|---|---|
| `internalBuildState: IN_BETA_TESTING` | Anyone on the App Store Connect team, immediately |
| `externalBuildState: WAITING_FOR_BETA_REVIEW` / `IN_BETA_TESTING` | The public link, only after Beta App Review |

The public link is stable: https://testflight.apple.com/join/pVYPTxc7
(group **Beta**, id `dad3b7b2-772d-44e6-aa40-fe538f328f10`). Internal group
id: `f0b2cc09-9776-409c-865a-4706e881bccd`.

On 2026-08-27 the 0.5.0 build **202608270920** (`90bba10e-6b38-4b6b-9755-63a0d9771fc2`)
was `IN_BETA_TESTING` internally and `WAITING_FOR_BETA_REVIEW` externally.
Install it from TestFlight on your own phone; friends wait for Apple.

Testers who still have the pre-rename **1.0** may have to delete and reinstall —
iOS treats 0.5.0 as older. That wipes Keychain pairing. See [updating.md](updating.md).

## Submit an already-uploaded build for external review

Do this when `externalBuildState` is `READY_FOR_BETA_SUBMISSION` and you are
sure What to Test is filled (paste `CHANGELOG.md` `[Unreleased]`, or the cut
version section).

```sh
asc testflight review submit --build-id <BUILD_ID> --confirm
asc testflight distribution view --build-id <BUILD_ID> --pretty
```

Do not submit twice. A build already `WAITING_FOR_REVIEW` stays in the queue.

## Upload a new build

Prefer the repo script when you want the self-checks + archive path:

```sh
ASC_KEY_ID=Y4MR7X24UL ASC_ISSUER_ID=<uuid> sh scripts/release-testflight.sh
```

Or `asc`, which already holds credentials:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  asc publish testflight \
    --app 6803438426 \
    --project MeshWatch.xcodeproj \
    --scheme MeshWatch \
    --version 0.5.0 \
    --configuration Release \
    --group Internal \
    --upload-only --wait --pretty
```

Then add it to **Beta** and submit:

```sh
asc publish testflight \
  --app 6803438426 \
  --build <BUILD_ID> \
  --group Beta \
  --test-notes "$(sed -n '/^## \[Unreleased\]/,/^## \[/p' CHANGELOG.md | sed '$d')" \
  --submit --confirm --wait --pretty
```

Use **stable Xcode** (`/Applications/Xcode.app`), not a beta — a beta-built
upload fails processing with **90534**. Build numbers are UTC timestamps;
App Store Connect rejects reuse.

## After processing

1. Internal: TestFlight → LeSearch Mesh → **Update**. Watch rides along.
2. External: wait until `externalBuildState` is `IN_BETA_TESTING`. The join
   link does not change.
3. Machines: `mesh upgrade` (or a fresh curl of `https://mesh.lesearch.ai/install.sh`).
   The app update does not update `meshd`.
