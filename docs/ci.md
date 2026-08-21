# CI/CD

## GitHub Actions (`.github/workflows/ci.yml`)

Triggers on push to `feat/**`, `fix/**`, `claude/**`, `codex/**`, and on every pull
request. Same-ref runs cancel superseded ones.

**`daemon`** (ubuntu-latest, ~15 min budget)
- Installs bun, then typechecks `install/payload/meshd` with
  `bun x tsc --noEmit -p tsconfig.json` (bun-types + typescript installed
  ephemerally with `--no-save`, so nothing is written to the committed
  package.json/lockfile).
- Runs the subset of `scripts/check-*` that need nothing macOS-only, no rmux/cmux,
  and no running daemon: `check-mesh-self-check.sh`, `check-mesh-input-linux.sh`,
  `check-mesh-pair.sh`, `check-mesh-push.sh`, `check-mesh-hooks.sh`,
  `check-mesh-upgrade.sh`, `check-token-rotate.sh`, `check-mesh-onboarding.sh`,
  `check-pair-qr.sh`, `check-wol.sh`,
  `check-package-mesh-install.sh`, `check-mesh-hook.py`. The rest of
  `scripts/check-*` (Swift, `check-mesh-input.sh`, anything touching a live
  daemon) only runs in `apps`, where the real toolchain exists.

  **Every daemon `.ts` file is typechecked — nothing is excluded.** bun-types pulls
  in `@types/node`'s undici fetch types, where `Body.json()` is `Promise<unknown>`
  (correct per spec), so a bare `const body = await req.json()` followed by
  `body.foo` is a real `TS2339`. The request handlers cast the parsed body once at
  the boundary — `(await req.json().catch(() => ({}))) as any` — which is honest
  about JSON being dynamic and keeps `tsc` covering `server.ts`, `input.ts`,
  `push.ts`, `files.ts`, and `doctor.ts` like everything else. If you add a handler,
  cast the body the same way (annotating a `Promise<unknown>` fallback as `any`
  does NOT work: TypeScript collapses `unknown | any` back to `unknown`).

**`apps`** (macos-15, 45 min timeout)
- `brew install xcodegen`, then `xcodegen generate` — `MeshWatch.xcodeproj` is
  gitignored/generated, same as everywhere else in this repo.
- Builds both schemes unsigned against generic simulator destinations
  (`CODE_SIGNING_ALLOWED=NO`, `-derivedDataPath build/DerivedData`): `MeshWatch`
  against `generic/platform=iOS Simulator`, `MeshWatch Watch App` against
  `generic/platform=watchOS Simulator`.
- Runs `sh scripts/check-all.sh` (the full Swift + shell self-check suite).

## Xcode Cloud (TestFlight)

`ci_scripts/ci_post_clone.sh` and `ci_scripts/ci_pre_xcodebuild.sh` are the Xcode
Cloud hooks; everything else (build, archive, sign, upload) is configured through
App Store Connect, and one thing needs a human to click it once:

1. **App Store Connect → your app → Xcode Cloud → Get Started**, and link this
   GitHub repo (`aryateja2106/lecoder-watch`) if it isn't linked already.
2. **Create a workflow**:
   - Start condition: branch changes on `feat/apns-push` (current default branch)
     or `main`, whichever should auto-release.
   - Action: **Archive**, scheme **MeshWatch** (this also builds and embeds
     `MeshWatch Watch App` and both widget extensions — same dependency graph
     `xcodebuild -scheme MeshWatch` builds locally).
   - Post-Action: **TestFlight (Internal Testing)** — internal testers get every
     archive automatically; promoting a build to *external* testing still needs a
     one-time Beta App Review, same as `scripts/release-testflight.sh` today.

After that one-time setup, every push to the workflow's branch archives and lands
in TestFlight with no further action.

### Build numbers

`scripts/release-testflight.sh` (local releases) stamps
`CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)"` straight onto the `xcodebuild`
command line. Xcode Cloud runs its own `xcodebuild` invocation, so there's no
command line to hook — `ci_pre_xcodebuild.sh` does the equivalent thing earlier:
it overwrites the literal `CFBundleVersion` in `Generated/iOS-Info.plist` and
`Generated/Watch-Info.plist` (the two Info.plist sources that reference
`$(CURRENT_PROJECT_VERSION)` — `project.yml` sets `GENERATE_INFOPLIST_FILE: NO`,
so these are checked-in files, not something xcodegen writes) with the same
`YYYYMMDDHHMM` shape, before `xcodebuild` runs. Xcode Cloud's checkout is
discarded after the build, so this never touches what's committed.
(`MeshWatchWidgets/Info.plist` and `WatchWidgets/Info.plist` hardcode a static
`1`/`1.0` instead of referencing the build setting, so both schemes leave them
alone — same as the local release script today.)

Both paths produce a monotonically increasing, mutually comparable build number
as long as they don't collide, which is the one open edge case:
`ci_pre_xcodebuild.sh` uses UTC, and the local script uses whatever timezone the
machine running it is in. A local release and an Xcode Cloud build landing within
the same few hours of each other in wall-clock time could in principle produce a
build number that isn't strictly increasing, and App Store Connect would reject
the second upload. In practice that only bites if you run a local release and a
Cloud-triggered push land close together; if it ever does, switching
`scripts/release-testflight.sh` to `date -u` would close the gap entirely.
