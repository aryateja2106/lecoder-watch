# Landing page redesign specification

Status: implementation-ready structure, with explicit launch gates. The current static
`web/index.html` remains the implementation base. This spec does not authorize a framework
migration, new product claims, analytics, generated product UI, or publication of uncleared
assets.

## Direction

**Purpose:** show that a long-running agent can ask for attention and receive a deliberate
answer without keeping its operator at the desk.

**Aesthetic:** a calm night-shift instrument panel. Dense product detail appears only where it
proves something; the surrounding page is spacious, direct, and readable by technical
non-developers. It should feel like owned hardware under control, not a cloud-AI spectacle.

**Memorable move:** one attention signal crosses a real host session, a Watch-sized decision,
and a continued session as the visitor scrolls. The signal is an explanatory hairline and
status pulse, not a representation of network topology.

**Technical floor:** semantic HTML, the current inline CSS and small vanilla JavaScript, real
redacted captures, and native CSS sticky positioning. No WebGL, canvas, animation library,
new build step, device-rendering pipeline, or page framework.

The archived large-headline / overlapping phone-and-watch composition may inform proportion
only. It is Meshwatch-branded, contains older UI and claims, and is not an implementation or
asset source. Everything under the archived `design-concepts/` and `public/product/` folders is
reference-only and requires provenance, redaction, and current-state validation before reuse.

## Launch decisions and gates

The naming decision is locked below. The remaining gates block final copy, asset approval, or
deployment, but do not block local markup and CSS work.

1. **Name:** **LeSearch AI** is the company and **LeSearch Mesh** is the one public product
   name across the website, native apps, legal pages, metadata, and exports. Keep legacy
   `MeshWatch` technical identifiers stable until a separate migration is approved.
2. **Attention-loop claims:** physically prove the notification, risk-labelled action, session
   match, and continuation on current iPhone and Apple Watch builds. Until that proof exists,
   use beta-qualified language and avoid “the actual question,” “tap Continue and it carries
   on,” or equivalent absolute outcomes.
3. **Primary action:** approve one label and destination. The safe current default is the
   existing TestFlight destination; do not invent a waitlist or purchase flow.
4. **Asset clearance:** approve a sanitized, current three-frame handoff set. The set must show
   one reproducible harmless session across all frames. No generated terminal text, personal
   hostnames, paths, repositories, URLs, tokens, auth screens, or private prompts.
5. **Routes:** verify ownership and live behavior for `lesearch.ai`, `mesh.lesearch.ai`,
   `/privacy`, `/install.sh`, GitHub, TestFlight, and the current Vercel catch-all before
   deployment. This redesign does not change DNS or redirect policy.
6. **Privacy:** keep the landing free of PostHog, surveys, session replay, cookies, and other
   analytics while the public policy says they are absent. Instrumentation requires one prior
   decision updating the event allowlist, consent or opt-out behavior, privacy copy, daemon
   telemetry promise, and App Store disclosures together.

## Safe to implement now

- Add a skip link, semantic navigation, `<main>`, labelled sections, and a single `<h1>`.
- Rework the page into the information architecture below without changing destinations.
- Raise low-contrast small text, correct the red risk-control contrast, and preserve the
  current visible focus treatment.
- Reduce the first proof set to the three strongest current cleared captures; keep the other
  two available below the fold only if each adds distinct proof.
- Build the attention-handoff markup, base static layout, mobile stack, and reduced-motion
  state. Keep all states visible without animation.
- Add the CSS sticky/scroll-timeline enhancement only inside a feature query, after the static
  state is complete.
- Add a copy-status live region and a clipboard failure state.
- Remove the Google Fonts request when approved local font files are available. Do not replace
  it with another third-party font request.

## Information architecture

Use this reading order. A section that does not advance one of these beats is cut.

