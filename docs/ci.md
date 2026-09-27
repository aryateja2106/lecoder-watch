# CI/CD

## GitHub Actions (`.github/workflows/ci.yml`)

Triggers on push to `main`, `backup/**`, `release/**`, `feat/**`, `fix/**`,
`claude/**`, `codex/**`, and on every pull request. Same-ref runs cancel superseded
ones.

`main` and `backup/**` are in that list because they were the two branches that
mattered most and matched no pattern. `main` is where shipping work lands; the
repo's declared PR base is `backup/2026-07-02`, which is what every PR gets compared
and merged into. A base branch with no CI is worse than an untested feature branch —
a break landing there is invisible until it is in everything.

**`daemon`** (ubuntu-latest, ~15 min budget)
- Installs bun, then typechecks `install/payload/meshd` with
  `bun x tsc --noEmit -p tsconfig.json` (bun-types + typescript installed
  ephemerally with `--no-save`, so nothing is written to the committed
  package.json/lockfile).
- Runs the subset of `scripts/check-*` that need nothing macOS-only, no rmux/cmux,
  and no running daemon: `check-mesh-self-check.sh`, `check-mesh-input-linux.sh`,
  `check-mesh-pair.sh`, `check-mesh-push.sh`, `check-mesh-hooks.sh`,
  `check-mesh-upgrade.sh`, `check-mesh-version.sh`, `check-paste-epipe.sh`,
  `check-mesh-uninstall.sh`, `check-install-idempotent.sh`, `check-host-guard.sh`,
  `check-token-rotate.sh`, `check-mesh-onboarding.sh`, `check-pair-qr.sh`,
  `check-wol.sh`, `check-package-mesh-install.sh`, `check-mesh-hook.py`, and
  `check-links.sh`. The rest of `scripts/check-*` (Swift, `check-mesh-input.sh`,
  anything touching a live daemon) only runs in `apps`, where the real toolchain
  exists.
- `check-links.sh` runs here with **`MESH_LINKS_REQUIRED=1`**. It fetches every
  published install / TestFlight URL — the four canonical ones plus anything
  matching `install` or `testflight.apple.com` harvested out of `README.md` and
  `docs/updating.md` — and demands a 2xx/3xx. Off CI it skips when the machine is
  offline (probe: `https://github.com`), because a laptop on a plane is not
  evidence of link rot. `MESH_LINKS_REQUIRED=1` inverts that: on a runner, "no
  network" is a broken runner, and reporting it as a pass hides the exact rot the
  check exists for — `mesh.lesearch.ai` once had no DNS at all while the README
  kept telling people to `curl` it.

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
- Builds all three schemes unsigned against generic destinations
  (`CODE_SIGNING_ALLOWED=NO`, `-derivedDataPath build/DerivedData`): `MeshWatch`
  against `generic/platform=iOS Simulator`, `MeshWatch Watch App` against
  `generic/platform=watchOS Simulator`, `MeshDesktop` against
  `generic/platform=macOS`.
- Runs `sh scripts/check-all.sh` (the full Swift + shell self-check suite) **once**,
  as the last step. That loop already includes `check-ios-smoke.sh`, which launches
  the app on a simulator.

  **The job sets `MESH_SMOKE_REQUIRED: '1'`.** `check-ios-smoke.sh` exits 0 with a
  SKIP when the machine has no iOS 26+ simulator, which is honest on a laptop and a
  lie here: a green `apps` job would mean "the app was never launched" and be read
  as "the app is fine" — the exact shape of the 0.5.0 release, where every static
  check passed while the app died on every screen containing a text field. With the
  flag set, every skip path exits 1 with a loud message instead, so if the runner
  image ever loses its simulators CI says so rather than quietly stopping doing the
  one check that runs the code. On success the check prints the simulator name and
  runtime it used, so a log tail can answer "on what?".

  **There is no separate smoke-test step, and adding one back is a bug.** There used
  to be: `check-all.sh` ran the smoke test and a dedicated step ran it again, which
  meant two `xcodebuild test` runs against the same simulator in one job. The second
  gets its test runner killed before it connects, which `check-ios-smoke.sh`
  correctly refuses to call either a pass or a failure (`INCONCLUSIVE`, exit 1) — so
  the duplicate produced red builds that were nothing but the duplication, and the
  cure for those is re-running until green, which is how a real crash gets waved
  through.

