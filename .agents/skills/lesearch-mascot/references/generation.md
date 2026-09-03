# Generation reference

Read this only after the user approves a direction and candidate batch.

## Candidate assignment

| Candidate | Direction | Corner |
| --- | --- | --- |
| A1 | Direction A | lower-left |
| A2 | Direction A | lower-right |
| B1 | Direction B | lower-left |
| B2 | Direction B | lower-right |
| C1 | Direction C | lower-left |
| C2 | Direction C | lower-right |

For a user-selected single direction, alternate lower-left for odd variants and lower-right for
even variants. Keep the user-requested quantity if it differs from six.

## Default palette

Use exactly three semantic color families in one candidate:

| Role | Default | Rule |
| --- | --- | --- |
| Background | `#191919` | Flat full canvas; no texture, scenery, halo, vignette, or gradient. |
| Character | `#e9e9e7` | Large primary body mass and face. |
| Signal | `#4ade80` | One healthy/continue node, wrist signal, or question-token. Replace with `#bd3038` only for an explicit blocked/destructive brief. |

Do not introduce `#8f8f8f` in a default three-color candidate. It is a UI hierarchy color, not a
fourth mascot color.

## Prompt skeleton

Use this as one complete prompt for a modern instruction-following image model. Keep it an image
request only: do not call the output a logo, app icon, brand mark, or product asset.

```text
Create one complete full-bleed 1:1 square character image.
Background: fill the entire square with solid #191919. Keep it uniform in every open area.
Subject: one extremely simplified, calm, endearing <subject> character acting as an attention companion. Its only action is <direction>.
Shape: build one compact upright silhouette from 4–7 large rounded forms. Give it one defining feature, two simple eyes, and only a tiny mouth when it improves the expression. Keep it recognizable at 32 × 32.
Color: use exactly three semantic color families—#191919 background, #e9e9e7 character, and <#4ade80 or #bd3038> for one small state signal only. Keep the character mostly monochrome.
Composition: let the character emerge upright from the <lower-left or lower-right>, filling about 85–95% of the square. Preserve both members of any paired defining feature. Leave calm negative space elsewhere.
Style: thick rounded contours, broad clean color masses, friendly but capable, with barely perceptible soft depth and no strong 3D treatment.
Constraints: no words, watermark, border, card, badge, interface, device, terminal, code, extra subject, scenery, texture, fragile line, sharp tip, neon glow, glossy hotspot, photorealistic material, or cast shadow.
```

Do not add a reference image from another candidate when testing prompt-only reproducibility. Do
not replace the requested subject with the existing orbital/node mark.
