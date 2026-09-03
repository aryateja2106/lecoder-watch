# Scroll-experience research

_Retrieved 2026-08-30. This is design-process research, not an implementation dependency decision._

## Recommendation

Use Scrollcraft's story discipline and QA approach, then build one LeSearch-specific visual
peak: **owned home machine → working agent → attention handoff to Watch and iPhone**.
Do not make the site a long, continuous 3D flight. It would be fragile on mobile and place
the effect ahead of the product story.

## What transfers

- Define four to seven customer-story beats, a feeling curve, one memorable peak, and one
  bespoke interaction before generating assets. [Scrollcraft procedure](https://github.com/nateherkai/scroll-craft/blob/main/plugins/nateherk-design/skills/scrollcraft/SKILL.md)
- Treat each scroll position as a test state: desktop/mobile, reduced motion, contrast over
  motion, dead scroll, failed video load, and keyboard focus. [Scrollcraft verification](https://github.com/nateherkai/scroll-craft/blob/main/plugins/nateherk-design/skills/scrollcraft/references/verify.md)
- If a scrubbed-video peak is justified, begin with a poster, lazy-load it, supply a mobile
  composition, and keep a graceful fallback. [Scroll-world README](https://github.com/oso95/scroll-world#readme)
- Reuse one art-direction preamble across supplementary imagery, but make real redacted
  product captures the proof.

## What does not transfer

- Do not copy source wording, examples, prompt libraries, visual identity, template counters,
  generic AI gradients, or clay-diorama aesthetics.
- Do not bake landing copy into generated images; keep it accessible HTML.
- Do not budget from the projects' generation-cost examples; providers and availability change.
- Do not use an asset-provider workflow without checking commercial terms for generated assets
  and fonts.

Both reference repositories are [MIT licensed (Scrollcraft)](https://github.com/nateherkai/scroll-craft/blob/main/LICENSE)
and [MIT licensed (Scroll-world)](https://github.com/oso95/scroll-world/blob/main/LICENSE).
Retain notices if substantial code or documentation is copied; neither license grants rights to
third-party assets, trademarks, or provider outputs.
