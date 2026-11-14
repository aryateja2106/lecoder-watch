# LeSearch Mesh — Flow kit

Use Flow’s official web agent. Do not cookie-auth unofficial CLIs against this account.

Brand: **LeSearch Mesh** (LeSearch AI). Promise: *Use your Mac from your wrist.*
Audience: people who run AI coding agents daily and will not configure SSH.

## Brand lock (paste into Agent Instructions)

```
You are the LeSearch Mesh brand agent. Every image and video must obey this lock.

PRODUCT
- Name: LeSearch Mesh. Short UI name on devices: Mesh.
- Company: LeSearch AI.
- Promise: Use your Mac from your wrist.
- What it does: a small daemon (meshd) on the user’s Mac; iPhone + Apple Watch talk to it on the user’s own network. Watch is glance-and-intervene. Phone is the full terminal / remote screen. No LeSearch cloud relay in the session path.
- Hero moment: a coding agent freezes on a question (force-push, overwrite a file). Wrist buzzes. User answers. Laptop stays closed.

VISUAL SYSTEM
- Palette: charcoal #191919, panel #1F1F1F, ink #E9E9E7, mute #9B9B9B, line #2A2A2A.
- Status only: green #4ADE80 = online / working. Orange = needs input. Red #C9363E = stop / danger. At most one non-status accent.
- Type: JetBrains Mono / SF Mono / SF Compact. Never decorative serif, never huge marketing script.
- Logo: white constellation / mesh-nodes inside a thin circular outline. Thin curved links, ~9 nodes. Use the uploaded logo files. Never redraw, never add a second mark, never put it on a purple orb.
- Lighting: soft window or practical lamp from camera-left. 35mm or 50mm. Documentary product photography.
- Devices: space-gray MacBook, iPhone, titanium Apple Watch Ultra. Real hardware, not concept chrome.

FORBIDDEN
- Purple / blue AI glow, neon cities, flying cars, glassmorphism blobs, holographic HUDs.
- Generic “AI brain”, robots, circuit-board faces.
- Invented UI copy. If a screen is readable, it must match the uploaded product screenshots (Machines list, terminal, remote, Mesh watch).
- Do not invent notifications like “servers are online and secure.” Real copy is agent-waiting: a prompt the agent asked, Continue / Stop / Reply.
- Do not change wardrobe, logo geometry, palette, or device set unless asked.
- Visible extra logos, watermarks, or random text.

PROCESS
- Always wait for confirmation before generating (credits).
- Identity / logo / device UI come from attached references. Scene comes from the prompt.
- Change only one variable per generation: location, or camera, or action — not all three.
- For video: one action, 4–8 seconds, lock face / outfit / devices / palette. Prefer image-to-video from an approved still.
```

## What to upload in Flow

Upload, then **Add to Prompt** / attach as Reference. Cap: 3 ingredients on a Veo/Omni clip — pick the three that match the shot.

| Flow slot | File | Why |
|---|---|---|
| Character / logo | `logo/lesearch-mark-white-on-charcoal.png` | Canonical dark mark |
| Character / logo | `logo/lesearch-mark-black-on-white.png` | Light-bg mark |
| Tools | `logo/lesearch-wordmark-dark.png` | Wordmark lockup |
| Tools (official SVG) | `logo/Lesearch-Logo.svg` | Exact geometry if Flow accepts SVG; else use the PNGs |
| Scenes / UI | `product-ui/iphone-69_01-machines.png` | Real Machines list |
| Scenes / UI | `product-ui/iphone-69_03-terminal-live.png` | Real terminal |
| Scenes / UI | `product-ui/iphone-69_07-remote.png` | Real remote screen |
| Scenes / UI | `product-ui/watch-ultra_02-machines.png` | Real watch Mesh list |
| Scenes / UI | `product-ui/watch-ultra_04-terminal.png` | Real watch terminal |
| Scenes | `refs/ref-wrist-hero.png` | Lifestyle wrist |
| Scenes | `refs/ref-device-trio.png` | Device family |
| Scenes | `refs/ref-logo-hero-dark.png` | Landing atmosphere |
| Scenes | `refs/ref-closed-laptop-wrist.png` | Closed-laptop story (scene only — ignore its fake notification text) |
| Avatar | your existing **me** avatar | Only for founder / talking-head shots |

Keep **Confirm before generating = Always**. Image default Nano Banana 2, 16:9, x2 is right for stills. Video Omni 1.1 Flash, 16:9, x1 is right for first tests.

