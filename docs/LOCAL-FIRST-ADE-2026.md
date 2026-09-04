# LeSearch Mesh — Local-First ADE Architecture (2026)

**Mission:** *Less search, more agents.*  
Empowering users who own powerful local hardware (Apple Silicon Macs, iPhones, iPads, Apple Watches) to own their entire application layer, local intelligence, and agentic development environment.

---

## 1. The Core Thesis: Hardware Ownership = Application Ownership

Modern developer tools (ChatGPT, Anthropic Claude) are introducing sharable canvas artifacts and web sites. However, these solutions run inside proprietary cloud silos, gated behind monthly cloud subscriptions, vendor-locked databases, and ephemeral remote hosting.

**LeSearch Mesh takes this one step further:**
1. **Local-First Machine Control:** Your Mac, Mac mini, or studio machine is your execution engine.
2. **Multi-Agent CLI Harness:** Seamlessly supervise and chat with your favorite CLI agents:
   - **Claude Code (`claude`)**
   - **ChatGPT Codex (`codex`)**
   - **Cursor Agent CLI (`cursor-agent`)**
   - **Antigravity / OMP (`agy` / `omp`)**
   - **Hermes / OpenClaw**
3. **Wrist & Pocket Supervision:** Real-time visibility on Apple Watch and iPhone, approving decisions with single-tap or voice haptics.
4. **Permanent Artifact Ownership:** The applications you ask agents to build belong to you permanently on your hardware and your devices.

---

## 2. Two Application Distribution Routes

To support both developers and non-developers with zero friction, LeSearch Mesh provides two distinct output paths:

```
                            User Prompt
                  ("Build a habit tracker...")
                                │
                                ▼
                       Agent Task Harness
                (Claude / Codex / Cursor / OMP)
                                │
          ┌─────────────────────┴─────────────────────┐
          ▼                                           ▼
       Route 1                                     Route 2
 [Apple Developer Account]                  [No Developer Account]
          │                                           │
  Native Swift/SwiftUI                       Progressive Web App (PWA)
  XcodeGen (project.yml)                     Local Browser Storage (IndexedDB/OPFS)
  xcodebuild archive                         Offline Service Worker (sw.js)
  Wireless OTA / TestFlight                  Safari Standalone / Add to Home Screen
          │                                           │
          ▼                                           ▼
  Installed Native App                       Installed Web App Icon
 (Deep link: com.aryateja.<slug>://)        (Full screen, offline, zero fees)
```

### Route 1: Native Apple Applications (Apple Developer Account)
- **Target:** Users with an Apple Developer Account.
- **Pipeline:** XcodeGen creates `project.yml` with the user's `DEVELOPMENT_TEAM` and `bundleIdPrefix`. The agent compiles with `xcodebuild`, archives the build, and packages a wireless Over-The-Air (OTA) distribution bundle (`manifest.plist` + `meta.json` + `App.ipa`) or uploads to TestFlight.
- **User Experience:** One tap to install over the air directly onto physical iPhones or iPads via `itms-services://`. Once installed, LeSearch Mesh detects the app via its custom deep link scheme (`com.aryateja.<slug>://`).

### Route 2: Progressive Web Apps (Local-First Storage, No Apple Account)
- **Target:** Users *without* an Apple Developer Account (zero developer fees, zero provisioning).
- **Pipeline:** The agent builds a standalone PWA using modern responsive web technologies, local browser storage (`IndexedDB` / client-side SQLite via OPFS), and an offline Service Worker (`sw.js`).
- **User Experience:** The user opens the local preview link in Safari and taps **Share → Add to Home Screen**. The app installs with a native icon on the home screen, opens full-screen without browser chrome, and operates 100% offline.

---

## 3. Conversational Agent Chat UI (`AgentChatView`)

Rather than forcing users to interact with raw terminal sessions or monochrome ANSI dumps on mobile screens, LeSearch Mesh introduces a native **Agent Chat UI**:

- **Dual-Mode Peek Screen:** A segmented switch `[ Chat | Terminal ]` allows instant toggling between high-level conversational flow and raw terminal output.
- **Collapsible Reasoning:** Agent thinking blocks (`<thinking>`) collapse cleanly into expandable brain-profile disclosures.
- **Interactive Tool Execution:** Visual cards for Bash commands, file reads, and edits with real-time status indicators.
- **Decision Cards:** Prominently highlights approval requests (`Allow? [y/n]`, dangerous shell commands) with green "Allow" and red "Deny" touch targets.
- **Artifact Cards:** Automatically parses `<!-- APP_READY -->` and `<!-- PWA_READY -->` tags to render interactive installation cards.

---

## 4. Specialized Apple Native Capabilities

LeSearch Mesh equips agents with deep domain knowledge of Apple's platform-specific technologies:

1. **Live Activities & Dynamic Island (`ActivityKit`):**
   - Track agent build progress, current tool executions, and pending approvals directly on the Lock Screen, StandBy, and Dynamic Island.
2. **Interactive Widgets & Smart Stack (`WidgetKit` & `AppIntents`):**
   - Quick one-tap widget buttons on iOS and watchOS Smart Stack to trigger agent tasks and view live mesh health.
3. **Siri & App Shortcuts (`AppIntents`):**
   - Zero-configuration Siri voice commands: *"Hey Siri, build an app with LeSearch."*
4. **Interactive Notifications (`UserNotifications`):**
   - Actionable banners with **Allow (Y)**, **Deny (N)**, and **Reply** buttons, operable from Lock Screen or Apple Watch.
5. **WatchConnectivity (`WCSession`):**
   - Bidirectional real-time bridge streaming session states, clipboard sharing, and haptic intervention between wrist and Mac.

---

## 5. Strategy for the First 1,000 Customers

1. **Immediate Out-of-the-Box Value:** Zero setup required for Route 2 (PWAs) — any user can build their first offline-capable home screen tool in under 3 minutes.
2. **Developer Superpowers for Route 1:** Professional iOS engineers can generate native TestFlight / OTA apps from voice briefs on their Apple Watch without opening Xcode manually.
3. **Local Sovereignty:** Users maintain complete ownership of their data, models, and code, eliminating reliance on third-party cloud platforms.
