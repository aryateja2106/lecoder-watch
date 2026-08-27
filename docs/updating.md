# Getting a new version onto a phone, a watch, and a machine

Three things carry a version, and they update by **three different routes**. Nothing here
needs a cable.

| What | Route | Who can do it | Takes |
|---|---|---|---|
| iPhone app | TestFlight | the tester, themselves | seconds |
| Apple Watch app | rides along with the iPhone app | automatic | seconds |
| `meshd` on each Mac / Linux box | `mesh upgrade` | whoever owns the machine | ~20 s |

---

## 1. The apps — TestFlight, over the air

**You do not plug the phone in.** Sideloading is the thing to avoid, not the fallback: a
development-signed build re-verifies with Apple on every fresh install (the *"Unable to
Verify App"* dead end), and each re-sign makes iOS treat it as a new app identity and
**wipes its privacy grants** — including Local Network, without which every machine on a
`100.64/10` tailnet reads as offline. See [release-workflow.md](release-workflow.md).

### On the phone

1. Open **TestFlight**.
2. **LeSearch Mesh** → **Update**. (Turn on *Automatic Updates* in TestFlight once, and
   even this step disappears.)

### On the watch

Nothing to do. The watch app is **embedded in the iPhone app** (`embed: true` in
`project.yml`), so one upload ships both and updating the phone updates the watch.

If the watch app doesn't appear after an update: iPhone → **Watch** app → scroll to
**Available Apps** → **Install**. That is a first-install step, not an update step.

### What it will not do

TestFlight cannot push a build the tester's OS can't run. Every build so far declares
**minimum iOS 26.0**, so a friend on iOS 18 sees nothing at all — no error, just an app
that never appears. Ask before sending the link.

---

## 2. The daemon — `mesh upgrade` on each machine

The apps are clients. The daemon is where most capability actually lives, and it updates
on its own schedule:

```bash
mesh upgrade
```

Or, on a machine that has no `mesh` yet:

```bash
curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh | sh
```

Check what a machine is actually running before debugging anything daemon-shaped:

```bash
mesh version && curl -s http://127.0.0.1:8899/health | python3 -m json.tool | head -20
```

**This is the failure that costs the most time.** An old daemon does not refuse a new
request — it answers **200 with the old shape**, which is indistinguishable from the
feature being broken. The app now says **update available** on a machine whose `/health`
is missing a capability this build needs; believe it (`Shared/DaemonCapabilities.swift`
is the list, and each entry carries the symptom you'd otherwise be chasing).

---

## 3. Publishing a build so other people get it

This is the part with a trap in it.

TestFlight has **two audiences**, and a build that is fine for one is invisible to the
other:

- **Internal testers** (up to 100, must be on your App Store Connect team) get a build
  **the moment processing finishes**. No review.
- **External testers** — anyone with the public link — only get a build **after Beta App
  Review approves it**. Uploading is not publishing.

A build sitting at `externalBuildState: READY_FOR_BETA_SUBMISSION` has been uploaded and
processed and is going nowhere. Check it before assuming your testers have what you have:

```bash
asc builds list --app 6803438426 --limit 5
```

```bash
asc testflight distribution view --build-id <BUILD_ID>
```

`internalBuildState: IN_BETA_TESTING` means you have it. **`externalBuildState:
IN_BETA_TESTING` is the one that means your friends have it.**

### The full publish

```bash
ASC_KEY_ID=Y4MR7X24UL ASC_ISSUER_ID=<uuid> sh scripts/release-testflight.sh
```

Then, in App Store Connect → TestFlight → the new build:

1. Fill **What to Test** — the `## [Unreleased]` block of [`CHANGELOG.md`](../CHANGELOG.md)
   is written to be pasted here.
2. Add the build to the **Beta** group (that is the group the public link points at).
3. **Submit for Beta App Review.** Review is usually hours, occasionally a day.
4. When it flips to `IN_BETA_TESTING`, testers get a notification automatically.

### The link to send people

```
https://testflight.apple.com/join/pVYPTxc7
```

Public, enabled, 1000 seats. It is a stable link — the same URL always serves whatever
build is currently approved for external testing, so it can go in a README, a DM, or a
landing page and never needs reissuing.

---

## Version numbers, and what they mean

| Number | Where it lives | Changes when |
|---|---|---|
| `0.5.0` | `MARKETING_VERSION` in `project.yml` | a release with user-visible change |
| `202608241803` | build number, stamped at upload | every single upload (UTC `YYYYMMDDHHMM`) |
| `0.5.0` | `const VERSION` in `install/payload/meshd/server.ts` | a daemon release |
| `v0.5.0` | the `mesh-install` GitHub release tag | a daemon release |

The apps and the daemon share a marketing version **on purpose** — a phone on 0.5.0 and a
Mac on 0.4.1 is the mismatch that produces silent, invisible failure, and matching numbers
make it a thing you can see. `mesh version` reads its answer out of the installed daemon,
so it describes the machine rather than the tarball it arrived in
(`scripts/check-mesh-version.sh` keeps it that way).