| Order | Section | Visitor belief | Required proof |
| --- | --- | --- | --- |
| 1 | Header | This is LeSearch AI's current beta product. | Product name, three anchors at most, one beta action. |
| 2 | Hero | I can supervise agents on machines I own without staying at the desk. | Plain beta/network boundary and one real phone/watch composition. |
| 3 | Attention handoff | A task can ask for me, reach a small surface, and continue after a deliberate answer. | One current sanitized session across three verified frames. |
| 4 | Product proof | I can see the fleet, read a live session, and use a larger control surface when needed. | Machines, iPhone terminal, and Watch terminal captures. |
| 5 | Setup | I understand what runs on my machine and how pairing works. | Existing install, pair, and hook commands with current output only. |
| 6 | Boundary | I know what is direct, what uses APNs, what the heartbeat sends, and when LAN/VPN is required. | Precise privacy link and reachable-network caveat. |
| 7 | Beta truth / FAQ | I know current requirements, limitations, and project maturity. | Existing requirements, roadmap, changelog, and qualified capability answers. |
| 8 | Close | I know the one next action. | The approved action repeated verbatim. |

The current six equal feature cards do not belong in the primary story. Convert the useful
content into a compact two-column capability list after product proof, or move it into FAQ
answers. Do not add a new card grid.

## First-scroll story

### Header

- Keep it one line at desktop and compact on mobile.
- Show the approved product name once; establish “by LeSearch AI” in subdued text rather than
  creating a second competing logo.
- Navigation: `How it works`, `Privacy`, and the primary beta action. GitHub may remain a text
  link if the public-source claim and destination are verified.
- The sticky header must not cover anchor targets; use `scroll-margin-top` on sections.

### Hero

- Lead with the outcome, not terminal installation. The first screen should name agent
  supervision, owned machines, iPhone/Watch, and the LAN/VPN boundary in ordinary language.
- Keep one headline, one paragraph no wider than 62 characters, one primary action, and one
  secondary text link. Do not use a pill badge, animated scroll cue, section counter, or
  gradient headline.
- The current install terminal moves below the first proof moment or into Setup. Installation
  is evidence, but it currently makes the product read as developer-only before the visitor
  understands the benefit.
- The hero product composition may overlap one iPhone and one Watch capture. Use only current,
  cleared screenshots and let the Watch interrupt the phone silhouette optically. Do not add a
  MacBook render merely to fill space.
- First paint is complete without animation. No hero text starts hidden.

### Attention handoff

Place this directly after the hero and replace the current `#moment` three-card row.

The section contains a short introduction followed by one sticky stage. On desktop, the text
column stays fixed while one evidence composition changes through three states:

| Progress | State | Visible evidence | Copy job |
| --- | --- | --- | --- |
| 0–30% | Running | Sanitized host/session frame, calm neutral status. | “The task keeps running on a machine you own.” |
| 30–68% | Needs you | The same session identifier and question on a current Watch capture. The host frame recedes but stays legible. | “When it needs a decision, the question gets smaller, not lost.” |
| 68–100% | Answered | A verified response state and the same host/session visibly continuing; show iPhone only when more room genuinely adds proof. | “You answer deliberately. The session continues.” |

The sentences above describe each copy job, not approved public copy. Final wording inherits the
claim gate.

#### CSS-native mechanism

- Base markup is three sequential `<article>` elements inside the section. This is the mobile,
  reduced-motion, unsupported-browser, print, and screen-reader experience.
- At `min-width: 820px`, set the section to approximately `260dvh` and its stage to
  `position: sticky; top: var(--header-height); min-height: calc(100dvh - var(--header-height))`.
  This is long enough for three readable states but short enough to avoid dead scroll.
- Apply overlays only under
  `@supports (animation-timeline: view()) and (animation-range: entry 0% cover 100%)`.
  The section owns a block-axis view timeline; state layers animate with `opacity`, `transform`,
  and at most one `clip-path`. Do not animate dimensions, offsets, blur, or shadows.
- State one is fully visible at section entry. State windows overlap by roughly 10% so the stage
  never becomes empty. State three reaches full opacity before the final 15% and holds through
  the section exit.
- A one-pixel route line remains structural. One small status pulse travels host → Watch during
  state two, then Watch → host during state three. Green appears only after the verified answer;
  blocked or destructive states use the existing red role. The line must not be labelled as a
  network path.
- Do not use scroll event handlers. Existing JavaScript remains limited to copy feedback and
  non-essential entrance observation. If CSS scroll timelines are unsupported, the semantic
  stacked layout is the finished fallback.
- No animation may be required to reveal text, controls, or the meaning of the sequence.

#### Asset contract

The handoff sequence is not publishable until all three required frames exist:

