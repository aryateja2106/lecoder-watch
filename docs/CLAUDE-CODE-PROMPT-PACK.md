# LeSearch Mesh — Claude Code & Cursor Prompt Pack (75% Completion Roadmap)

> **Purpose:** Copy-pasteable, production-ready prompts to feed into Claude Code or Cursor Agent when session limits reset. These prompts guide the agent to complete the remaining 75% of LeSearch Mesh, elevating it from an MVP into a production-grade Local-First Agentic Development Environment (ADE).

---

## 1. Master Context Prompt (Start Here When Launching Claude Code)

Paste this into Claude Code as the opening session prompt:

```markdown
You are the lead systems engineer on LeSearch Mesh (`lecoder-watch`).

MISSION & VALUE PROPOSITION:
- "Less search, more agents."
- We are NOT building another cloud app generator like Lovable or Bolt (no cloud vendor lock-in, no proprietary databases, no subscription compute fees).
- We are NOT building just another mobile SSH client like Termius or Moshi (no living inside monochrome terminal scrollback on phone glass).
- We ARE building the premier Local-First Agentic Development Environment (ADE): empowering users who own powerful local Apple Silicon hardware (M2/M3/M4 Macs) to turn their machines into personal software factories supervised from their iPhone, iPad, and Apple Watch.

CURRENT STATE & PROGRESS:
- We have completed the initial 25% MVP: basic pairing, terminalpeek, initial AgentChatView, and baseline skills.
- The repository is at: `/Users/aryateja/Projects/lecoder-watch`.
- The companion daemon workspace is at: `/Users/aryateja/Projects/devcluster-mesh`.
- Developer Team ID: `B5B87F7AXF` (bundle ID prefix: `com.aryateja`).

OBJECTIVE:
We must implement the remaining 75% of the application to reach production readiness. Follow the explicit directives below, adhere strictly to `CONSTRAINTS.md`, use Swift 5.9+ and modern `@Observable`, and verify every step with `xcodegen generate` and `xcodebuild`.
```

---

## 2. Prompt Directive 1: Business Workflow Tool Scaffolding (CRM & ERP Generator)

Paste this prompt to teach the agent how to build bespoke internal tools:

```markdown
TASK: Implement the Autonomous Business Tool & Niche App Scaffolding Engine in LeSearch Mesh.

BACKGROUND:
Users are confused by abstract "agents". They understand concrete software that solves day-to-day business pain:
- A niche CRM for client followup with local SQLite storage.
- An inventory/ERP tool for warehouse tracking.
- A project invoice & time tracker that operates 100% offline.

SPECIFICATION:
1. Create a scaffold module in `install/payload/agent/scaffold.ts` (or Python/TS daemon module) that accepts a user prompt (e.g., "Build a niche CRM for consulting clients with hourly billing").
2. The module must generate `~/.mesh/apps/<slug>/spec.md` with:
   - Target User & Persona
   - Data Schema (SQLite table definitions for clients, projects, invoices)
   - Three core views: List, Detail/Edit, Metrics Dashboard
   - Realistic seeded sample data
3. Support the dual output paths:
   - If user has Apple Developer account: Output Route 1 SwiftUI + XcodeGen project.
   - If user has no Apple Developer account: Output Route 2 Progressive Web App with IndexedDB & offline Service Worker.
4. Output signal:
   - Emit `<!-- APP_READY slug="<slug>" name="<Display Name>" -->` (for native) or
   - `<!-- PWA_READY slug="<slug>" name="<Display Name>" url="http://localhost:7777/apps/<slug>/" -->` (for PWA).

ACCEPTANCE CRITERIA:
- The generated app runs standalone without requiring network access.
- Seed data is pre-populated so the app feels alive immediately upon installation.
- Verify with `bun test` or automated check script.
```

---

## 3. Prompt Directive 2: Wire-Free Native iOS App Delivery (Route 1)

Paste this prompt to polish wireless Apple OTA & TestFlight distribution:

```markdown
TASK: Productionize Cable-Free Wireless App Installation for Route 1.

BACKGROUND:
Users currently think they need a USB cable to get apps built by agents onto their physical iPhone. In reality, Apple has built-in Wireless Over-The-Air (OTA) distribution and TestFlight APIs.

SPECIFICATION:
1. In `devcluster-mesh/lib/ota-builder.js` and `lecoder-watch/templates/`:
   - Ensure `manifest.plist` accurately references the local HTTPS or Cloudflare tunnel URL:
     `itms-services://?action=download-manifest&url=https://<domain>/releases/<slug>/manifest.plist`
   - Include high-resolution 512x512 app icon (`icon.png`) and `meta.json`.
2. In `iOS/WirelessInstallGuideView.swift`:
   - Verify all instructions for enabling iOS Developer Mode (`Settings → Privacy & Security → Developer Mode`) and trusting the developer certificate (`Settings → General → VPN & Device Management → Developer App → Trust B5B87F7AXF`).
3. In `iOS/AgentChatView.swift`:
   - Ensure the "Install on this Device" button on `ArtifactDetailSheet` triggers `UIApplication.shared.open(installUrl)` directly.
