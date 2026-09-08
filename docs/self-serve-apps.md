# Self-serve apps: describe it on any device, build it on your Mac, run it everywhere

Written 2026-09-08 from Arya's brief. Direction, not a spec; the spec comes when this is
scheduled.

## The promise

A person with a Mac (awake, running meshd) and any Apple device describes an app by
speaking or typing on the iPhone, iPad, Watch or Mac. The Mesh agents on the Mac build
it, sign it with the person's own developer team, and it appears on whichever of their
devices they want, without a cable, without Xcode on the device, and without the App
Store. It is their app, for their day.

## What exists today (2026-09-08)

| Step | State | Where |
|---|---|---|
| Describe the app by voice or text from the phone | shipped in 0.6 (agent chat, voice input) | `iOS/AgentChatView.swift`, `iOS/VoiceInputSheet` |
| Build on the Mac, sign with the user's team | shipped (`mesh apps config`, native-app-builder skill) | `install/payload/bin/mesh`, `share/skills/native-app-builder` |
| Icon in every build | shipped (generator emits iOS + watchOS entries) | `make-appicon.sh` |
| Wireless install link over the tailnet | shipped (`mesh apps add` + `mesh apps ota --enable`) | `meshd/apps.ts` |
| Install banner pushed to the device, tap to install | shipped today (`mesh apps push <slug>`) | `meshd/push.ts`, `iOS/NotificationManager.swift` |
| Direct push over cable or shared Wi-Fi | shipped (`mesh apps install`, devicectl) | `install/payload/bin/mesh` |
| Watch companion in the same install | shipped (Audiolib proves it) | |
| Install with no tap at all | not possible without MDM (see below) | |
| Off-tailnet install | not yet: the manifest is served on the tailnet only | |
| TestFlight | not built | |

## How the install reaches a device

1. **On the tailnet, any network** (today): `mesh apps push <slug>` sends an APNs banner
   to every paired iPhone and iPad. Tap, iOS asks "Install <name>?", done. Two taps,
   no cable, no shared Wi-Fi. The device must reach APNs (any internet) and the Mac's
   tailnet address (Tailscale on the device). First-time installs on a device need
   Developer Mode on.
2. **Off the tailnet** (next): expose only the `/a/` route publicly with Tailscale
   Funnel (`tailscale funnel --bg --set-path /a ...`). The random key in the path is
   the only secret on that route, which is the same posture the tailnet link has today.
   The `.ipa` is a dev-signed build that only installs on the team's registered devices,
   so a leaked link installs nothing on a stranger's phone.
3. **Zero-tap updates**: TestFlight. The first install on a device is a tap in the
   TestFlight app; every later build installs itself when Automatic Updates is on.
   Internal testers (up to 100 App Store Connect users, no review) fit "my own devices";
   external testers need one Beta App Review. Upload from the Mac with the user's own
   App Store Connect API key (`asc` CLI or Transporter); Xcode Cloud is a second route
   for people who keep the source on GitHub. Processing takes minutes, not seconds, so
   it is the update channel, not the first-run channel.
4. **Silent install, no tap ever**: MDM. A supervised device enrolled in an MDM server
   accepts `InstallApplication` with a manifest URL silently. NanoMDM or MicroMDM (open
   source, Go) plus an APNs MDM push certificate (Apple Push Certificates Portal; the
   CSR must be signed by an MDM vendor certificate, which individuals get through
   mdmcert.download). Real work, and an enrollment profile the person has to accept
   once. Worth it only if "no tap" matters more than a one-time enrollment.

## What the product needs beyond distribution

- One queue per person, on their Mac: describe → spec → build → prove → deliver, with
  the proof recordings (`docs/recordings/` in the app's repo) as the acceptance step.
  The Audiolib factory run is the template.
- A device picker on the phone: "put this on my iPad and my Watch" chooses the push
  targets; today a push goes to every registered device.
- The Watch as a first-class target: watch companions ride inside the iPhone install;
  standalone watch apps need their own OTA path (unverified; devicectl works).
- Their developer account, never ours: team id and bundle prefix stay in
  `~/.mesh/apps.json` on their Mac. Free accounts can sign for their own devices for
  seven days at a time; a paid account gets a year and TestFlight.
- Privacy: nothing leaves the Mac except the APNs banner (title + link) and, with
  TestFlight, the binary to Apple.