| Asset | Source rule | Validation |
| --- | --- | --- |
| Host running frame | Fresh capture from a current harmless demo session. | Same sanitized session label used in all three frames; terminal text manually reviewed. |
| Watch needs-you frame | Fresh physical-device or current simulator capture of the same event. | Action labels and risk treatment match the shipping beta; physical notification/action behavior checked by a human. |
| Continued session frame | Fresh capture after the verified response. | Output proves continuation without exposing generated or private content. |

Do not synthesize missing frames, alter terminal lines, or combine unrelated current screenshots
and describe them as one flow.

## Proof asset mapping

Use existing files in place; do not create another duplicate set.

| Story role | Current candidate | Treatment |
| --- | --- | --- |
| Multi-machine overview | `docs/screenshots/iphone-69_01-machines.png` | Canonical source; the current `web/shots/` copy may be used by the page after hostname/status review. |
| Live session detail | `docs/screenshots/iphone-69_03-terminal-live.png` | Read every visible line before publication. Present as live terminal proof, not the synchronized handoff unless it is the same recaptured session. |
| Wrist terminal | `docs/screenshots/watch-ultra_04-terminal.png` | Use at its natural scale with a concise caption; do not imply text is legible from a decorative thumbnail. |
| Secondary remote control | `docs/screenshots/iphone-69_07-remote.png` | Below the core proof only; qualify host support. |
| Secondary Watch fleet | `docs/screenshots/watch-ultra_02-machines.png` | Use only if it adds proof not already carried by the iPhone machine list. |

The 133.7-second recording and `Reference-images/` remain private inputs until frame-by-frame
review. They are not landing assets. Every meaningful image gets dimensions, a concrete alt
description, and a caption that states what the capture proves. Decorative bezels get no
separate accessible name.

## Typography and visual system

- Recommend **Instrument Sans** for headlines and narrative copy, subject to launch-brand and
  font-license approval. Its job is to make the explanation approachable without losing the
  product's technical precision.
- Keep **JetBrains Mono** for commands, terminal output, machine/session labels, compact status,
  and tabular values only. Long paragraphs do not use mono.
- Self-host approved WOFF2 files with `font-display: swap`; remove Google Fonts preconnects and
  requests. System sans and monospace stacks remain fallbacks.
- Two families maximum. Headings use tight tracking and balanced wrapping; body copy uses
  `text-wrap: pretty`, a 45–65ch measure, and at least 1.55 line height.
- Retain the near-black, cool-gray foundation, one 8px corner scale, thin utility lines, and
  restrained depth. Avoid purple/blue AI gradients, neon, glossy glass, floating icon cards,
  and decorative 3D.
- Green means affirmative/online/continued. Red means blocked/destructive/stop. Neither becomes
  ambient decoration.
- Small narrative text must not use the current low-contrast `--ink-3`. Adjust the semantic
  muted-text role until it reaches 4.5:1 on every surface; controls and focus indicators reach
  at least 3:1. Correct the current small white-on-red risk action at the token level.

## Mobile and reduced motion

- At widths below 820px, remove the sticky timeline entirely. Render the three handoff articles
  as an ordinary vertical sequence with the evidence before its explanatory copy.
- Test at 320px and 390px with no horizontal overflow. Minimum tap target is 44×44 CSS pixels;
  actions never depend on hover.
- Use `min-height: 100dvh`, not `100vh`, for any viewport stage. Respect safe-area insets where
  the sticky header or final action approaches an iPhone edge.
- A Watch capture may overlap a phone capture only above 820px. On narrow screens each figure
  owns its own row; no crop may hide product controls or captions.
- Under `prefers-reduced-motion: reduce`, use the same stacked layout at every width. Preserve
  short opacity feedback for controls, but remove the traveling pulse, spatial transitions,
  parallax, blinking caret, and sticky scroll span.
- The page remains coherent with CSS disabled: headings, copy, images, commands, disclosures,
  and links keep their source order.

## Semantics and accessibility

- Source order: skip link → `<header>` / labelled `<nav>` → `<main>` → page sections →
  `<footer>`. The hero and final action belong inside `<main>`.
- One `<h1>`. Every section has an `<h2>` connected with `aria-labelledby`; state articles use
  short `<h3>` headings. Do not use presentational numbering as accessible names.
- All links retain native link behavior and all commands remain selectable text. Use
  `<button type="button">` for Copy. Do not apply click handlers to cards or figures.
