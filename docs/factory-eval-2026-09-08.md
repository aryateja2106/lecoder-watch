# Factory evaluation, 2026-09-08: four apps from plain-language briefs

Arya asked whether a personal software factory can work today: a person describes an
everyday app, an agent on their Mac builds it, and it lands on their devices without a
cable. Four briefs from his own examples were handed to the Antigravity CLI
(`gemini-3.1-pro-high`, headless, `--dangerously-skip-permissions`, 55-minute cap) with
the LeSearch Mesh skills in `~/.agents/skills` and the `mesh` CLI. A shell script
(`~/Projects/factory-eval/verify-app.sh`) then rebuilt each app from a clean derived-data
directory on its own simulator, ran its tests, checked the icon and embedded extensions,
launched it, took a screenshot, and checked the wireless-install registration. Two
independent agents judged the code, the reports and the screenshots. Briefs, reports,
logs, screenshots and judgements are under `~/Projects/factory-eval/`.

## Scorecard

| App (slug) | Brief | Minutes | Tokens | Clean rebuild | Tests | Icon | Embedded | Launches | Registered | Score |
|---|---|---|---|---|---|---|---|---|---|---|
| Focus Rounds (pomodoro-share) | Pomodoro, Watch, Live Activity, share link | 33 | 815k | yes | 1/0 | yes | widget + Watch app | yes | yes, manifest 200 | 7 |
| Routine (routine-log) | HealthKit dashboard, checklist, log, widget | 38 | 434k | no (actool: no AppIcon in a fresh build; the builder's own build had the icon) | 0 in the clean rebuild; 1/0 in the builder's run | in the builder's build | widget | not in the clean rebuild | yes, manifest 200 | 5 |
| Later (scheduled-message) | scheduled iMessage, honest about iOS | 55 (cap) | 961k | yes | 1/0 | yes | widget | yes | yes | 5 |
| Night (night-sounds) | Watch overnight snoring, honest about watchOS | 20 | 411k | yes | 1/0 | yes | Watch app | yes (iPhone stub) | yes, manifest 200 | 3 |

Scores for Later and Night are the judge's; Focus Rounds and Routine are the
orchestrator's from the mechanical results and a screenshot read, because the judge
assigned to them stalled on a hand-run of the asset compiler and was stopped.

## What worked

- The pipeline exists end to end. Every run produced a native SwiftUI project generated
  by XcodeGen, an icon from the bundled generator, a device build signed with Arya's
  team, and a `mesh apps add` registration with a working wireless link. Three of four
  installs were then pushed to Arya's phone as banners by the new `mesh apps push`.
- Honesty about platform limits held. Later says a message cannot be sent without a tap
  and builds the notification-then-composer flow; Night says a watch cannot record
  overnight and reads HealthKit sleep stages instead. No code path in any app fakes a
  capability.
- Focus Rounds is a real product: timer, Watch companion over WatchConnectivity, Live
  Activity, widget, chart, share sheet, one passing UI test, all rebuilt clean by the
  verifier and running on a fresh simulator (`screenshot-main.png` shows the 25:00 timer
  and the notification prompt).
- The skills were read and followed: the icon rule, `mesh apps config` for the team and
  prefix, `mesh apps add`. The builders' own harness feedback was specific and mostly
  right (HealthKit reference missing, widget bundle-id rule, watchOS multi-target
  snippet, sandbox blocking the global DerivedData).

## What failed or was faked

- **Entitlements, twice.** Later's widget has no App Group entitlement on either target,
  so it can never read the app's schedule and renders empty forever; Night's Watch app has
  no HealthKit entitlement, so its one query is refused forever and the screen the app
  exists for says "Permission denied". Both compile, sign, install, launch and pass their
  tests. `codesign -d --entitlements -` on the built artifacts is the one command that
  would have caught both.
- **The screen that matters was never run.** Night's only screenshot and only test are
  the iPhone stub, whose single sentence promises "snoring analysis" that the same run's
  report calls impossible. Later's test types into a field and taps Cancel.
- **Reports drifted from the preamble.** Later's report stops before the verification,
  the link, the timings and the harness feedback. Night's quotes an iPhone test as proof
  of a Watch feature.
- **Reproducibility.** Routine fails a clean `xcodegen generate` + build in a fresh
  derived-data directory with `actool: None of the input catalogs contained ... "AppIcon"`
  although the catalog is byte-identical to a working one; the builder's own derived data
  built it with the icon. Cause not yet found; recorded as open.
- **Antigravity project cross-talk.** Two headless conversations started in different
  directories without `--new-project` shared one project: the second narrated finishing
  the first's app and did no work of its own. `--new-project` per app fixed it.
- **Timeouts and stalls.** Later hit the 55-minute cap (status ERROR) after 960k tokens
  while still polishing; the code it left is the better of the two "honest" apps.

## Harness changes made today (in `install/payload/share/skills`, installed to `~/.agents/skills` and `~/.mesh/share/skills`)

1. `native-app-builder/SKILL.md` §6c: entitlements are the silent killer; the codesign
   proof on the app, every `PlugIns/*.appex` and `Watch/*.app` before `mesh apps add`;
   extension bundle-id rule; run the screen the brief is about.
2. `apple-native-apis/references/healthkit.md`: new. The preamble promised it and it did
   not exist.
3. `apple-native-apis/references/watchos-swiftui.md`: what a watch app may do overnight
   (nothing continuous; the five `WKExtendedRuntimeSession` types; HealthKit sleep as the
   honest substitute).
4. `apple-native-apis/references/widgets-smart-stack.md`: how a widget reads the app's
   data and why `UserDefaults(suiteName:)` hides a missing entitlement.
5. `~/Projects/factory-eval/PREAMBLE.md`: the same rules in the brief itself, plus
   "every report section is mandatory" and "never ship UI text that promises what the
   limits section rules out".

Still to do in the harness: an isolated `--new-project` per build in whatever drives the
CLI; a per-story test requirement (one XCUITest per screen the brief names); a
reproducibility step (commit, then rebuild from a clean derived-data directory before
registering); the proof-recording system from Audiolib
(`scripts/e2e-record.sh`) as the acceptance step; and the Routine actool cause.

## What to bring into the Mesh phone app

- **The brief template.** Before building, the phone asks five things and writes
  BRIEF.md: what the app is for in one sentence; which devices (iPhone, iPad, Watch,
  Mac); the two or three screens by name; which Apple data it needs (Health, Contacts,
  Calendar, Photos, location, microphone), because each is an entitlement and a permission
  prompt; and what "done" looks like as one sentence a test can check. The preamble
  supplies everything else.
- **Progress the phone shows.** Phase lines from the builder's own timings (discovery,
  scaffold, build fixes, verification, delivery) with the decisive output line under each;
  the screenshot of the main screen; the codesign entitlement list; the test line.
- **Delivery.** `mesh apps push <slug>` is the last step of every successful build: the
  banner arrives on every paired device, a tap installs. The phone's Built Apps list
  already opens the same link.
- **Guardrails from the failures.** Refuse to register a build whose entitlements do not
  cover what the code calls; refuse a report missing a section; show the user the
  builder's "platform limits" paragraph before they tap Install.

## Cost and time

| App | Wall time | Tokens | Verdict |
|---|---|---|---|
| Focus Rounds | 33 min | 815k | usable today |
| Routine | 38 min | 434k | usable from the builder's build; clean rebuild broken |
| Later | 55 min (cap) | 961k | honest design, dead widget, data-loss bug |
| Night | 20 min | 411k | honest report, dead Watch screen |

Roughly 20 to 55 minutes and 0.4 to 1.0 million tokens per everyday app on a Pro-class
model, with the person's own subscription paying for it. For a subscription with a daily
or weekly token allowance, that is a few apps a week, which matches the "solve my own
small problems" use, not a build-anything-anytime one. The cost that matters more is
Arya's: each app needed an independent verification pass to find out that it was
partly dead, and that pass is the product.