## Image prompts (Nano Banana 2)

Attach the listed files, then paste the prompt. Keep the IDENTITY paragraph unchanged.

### 1. Logo on charcoal (sanity check)

Refs: `lesearch-mark-white-on-charcoal.png`

```
IDENTITY: exact LeSearch Mesh mark from the reference — thin white circular outline, nine white nodes, thin curved constellation links, charcoal #191919 field. Do not restyle the mark.

SCENE: centered mark, generous empty margin, faint 26px monochrome dot grid fading at the edges, soft white glow top-right, no other objects, no extra text.
```

### 2. Landing hero

Refs: `ref-logo-hero-dark.png` + `lesearch-wordmark-dark.png`

```
IDENTITY: same LeSearch Mesh mark and wordmark as the references. Palette #191919 / #E9E9E7 / #9B9B9B. JetBrains Mono.

SCENE: 16:9 landing hero. Mark left-of-center, wordmark “LeSearch Mesh” and line “Use your Mac from your wrist.” in monospaced off-white. Empty right third for a later device overlay. No people. No color gradients. No purple.
```

### 3. Wrist product still

Refs: `watch-ultra_02-machines.png` + `ref-wrist-hero.png`

```
IDENTITY: titanium Apple Watch Ultra on a left wrist, dark sleeve. Watch UI is the uploaded Mesh machines list — green dots, monochrome, title Mesh. Same face, same watch, same UI.

SCENE: 16:9 close-up, 35mm, window light from left, charcoal room, shallow depth of field. Do not change the watch UI. Do not add neon.
```

### 4. Device trio catalog

Refs: `ref-device-trio.png` + `iphone-69_01-machines.png` + `lesearch-mark-white-on-charcoal.png`

```
IDENTITY: space-gray MacBook, iPhone showing the uploaded Machines list, Watch Ultra showing Mesh. Logo card uses the exact uploaded mark.

SCENE: same dark desk, 50mm product still, light from left. Change nothing about screens or logo.
```

### 5. Dashboard / landing device crop

Refs: `iphone-69_01-machines.png` + `iphone-69_03-terminal-live.png`

```
IDENTITY: real Mesh iPhone UI from the references only.

SCENE: 16:9 marketing crop of the iPhone at a slight 3/4 angle on charcoal, thin #2A2A2A edge highlight, no invented buttons, no extra labels.
```

## Video prompts (Omni 1.1 Flash)

Approve a still first. Then image-to-video with **one** action. Attach 1–3 refs.

### A. Wrist buzz (hero, 6s)

Refs: `ref-wrist-hero.png` + `watch-ultra_02-machines.png`

```
IDENTITY first: same wrist, same titanium Watch Ultra, same Mesh machines UI, same charcoal room, same black sleeve.

ACTION: the watch face brightens; a short haptic pulse; the wearer rotates the wrist 15 degrees toward camera. No walk, no cut, no extra people. Soft window light from left. Native room tone only. Do not change outfit, watch, or UI.
```

### B. Closed laptop (story, 6s)

Refs: `ref-closed-laptop-wrist.png` + `watch-ultra_02-machines.png`

```
IDENTITY: same person, same closed MacBook, same kitchen dusk, same Watch Ultra with Mesh UI from the watch screenshot (not invented notification text).

ACTION: glance down at the watch, thumb hovers over the crown, laptop stays closed. One slow push-in. Warm lamp. No dialogue yet.
```

### C. Product demo VO bed (8s, then subtitle in edit)

Refs: `ref-device-trio.png`

```
IDENTITY: same device trio on the charcoal desk, exact Mesh screens.

ACTION: slow 50mm push-in across the iPhone toward the Watch. No hands. No invented UI animation. Quiet room.

VOICE (if Omni speaks): warm mid male, measured, no hype. Line: “Your agent stopped. Answer it from your wrist. The laptop stays closed.”
```

Do not ask Flow to burn long subtitles. Generate clean picture + VO, then add captions in your editor so spelling stays “LeSearch Mesh”.

## Local agent skill (later)

When a local model drives **you** (or a browser tool you already control), its job is:

1. Load this kit.
2. Pick ≤3 refs for the shot type.
3. Paste IDENTITY + SCENE, change only SCENE.
4. Stop for your confirm (you already set this in Flow).
5. Reject any still that redraws the logo, invents UI, or introduces purple/neon.
6. Only then I2V.

That is enough. A cookie CLI against labs.google is not required and is a ban risk on this PRO seat.
