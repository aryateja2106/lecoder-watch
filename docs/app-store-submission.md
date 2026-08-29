# App Store submission

Researched August 2026 against Apple's own guidelines and documentation. Every quoted rule
links to its source. Work top to bottom; the first section is the part that can actually
get the app rejected.

## The guideline that can kill this app is 4.2.7, not 2.5.2

Everyone assumes a terminal app dies on **2.5.2** ("may not download, install, or execute
code"). It almost certainly does not. That rule targets code executed *by the iOS app*. This
app sends keystrokes to a daemon on the user's own machine and receives rendered output; the
iOS binary executes nothing new. Termius, Blink, Prompt and Jump Desktop all ship on this
basis. The iSH rejection was about a *local* interpreter running on the device, and Apple
reversed it on appeal.

**The real landmine is [4.2.7 Remote Desktop Clients](https://developer.apple.com/app-store/review/guidelines/).**
Read the conditional at the top carefully:

> "If your remote desktop app acts as a mirror of **specific software or services** rather
> than a **generic mirror of the host device**, it must comply with the following: (a) The
> app must only connect to a user-owned host device that is a personal computer … and both
> the host device and client must be connected on a local and LAN-based network. … (e) Thin
> clients for cloud-based apps are not appropriate for the App Store."

Our screen feature is a generic mirror of the user's own Mac, so 4.2.7 should not bind. **But
the agent-activity view and the "answer the agent" surface can look to a reviewer like a
mirror of specific software** (Claude Code). If a reviewer applies 4.2.7, clause (a) bans
every non-LAN connection and (e) is fatal.

Mitigation, and it is mostly positioning:

1. Lead with **"a generic mirror of your own Mac"** in the description, the screenshots and
   the review notes. Say it in those words.
2. Never let the app look like it hosts, bundles or sells the agent. The agent is the user's,
   installed by them, running on their machine.
3. Satisfy (b) — all execution is host-side — and (c) — pairing is *initiated on the host*
   via the curl command. Say that explicitly; it is true and it helps.
4. Keep the UI from resembling an App Store view, per (d).

If rejected under 2.5.2 or 4.2.7, the right move is **one carefully argued appeal quoting the
"generic mirror" conditional**, not a resubmission with features stripped out.

**Do not** bundle a local interpreter, a package manager, or any scripting engine that can
fetch and run remote code. Each of those converts us into the iSH fact pattern.

## The reviewer cannot install our daemon — 2.1(a)

This is the second real risk, and Apple provides the escape hatch in the rule itself:

> "If you are unable to provide a demo account due to legal or security obligations, you may
> include a **built-in demo mode** in lieu of a demo account **with prior approval by
> Apple**. Ensure the demo mode exhibits your app's full features and functionality."

And from [App Review](https://developer.apple.com/distribute/app-review/): for features that
"require an environment that is hard to replicate or require specific hardware, be prepared
to provide a demo video or the hardware."

Do all three, belt and braces:

- [ ] **A Demo Host** that appears in the machine list with no pairing, exercising every
      feature: canned agent alerts, an answerable question, a scripted terminal session, a
      recorded screen stream, and the trackpad.
- [ ] **A live throwaway host** kept up for the whole review window, with its pairing code
      in the review notes so a reviewer can drive the real product.
- [ ] **An unlisted demo video**, 2–3 minutes, showing the curl install on a real Mac through
      to answering an agent on the wrist.

Request the "prior approval" for demo mode in the App Review notes on the **first**
submission, so it is on the record.

## Everything must be described in the review notes — 2.3.1(a)

> "Don't include any hidden, dormant, or undocumented features … All new features,
> functionality, and product changes must be described with specificity in the Notes for
> Review section of App Store Connect (generic descriptions will be rejected)."

Hiding screen control behind a flag to sneak past review is itself a violation, and a
developer-account-level risk under 2.3.1(b).

### Review notes template

1. **What it is** — "A client for the user's own Mac and Linux computers. It is a generic
   mirror of the host device; it does not mirror or resell any specific third-party software
   or service."
2. **How to test without a machine** — "Tap Demo Host on first launch. No pairing needed. It
   exercises every feature: agent alerts, answering an agent, a live terminal session, and
   remote screen view and control."
3. **How to test for real** — the live pairing code and the exact curl command.
4. **Demo video URL.**
5. **2.5.2 statement** — "The app contains no interpreter and downloads no code. All
   execution occurs on the user's own computer; the app transmits keystrokes and receives
   rendered output, as any SSH or VNC client does."
6. **4.2.7 statement** — quote the "generic mirror" conditional and assert we fall outside it.
7. **4.7 statement** — "The app offers no software; any AI agent is the user's own, installed
   and run by the user on their own machine."
8. **Prior-approval request** for the demo mode, per 2.1(a).
9. **Notification and background behaviour**, including expected watch suspend/resume.

## Privacy — the easy win

We can honestly answer **Data Not Collected** for every category.
[Apple's definition](https://developer.apple.com/app-store/app-privacy-details/):

> "'Collect' refers to transmitting data off the device in a way that allows you and/or your
> third-party partners to access it for a period longer than what is necessary to service the
> transmitted request in real time." … "Data that is processed only on device is not
> 'collected'."

The *apps* transmit nothing anywhere, so Data Not Collected holds. The daemon is a
different, disclosed story: meshd sends one anonymized heartbeat a day (version, platform,
uptime, coarse counters, random install id), `MESHD_TELEMETRY=off` silences it, and the
privacy page documents it. Say it plainly in the listing: *No accounts. No servers of ours
in the data path. The apps collect nothing — Data Not Collected. The daemon's optional
daily heartbeat is disclosed on the privacy page and `MESHD_TELEMETRY=off` turns it off.*
Never write "no telemetry" — that claim was retired when the heartbeat shipped.

**The apps' Data Not Collected answer becomes false the moment we add a hosted relay,
crash reporting, or an analytics SDK to the apps.** A cloud relay is a
[roadmap](../ROADMAP.md) non-goal today; if that stance ever changes, revisit this answer
before shipping the change.

- [ ] **Privacy policy in two places** — 5.1.1(i) requires it in App Store Connect metadata
      *and* "within the app in an easily accessible manner". A Settings › Privacy Policy row
      is a five-minute fix and a common avoidable rejection. `web/privacy.html` exists.
- [ ] **`PrivacyInfo.xcprivacy` on both the iOS and watchOS targets**:
      `NSPrivacyTracking=false`, empty `NSPrivacyTrackingDomains`, empty
      `NSPrivacyCollectedDataTypes`, and `NSPrivacyAccessedAPITypes` for what we use —
      almost certainly UserDefaults **CA92.1**, plus FileTimestamp **C617.1** if we cache
      scrollback or frames, DiskSpace **E174.1** if we check free space, and SystemBootTime
      **35F9.1** if elapsed-time clocks are used (they are, for the connection grace window).
      With no third-party SDKs we skip the SDK signature list entirely.
      ([reference](https://developer.apple.com/documentation/BundleResources/describing-use-of-required-reason-api))
- [ ] **`ITSAppUsesNonExemptEncryption` = false** in Info.plist. HTTPS/TLS via URLSession,
      Keychain and CryptoKit are exempt. This also stops App Store Connect asking the export
      questionnaire on every build.
      **Re-evaluate if we ever roll our own crypto** — a custom pairing handshake or our own
      framing over a raw socket could push us out of the exemption.
- [ ] **No accounts.** 5.1.1(v): apps with account creation must offer in-app account
      deletion. Having no accounts avoids that entirely, and trivially satisfies 4.2.7(c) if
      it is ever applied. Do not add accounts before launch.

## Assets

watchOS ships **inside the iOS app record** — one listing, one review. No standalone watch
app is needed, which is right since the phone does pairing. **Apple Watch does not support
App Previews at all**, so the watch story has to be told inside the iPhone preview.

**iPhone screenshots** — 6.9" is required. Accepted portrait sizes: `1260x2736`, `1290x2796`,
or `1320x2868`. Upload only the 6.9" set; smaller sizes are scaled automatically. 1–10 per
app, no alpha channel.

**Apple Watch screenshots** — required, and **one size used consistently across every
localization**. Series 10 / 11 = `416x496` is the sensible default. (Ultra 3 = 422x514,
Ultra 2 = 410x502, Series 9/8/7 = 396x484, SE = 368x448.)

**App preview video** — 15–30s, ≤500MB, up to 3. H.264 High ≤L4.0, ≤30fps, 10–12 Mbps VBR.
iPhone accepts `886x1920` portrait. Stereo AAC 256kbps.

2.3.3: "Screenshots should show the app in use, and not merely the title art, login page, or
splash screen." **Do not lead with the pairing screen.** Lead with an agent waiting on the
wrist, a live terminal, and the Mac mirrored. Overlays and captions are explicitly allowed.
2.3.10: no other-platform devices or logos in the imagery. 2.3.8: metadata must hold to a 4+
rating — no profanity in captured terminal output.

### Producing them

```bash
xcrun simctl list devices available
xcrun simctl boot "iPhone 16 Pro Max"            # 1320x2868 -> the 6.9" slot
xcrun simctl boot "Apple Watch Series 10 (46mm)" # 416x496
```

```bash
xcrun simctl status_bar "iPhone 16 Pro Max" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
```

```bash
xcrun simctl io "iPhone 16 Pro Max" screenshot --type png ~/shots/ios-01.png
```

```bash
xcrun simctl io "Apple Watch Series 10 (46mm)" screenshot ~/shots/watch-01.png
```

A hidden alpha channel is the most common `IMAGE_TOOL_FAILURE`. Strip it and verify the exact
pixel size — `1320x2867` is rejected from a `1320x2868` slot:

```bash
sips -s format png --setProperty hasAlpha false in.png --out out.png && sips -g pixelWidth -g pixelHeight out.png
```

Recording, then transcoding to spec with a silent stereo track (App Store Connect rejects a
video with no audio track):

```bash
xcrun simctl io booted recordVideo --codec h264 --mask black ~/shots/raw.mov
```

```bash
ffmpeg -i raw.mov -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -vf "scale=886:1920:force_original_aspect_ratio=decrease,pad=886:1920:(ow-iw)/2:(oh-ih)/2,fps=30" -c:v libx264 -profile:v high -level 4.0 -b:v 11M -maxrate 12M -bufsize 24M -pix_fmt yuv420p -c:a aac -b:a 256k -ar 44100 -ac 2 -shortest -t 28 preview-69.mp4
```

Upload screenshots **serially** — uploading many at once is a known cause of
`IMAGE_TOOL_FAILURE`. Scrub any TestFlight chrome, debug banners or staging hostnames from
captures; one documented rejection was for a screenshot still showing a "Back to TestFlight"
button.

## App identity is accepted debt — never "fix" it in a branding sweep

The bundle ids (`com.lecoder.meshwatch`, `com.lecoder.meshwatch.*`, `com.lecoder.meshdesktop`),
the APNs topic (`com.lecoder.meshwatch`), and the `meshwatch://` pairing URL scheme are
internal names pinned by the live App Store Connect app record (6803438426, on TestFlight).
Changing the bundle id means a **new** App Store app: a new TestFlight link, every tester
re-invited, every machine re-paired, and push broken until the APNs topic moves with it.
These identifiers are invisible to customers — the display name everywhere is LeSearch Mesh.
The decision is: keep them forever, and keep them out of scope for any rename or branding
pass. User-facing *strings* say LeSearch Mesh; identifiers stay `com.lecoder.*`.

## Two things outside the store that will bite

- [ ] **Local network permission.** Since iOS 14, LAN discovery needs
      `NSLocalNetworkUsageDescription` and an `NSBonjourServices` array. The system prompt is
      a cliff for a non-technical user: deny it once and discovery silently returns nothing
      forever, with recovery buried in Settings › Privacy & Security › Local Network. Build a
      pre-prompt explainer, and a diagnostic that detects the denial and deep-links via
      `UIApplication.openSettingsURLString`.
- [ ] **`meshd` must be Developer ID signed and notarized.** It is true that curl-downloaded
      files skip the quarantine attribute and therefore Gatekeeper — but relying on that is
      fragile and unacceptable for this audience. It is also load-bearing for the
      Accessibility and Screen Recording grants, which are **per-binary**: re-signing changes
      the identity and re-triggers the prompts.

## TestFlight — the vehicle for the first users

Internal testers: up to 100 team members, **no Beta App Review**, builds distribute
immediately. That is the right path for the first cohort.

External testers: up to 10,000, and Apple requires the first build to be approved by App
Review for TestFlight. Expect roughly 24 hours for that first external build; later builds of
the same version usually reach existing testers within minutes unless entitlements, privacy
strings or marketing copy changed. Builds expire after 90 days. A public TestFlight link
allows recruiting from a launch post without collecting emails.

Review timing generally: "On average, 90% of submissions are reviewed in less than 24 hours."
Appeals go to the App Review Board — one appeal per rejection, with specific reasons.
