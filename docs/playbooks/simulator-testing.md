# Simulator testing: `check-ios-smoke.sh`, and driving `simctl` directly

## `check-ios-smoke.sh` — what it proves and how it decides to run

This is the check that exists because a static build cannot see a crash that only happens
when UIKit replays a stored appearance invocation onto a live view (the 0.5.0 story, told
in full in [README.md](README.md) rule 1). It launches the real app on a real simulator,
runs a UI test that visits every tab and opens the pairing sheet, and only a pass means the
app actually opened.

```sh
sh scripts/check-ios-smoke.sh
```

**It skips instead of failing when there is no usable simulator**, and that skip is
*correct on a laptop* — a machine with an older Xcode reporting "not covered here" is
honest. The skip becomes dangerous only where the green tick gets read as "the app was
launched": a release, or CI's macOS job. Both of those set:

```sh
MESH_SMOKE_REQUIRED=1 sh scripts/check-ios-smoke.sh
```

which turns every skip path into `exit 1` instead of `exit 0`. There is deliberately **no
hatch** for `MESH_SMOKE_REQUIRED=1` — the fix for "this machine can't run it" is to run it
on a machine that can, never to silence the requirement.

`scripts/release-testflight-asc.sh` exports `MESH_SMOKE_REQUIRED=1` for its own run of
`check-all.sh`, and `check-all.sh` runs the smoke test exactly once as part of its normal
loop. **Never invoke `check-ios-smoke.sh` a second time in the same release or CI run** —
see the next section for why.

## Never run two `xcodebuild test` against one simulator at once

A second `xcodebuild test` targeting a simulator that already has a test runner attached
gets **its own runner killed before it connects**. `check-ios-smoke.sh` correctly refuses
to call that a pass or a real failure — it reports **INCONCLUSIVE** (matched by
`"before establishing connection"` / `"never finished bootstrapping"` in the log) and still
exits 1, because a gate that proved nothing must not be read as green either.

This has already shipped as a real bug once: `release-testflight-asc.sh` used to invoke the
smoke test both inside `check-all.sh` *and* as a separate step, producing exactly this
collision. The fix was deleting the duplicate invocation, not retrying until it passed —
**a release that fails on its own duplicate gate teaches you to re-run until green, which
is how a real crash gets waved through.** If you're adding any new script that touches a
simulator, check whether something else in the same run already owns it before invoking
`xcodebuild test`.

## Matching simulators: by `deviceTypeIdentifier`, never by display name

A simulator can be named anything — `check-ios-smoke.sh` was written on a machine whose
only matching simulator was called `iOS27-repro`, and an earlier version that filtered on
the display name containing `"iPhone"` reported **SKIP on the exact machine that had just
proven the check works**. Filter on the type identifier instead:

```python
if "iPhone" not in dev.get("deviceTypeIdentifier", ""):
    continue
```

This is the pattern `check-ios-smoke.sh` already uses when picking the newest usable
simulator — copy it rather than filtering on `dev["name"]`.

## Getting environment variables into `simctl launch`

`launchctl setenv` after the simulator has already booted **sets nothing that the launched
process sees** — it silently produces a confidently wrong result if you're using it to
check environment propagation. The only thing that actually works:

```sh
SIMCTL_CHILD_MESHD_TOKEN=throwaway xcrun simctl launch "$UDID" com.lecoder.meshwatch
```

Every `SIMCTL_CHILD_<VAR>` in the launching shell's environment is passed through to the
launched process as `<VAR>`. There is no other route.

## XCUITest relaunches a crashed app — assert more than `runningForeground`

If the app under test crashes mid-run, XCUITest **relaunches it automatically**. That means
`app.state == .runningForeground` passes even through a crash, because by the time the
assertion runs the app is back up on its first tab. Always assert something that only holds
if the app *stayed* up — e.g. `tab.isSelected` on whatever tab the test navigated to, not
the first one:

```swift
XCTAssertTrue(app.state == .runningForeground)   // NOT enough on its own
XCTAssertTrue(settingsTab.isSelected)             // catches the silent relaunch
```

## Driving or inspecting a simulator directly, outside a UI test

Useful when you need to look at or poke the simulator by hand rather than through
`xcodebuild test`:

- **Screenshot:** `xcrun simctl io "$UDID" screenshot /tmp/out.png`, then shrink before
  reading it back (`sips -Z 600 /tmp/out.png`). The iOS-Simulator MCP tool's own
  `screenshot` action is unreliable in this environment (fails with "restarting after a
  crash" on multiple runtimes) and its `tap` reports success without the tap landing —
  `attach` and `button` on that tool do work, but for anything pixel-precise use `simctl`
  directly.
- **Jump straight to a screen:** simulator launch arguments land in `UserDefaults`, so
  `xcrun simctl launch "$UDID" com.lecoder.meshwatch -onboardingStep 2` lets a view read
  `UserDefaults.standard.integer(forKey: "onboardingStep")` and open past onboarding. An
  absent key reads `0`, so this is inert in production — safe to leave wired.
- **A stale permission alert survives uninstall/reinstall.** Only `xcrun simctl shutdown
  "$UDID" && xcrun simctl boot "$UDID"` actually clears it. Do this before concluding a
  permission-prompt fix didn't work.
- **Watch app pairing is fixed, not automatic.** `xcrun simctl list pairs` shows which
  simulated watch is paired to which simulated phone — the pairing you want may not be the
  default one, so a watch-app install can silently land on the wrong pair. Check the list
  before assuming.
- **Choosing Xcode without a password:** `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`
  works for `simctl` and `xcodebuild` alike; `xcode-select -s` needs sudo. See
  [xcode-cli.md](xcode-cli.md).