## Xcode Cloud (TestFlight)

`ci_scripts/ci_post_clone.sh` and `ci_scripts/ci_pre_xcodebuild.sh` are the Xcode
Cloud hooks; everything else (build, archive, sign, upload) is configured through
App Store Connect, and one thing needs a human to click it once.

**`ci_pre_xcodebuild.sh` runs `sh scripts/check-all.sh` before the archive.** This
lane can auto-distribute to TestFlight, and it used to run *no* checks at all — so
the one path that puts a build straight into testers' hands had no gate on it while
the local release script had four. Red checks abort the archive.

It deliberately does **not** set `MESH_SMOKE_REQUIRED=1`: which simulator runtimes
an Xcode Cloud image carries is not something this repo controls or can check from
here, and a release lane that refuses to build because Apple changed an image is
worse than one that builds and says plainly what it did not verify. So the smoke
test may skip — but not quietly. When it does, the log gets a banner saying **the
app was never launched in this build**, and what to run before promoting it:

```bash
MESH_SMOKE_REQUIRED=1 sh scripts/check-ios-smoke.sh
```

1. **App Store Connect → your app → Xcode Cloud → Get Started**, and link this
   GitHub repo (`aryateja2106/lecoder-watch`) if it isn't linked already.
2. **Create a workflow**:
   - Start condition: branch changes on `feat/apns-push` (current default branch)
     or `main`, whichever should auto-release.
   - Action: **Archive**, scheme **LeSearch Mesh** (this also builds and embeds
     `MeshWatch Watch App` and both widget extensions — same dependency graph
     `xcodebuild -scheme MeshWatch` builds locally).
   - Post-Action: **TestFlight (Internal Testing)** — internal testers get every
     archive automatically; promoting a build to *external* testing still needs a
     one-time Beta App Review, same as `scripts/release-testflight-asc.sh` today.

After that one-time setup, every push to the workflow's branch archives and lands
in TestFlight with no further action.

### Build numbers

`scripts/release-testflight-asc.sh` (local releases) passes
`--build-number "$(date -u +%Y%m%d%H%M)"` to `asc publish testflight`. Xcode Cloud
runs its own `xcodebuild` invocation, so there's no command line to hook —
`ci_pre_xcodebuild.sh` does the equivalent thing earlier:
it overwrites the literal `CFBundleVersion` in `Generated/iOS-Info.plist` and
`Generated/Watch-Info.plist` (the two Info.plist sources that reference
`$(CURRENT_PROJECT_VERSION)` — `project.yml` sets `GENERATE_INFOPLIST_FILE: NO`,
so these are checked-in files, not something xcodegen writes) with the same
`YYYYMMDDHHMM` shape, before `xcodebuild` runs. Xcode Cloud's checkout is
discarded after the build, so this never touches what's committed.
(`MeshWatchWidgets/Info.plist` and `WatchWidgets/Info.plist` hardcode a static
`1`/`1.0` instead of referencing the build setting, so both schemes leave them
alone — same as the local release script today.)

Both paths produce a monotonically increasing, mutually comparable build number.
This used to have an open edge case — `ci_pre_xcodebuild.sh` used UTC and the local
script used the machine's timezone, so two releases inside the same few wall-clock
hours could produce out-of-order numbers and App Store Connect would reject the
second upload. Both are `date -u` now, so the gap is closed. Keep it that way: a
build number that goes backwards costs a release.