4. Add automated deep linking:
   - When the native app is opened via its custom scheme `com.aryateja.<slug>://`, LeSearch Mesh records that the app was successfully launched.

ACCEPTANCE CRITERIA:
- The wireless installation URL passes XML validation against Apple's Wireless Distribution DTD.
- Tapping Install in LeSearch Mesh on a physical iPhone immediately summons the iOS SpringBoard installation alert: `"[host] would like to install '<App>'"` without any USB cable.
```

---

## 4. Prompt Directive 3: Zero-Account Progressive Web App Engine (Route 2)

Paste this prompt to perfect the zero-fee PWA engine for non-developers:

```markdown
TASK: Perfect Route 2 (Autonomous PWA Generator with Local-First Storage).

BACKGROUND:
Users without an Apple Developer account must have a first-class experience where apps run full-screen, store data locally on their phone, and can be installed in 2 seconds via Safari "Add to Home Screen".

SPECIFICATION:
1. In `.agents/skills/pwa-local-app-builder/SKILL.md` and template engine:
   - Ensure all generated HTML files include Apple mobile web app tags:
     `<meta name="apple-mobile-web-app-capable" content="yes">`
     `<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">`
     `<link rel="apple-touch-icon" href="icon-180.png">`
   - Ensure `manifest.webmanifest` specifies `display: "standalone"`.
2. Service Worker (`sw.js`):
   - Implement Stale-While-Revalidate caching for HTML, CSS, and JS so the app launches instantly offline.
3. Storage Layer:
   - Implement `LocalStorageDB` using browser `IndexedDB` or SQLite WASM in OPFS, ensuring zero data leaves the device.
4. Add to Home Screen Guidance:
   - If the app detects `window.navigator.standalone === false`, display a non-intrusive banner at the bottom: "Tap Share ⎋ → Add to Home Screen ⊞ to install this tool on your iPhone."

ACCEPTANCE CRITERIA:
- The generated PWA passes Google Lighthouse PWA criteria (installable, offline capable).
- Data entered into the PWA survives browser restarts and works without an internet connection.
```

---

## 5. Prompt Directive 4: On-Device Voice Dictation & Local Nemotron Streaming

Paste this prompt to refine voice input and transcription correction:

```markdown
TASK: Polish the Voice Dictation and Transcription Review System.

BACKGROUND:
Users want to speak their instructions naturally while on the move, review transcriptions, make quick corrections, and dispatch commands without manual typing.

SPECIFICATION:
1. In `iOS/VoiceTranscriber.swift`:
   - Verify `SFSpeechAudioBufferRecognitionRequest` handles live partial hypotheses.
   - Verify RMS audio level calculations properly feed the pulsing waveform animation in `VoiceRecordingSheet`.
   - Add support for streaming raw audio PCM to the Mac daemon endpoint (`POST /api/transcribe`) when the user selects "Local Mac Nemotron 3.5 / Whisper".
2. In `iOS/AgentChatView.swift`:
   - In `TranscriptionCorrectionSheet`:
     - Provide quick keyword insertion pills (`SwiftUI`, `XcodeGen`, `PWA`, `IndexedDB`, `TestFlight`, `run tests`).
     - Allow immediate keyboard editing of recognized text before dispatching to the agent.
   - Ensure pressing "Send to Agent" appends a newline and sends the command directly into the active session.

ACCEPTANCE CRITERIA:
- Microphone permissions are requested gracefully with clear user explanations.
- Spoken text appears live in the recording modal.
- User can edit any mistranscribed word before tapping "Send to Agent".
```

---

## 6. Prompt Directive 5: Moshi Comparison & Landing Page Integration

Paste this prompt to build the public comparison page and marketing site:

```markdown
TASK: Build the Moshi vs. LeSearch Mesh Public Comparison Page.

BACKGROUND:
Review `docs/MOSHI-VS-LESEARCH-MESH.md`. We need a public-facing comparison page on our web landing site (`web/compare.html` or `web/index.html`) that positions LeSearch Mesh as the local-first software factory, contrasting directly with Moshi's terminal-only approach.

SPECIFICATION:
1. Implement `web/compare.html` following our brutalist/minimalist brand aesthetic (`web/brand/tokens.css`).
2. Include the comparison matrix:
   - Categories: Session & Agent Runtime, Mobile Experience, App Building Engine, Supervision & Wearables.
   - Competitors: LeSearch Mesh vs. Moshi vs. Claude Code Remote Control vs. Termius.
3. Highlight our 3 key differentiators:
   - **Apps You Keep:** We build native apps and PWAs you own, not just terminal scrollback.
   - **Wrist Supervision:** Native watchOS app with haptic decision approvals.
   - **Local Sovereignty:** 100% private, runs on your own hardware, zero cloud compute fees.
4. Include clear pricing tiers:
   - Community / Local-First: Free forever.
   - Pro: $8/month (Apple OTA wireless signing, APNs push gateway).

ACCEPTANCE CRITERIA:
- The page is mobile-responsive and matches the design tokens in `web/brand/tokens.css`.
- All comparison claims accurately reflect existing features and verified capabilities.
```
