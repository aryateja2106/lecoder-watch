---
status: draft
owner: Arya
source: conversation
date: 2026-09-27
---

# Intent: The app looks the way I picture it, so I can put it in front of a client without apologising

## Problem

In my words: "I have a certain design theme in mind which I want us to bring inside the
application which I am not able to communicate properly … getting overwhelmed on what to show
where, compromising on design elements because they are functional, and that is stopping me from
getting new clients."

The app has no written-down look. Four different themes exist in the repository at once, each
made by a different agent session for a different reason, and nobody ever chose between them:

- a near-black monochrome with one blue accent (the June redesign mockups in
  `.agents/design/design-system.html` and the brief `.agents/REDESIGN-BRIEF.md`; never merged
  into the app);
- a grey, all-monospace brand (`web/brand/TOKENS.css`, also used by `web/privacy.html`);
- today's landing page, near-black with one orange accent (`web/index.html`);
- a light, editorial landing direction that survives only as a screenshot in an old commit.

The iPhone and Watch apps use none of them. They use Apple's default colours, so the app's
accent is iOS system blue by accident, not by decision. `docs/product/design-system.md` says
plainly that there is no design-token file.

One concrete example: in the chat screen (`docs/product/shots/iphone-chat.png`) my own message
is an orange bubble, because orange is Claude's brand colour in `iOS/AgentChatView.swift`. In the
rest of the app orange means "an agent needs you right now", and on the website orange is the
main button. So the one signal that matters most looks like decoration. A second example: on the
watch Control screen (`docs/product/shots/watch-control.png`) the controls sit on top of the
screen preview. And the default terminal theme is named after a competitor ("Moshi", in
`iOS/NativeTerminalScreen.swift`) and is visible in the theme picker.

Because nothing is decided, every agent reaches for "functional" defaults, and each new screen
drifts a little further from what I have in mind.

## Proposed outcome

- My theme is written down once, in words I approved, with one value for each decision (light
  or dark, background, brand colour, what colour means "needs you", type, corners, density,
  glass, motion, haptics).
- The first screen a new customer sees looks like that theme on a real iPhone, and I have
  approved it by looking at before-and-after screenshots.
- For each screen, it is decided what is shown first and what is hidden until asked, so "what to
  show where" stops being a daily question.
- Agents write new screens on-theme by default, and something automatic notices when a screen
  drifts off it.
- The website and the app either share the look or differ on purpose, and I decided which.
- I can show a client a two-minute walkthrough without apologising for how it looks.

## Affected users and systems

iPhone app, Apple Watch app, Mac menu-bar app (later), the landing site and its screenshots
(the website reuses the app's screenshots), and the agents' UI instruction pack
(`.agents/skills/meshwatch-ui-taste/SKILL.md`, which today names colour roles but no palette).
Everyone who opens the app, and every prospect I demo it to.

## Constraints

- Colour meanings the app already relies on: orange = needs you, red = destructive or error,
  green = working (`docs/product/design-system.md`). Changing any of them is a deliberate
  decision, not a side effect of a new brand colour.
- Interaction rules pinned by existing self-checks (safe text fields, the watch key strip, chord
  sequences, trackpad taps) must keep working; a restyle is visual only.
- Apple's review rules and platform conventions (iOS 26 glass bars, Dynamic Type, accessibility
  contrast) apply. Light and dark mode both reach users today, because the app follows the
  phone's setting.
- My reference images (`Reference-images/`) and some committed screenshots show personal or
  infrastructure details (a private network address, a user@host, an on-screen sign-in code that
  has since expired). They are already in this public repository's history; whether to remove
  them from the tree is my decision (see Open questions). They guide the look; nothing copies
  their values into a file.
- Frozen names (`MeshWatch`, `com.lecoder.*`) stay as they are; only visible branding changes.
- Small first step: one theme file, one screen, one check, one screenshot pair. No new
  third-party UI library.
- Revenue first: the goal is a demo that closes clients, not a full redesign of every screen.

## Open questions

Condensed from the 20-question design interview of 2026-09-27; the full script with example
answers is the appendix of `intents/INTERVIEW.md`, which the plans session follows. Answer with a word, an
app name, or a reference image; examples are only there to make answering easy.

1. Who should feel "this was made for me" the first time they open it: someone scared of
   Terminal, a developer who lives in it, a founder who runs agents but is not a coder, or both
   with the scary parts hidden?
2. Two or three apps whose look you wish this app had (for example Things 3 or Linear, Apple
   Fitness, Warp or Ghostty, Arc or Raycast).
3. Light, dark, or both? Same answer for the website?
4. Which existing look is closest to what is in your head: the June mockups, the old grey
   monospace brand, today's orange landing page, or the light editorial landing?
5. One brand colour for "this is LeSearch" and the main button: blue, orange, green, or black and
   white only with colour reserved for status?
6. What should mean "an agent needs you right now", given that orange is also Claude's colour?
7. Type: Apple's font with mono only in the terminal, mono everywhere, a bold headline font, or
   rounded and friendly?
8. Density: a dashboard, few big calm things, busy only in the terminal, or one decision per screen?
9. The terminal: deep green, navy, pure black, or matching the rest of the app? And should the
   theme named "Moshi" be renamed?
10. Glass and blur: Apple's glass where Apple uses it, glass menus as part of the look, or solid
    surfaces only?
11. Corners and shapes: soft and round, slightly rounded, square, or Apple's default?
12. Agent colours (Claude orange, Codex green, Cursor blue, Antigravity purple): keep, shrink to
    a small icon, remove, or use each agent's real logo? And what should your own chat message
    look like?
13. Motion and haptics: almost none, small confirmations, lively while agents work? Should the
    iPhone buzz on approve, send or stop?
14. Which one screen must a new customer love in the first ten seconds: Machines, the agent
    chat, the terminal, or the watch "nothing waiting on you" home?
15. What compromise hurts most today: default Settings-page look, too much small text, random
    colours, cramped watch screens, or something else?
16. Anything off-limits (purple or neon glow, monospace body text, emoji, stock illustrations)?
17. Who decides the look is right: you approving screenshots, an agent checking against the
    theme file with your spot-check, a day of using it on your phone, or a target user?
18. Should `Reference-images/` and the screenshots that show a private address or a user@host
    be removed from the public repository (they stay on disk as guides), or left as they are?
