---
name: lesearch-mascot
description: Create or extend a consistent LeSearch Mesh companion mascot. Use when the user requests a LeSearch mascot, character, agent companion, mascot variants, or mascot review; do not use for the primary logo, app icon, or product UI.
---

# LeSearch Mesh Mascot

Create a companion IP that personifies the attention handoff: it brings one question from an
owned machine to the person, then waits for an intentional answer. It is a calm night-shift
companion, not the agent itself, a search assistant, or an autonomous operator.

The existing orbital/node mark remains LeSearch Mesh's primary identifier. A mascot is secondary
campaign, onboarding, or support art; never replace the mark, redraw it as a face, attach limbs
to it, or use a mascot as an app icon or lockup.

## Read the product first

Before proposing a new mascot, read these project sources when available:

- `launch/BRAND-KIT.md` for the locked name, mark hierarchy, tokens, and asset rules.
- `launch/BRIEF.md` for product truth and the attention-handoff story.
- `web/brand/tokens.css` and `web/logo.svg` for the current visual system.

If they do not establish the product, audience, and intended use, ask one consolidated question.
Otherwise, proceed without a branding questionnaire.

## Direction before generation

When the user has not approved a mascot direction, propose exactly three concise directions:

`<subject> — <attention-handoff connection> — <defining rounded silhouette>`

When no subject is supplied, make the three directions distinct product lenses: an attention
courier, a bounded node keeper, and a pocket operator. Prefer familiar animals with a real reason
to fit the lens. Do not propose a generic robot, cloud creature, lightning bolt, rocket, magical
assistant, surveillance character, or arbitrary animal.

End by offering six independent square candidates: `A1`, `A2`, `B1`, `B2`, `C1`, and `C2`. Do not
generate until the user accepts that batch or explicitly asks to proceed with six outputs.

## Continuity contract

For every approved direction, preserve these rules across poses and future variants:

- One compact, friendly silhouette built from 4–7 large rounded shapes; no sharp or fragile parts.
- A simple face: two eyes and at most one tiny mouth. Do not add texture, labels, terminal text,
  decorative marks, or detailed anatomy.
- Upright lower-corner composition: `A1`, `B1`, and `C1` emerge from lower-left; `A2`, `B2`, and
  `C2` from lower-right. The character occupies about 85–95% of its square.
- Default palette: `#191919` background, `#e9e9e7` character, and one semantic signal. Use
  `#4ade80` for a healthy/continue state; use `#bd3038` only for a blocked or destructive state.
  Never use both status colors in one candidate or make either a decorative personality color.
- Keep the mascot mostly monochrome. Put the single accent in one node, wrist signal, or carried
  question-token—not across the whole character.
- Preserve generous negative space and the calm, capable, local-first tone. Never imply a cloud
  relay, universal remote access, autonomous approval, or a capability the beta does not prove.

## Generate only after approval

Use the runtime's highest-quality supported image generator. In Codex, use the built-in image
generator; do not silently switch to a CLI, API key, or lower-quality provider. If it is not
available, return the directions and state the missing capability.

Generate each candidate as a separate full-resolution square—not a contact sheet. Assign one
direction and one corner to each candidate. Use the prompt skeleton in
[`references/generation.md`](references/generation.md) after substituting only the subject,
direction, corner, and permitted signal color.

Treat the batch as a creative draw: preserve all six returned files, do not rank, discard,
post-process, or automatically retry any result. A refinement is a new explicit user request.

For project-bound work, save every candidate and a short manifest under
`web/brand/mascots/<brief-slug>/`. The manifest records label, direction, corner, prompt,
three-color mapping, dimensions, and the continuity contract. Do not wire a mascot into the
website, native app, product logo, or app icon unless the user separately asks.

## Review or extension

When given an existing selected mascot, inspect it before proposing changes. Keep its chosen
subject, silhouette grammar, face, corner behavior, and palette mapping unless the user asks to
change one. State the preserved rules and the one requested change before generating variants.

This method is locally adapted from the MIT-licensed IP as Logo skill. Read
[`references/upstream-attribution.md`](references/upstream-attribution.md) when distributing or
substantially revising the adaptation.
