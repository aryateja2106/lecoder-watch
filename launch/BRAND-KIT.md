# LeSearch Mesh brand kit

Status: launch baseline, locked 3 September 2026. This keeps the proven identity intact and
adds only the assets the public site is missing.

## Naming

| Role | Exact form |
| --- | --- |
| Company | LeSearch AI |
| Product | LeSearch Mesh |
| Tagline | Less Search. More Agents. |

Use `MeshWatch` only where an existing Xcode target, bundle identifier, module, or legacy path
requires it. It is not public campaign or product copy.

## Mark and exports

| Asset | Purpose |
| --- | --- |
| `Lesearch Logo.svg` | Canonical editable orbital/node mark. Do not replace it with a raster derivative. |
| `web/logo.svg` | Website copy of the canonical mark. |
| `web/brand/lesearch-mesh-lockup-dark.svg` | Full lockup for light surfaces. |
| `web/brand/lesearch-mesh-lockup-light.svg` | Full lockup for dark surfaces. |
| `Assets.xcassets/AppIcon.appiconset/icon-1024.png` | Canonical 1024px app-icon export. |
| `web/brand/lesearch-mesh-social.png` | 1200×630 social-card export, rendered from the adjacent SVG source. |

The mark means an owned mesh: bounded hardware, multiple useful nodes, and an attention signal
moving between them. Keep it sparse and one-color; do not add a cloud, robot, lightning bolt, or
decorative gradient.

## Color and type

| Role | Token | Value |
| --- | --- | --- |
| Night surface | `--mesh-ink` | `#191919` |
| Primary ink | `--mesh-paper` | `#e9e9e7` |
| Secondary text | `--mesh-muted` | `#8f8f8f` |
| Healthy / continue | `--mesh-online` | `#4ade80` |
| Destructive / blocked | `--mesh-danger` | `#bd3038` |

Use JetBrains Mono for product labels, commands, and compact display copy. Use the existing
system sans stack for long narrative text where readability matters. Green and red are status
colors only, never decoration. The token source is [web/brand/tokens.css](../web/brand/tokens.css).

## Layout and motion

The visual world is a calm night-shift instrument panel: near-black surfaces, thin utility
lines, generous negative space, and real product proof. Motion may clarify one attention handoff
only. Always provide a complete `prefers-reduced-motion` state.

## Asset rules

- Use current, redacted product captures as proof; device mockups frame proof but never replace it.
- Use the social card for Open Graph and social previews; do not reuse an app icon as a campaign image.
- A mascot is secondary campaign/onboarding/support IP. Use the project-local
  [`lesearch-mascot`](../.agents/skills/lesearch-mascot/SKILL.md) skill; never replace or
  anthropomorphize the orbital/node product mark.
- Do not use generated terminal text, fictional dashboards, or private screenshots.
- Before public launch, verify the current captures, social card, and hardware behavior together.