- Copy success and failure write to one visually unobtrusive `aria-live="polite"` region. Return
  button text after feedback without moving keyboard focus.
- Maintain visible `:focus-visible` styling, logical tab order, and usable native `<details>`.
  The sticky sequence contains no focusable element whose position changes during focus.
- Meaningful images have useful `alt`; captions must not duplicate the alt word for word. If a
  screenshot's text is necessary to understand the claim, repeat that meaning in adjacent HTML.
- At 200% zoom, no text clips, overlaps the sticky header, or requires two-dimensional scrolling.

## Copy and claim rules

- State the network boundary on the first screen: operation requires a reachable LAN or a VPN
  the customer already uses. Do not imply a LeSearch relay or universal “access from anywhere.”
- Use “no account or relay server in the session data path,” not “we operate no server” or “we
  collect nothing.”
- Keep the exact daemon heartbeat and APNs distinctions consistent with `web/privacy.html` and
  the README. Link to the exact payload instead of compressing it into “nothing leaves.”
- Say beta wherever a reasonable visitor could mistake a roadmap capability for a production
  guarantee. Do not invent usage numbers, customer logos, testimonials, security certification,
  pricing, or availability.
- Do not claim that every agent is natively integrated. Distinguish the installed Claude Code
  hook from the generic events endpoint and any separately verified integration.
- Avoid jargon before proof. “Machine you own,” “private network,” and “asks for a decision” come
  before daemon, multiplexer, hook, APNs, or bearer token.

## Performance and implementation limits

- Keep the redesign within `web/index.html` plus approved local fonts and sanitized image files.
  Reuse the existing CSS variables and vanilla scripts; do not introduce a package manifest.
- No autoplay media is required. The signature sequence uses still captures and CSS only.
- Hero media is eagerly available and dimensioned. All below-fold screenshots use native lazy
  loading and explicit width/height.
- Base content is visible before enhancement. JavaScript failure, font failure, unsupported
  scroll timelines, or reduced motion must not produce an empty stage.
- Preserve current public routes until the route decision is verified. Do not encode a new
  hostname into visual assets.

## Acceptance criteria

Implementation is ready for launch review only when all of the following are true:

- [ ] The page is still static HTML/CSS with only small dependency-free JavaScript; no new
  framework, runtime package, WebGL, canvas, or animation library exists.
- [ ] The first viewport names the current beta outcome, owned-machine model, iPhone/Watch
  surfaces, and LAN/VPN boundary without an unproved capability claim.
- [ ] The old three-card `#moment` is replaced by one semantic attention-handoff sequence.
- [ ] The sequence uses one freshly captured, sanitized session across all states; physical
  Watch/iPhone notification and response behavior has a recorded human verification.
- [ ] With scroll-timeline support, desktop shows three readable states with no empty stage,
  frozen final state, focus movement, or dead scroll. Without support, all states appear in a
  complete static sequence.
- [ ] Mobile and reduced-motion layouts do not use sticky positioning and do not hide any state.
- [ ] Product proof uses real current captures; archived concepts, reference screens, and the raw
  recording are not shipped as current product evidence.
- [ ] Only approved product/company names and one approved beta-action label appear.
- [ ] Every capability sentence agrees with the current README, roadmap, shipping daemon/app,
  and privacy page; uncertain behavior is qualified as beta.
- [ ] No analytics, replay, survey, cookie, or unapproved third-party font request is added.
- [ ] Skip link, nav, main landmark, heading order, image alternatives, focus states, clipboard
  live feedback, and native disclosures pass a keyboard and screen-reader smoke test.
- [ ] Normal text meets 4.5:1 contrast; large text, controls, and focus indicators meet 3:1.
- [ ] At 320, 390, 768, and 1440px there is no horizontal overflow, content overlap, cropped
  control, or unreadable terminal proof. The page remains usable at 200% zoom.
- [ ] All production destinations resolve as intended: root, privacy, install script, GitHub,
  TestFlight, changelog, roadmap, and company site.
- [ ] Fresh desktop, mobile, and reduced-motion screenshots have been reviewed at the start,
  midpoint, and end of the sticky section, and Safari has been checked on an iPhone-class device.

Stop condition: the live first scroll proves one current attention handoff, all claims match
tested beta behavior, privacy and routes remain true, and the static fallback is as complete as
the enhanced version.
