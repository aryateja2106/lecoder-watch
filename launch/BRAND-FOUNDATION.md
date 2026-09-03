# Brand foundation

This is the launch identity baseline. It distils the historical brand board at
`a3a5cbd:web/brand/` and the live site so later work starts from one coherent system.

## Locked launch identity

| Element | Candidate rule | Evidence |
| --- | --- | --- |
| Company | LeSearch AI | Current legal and launch material |
| Product | LeSearch Mesh | Locked public product name; native technical identifiers retain MeshWatch |
| Mark | Existing orbital / node glyph | `web/logo.svg`, `Lesearch Logo.svg` |
| Personality | Calm, exact, capable; owned hardware rather than cloud spectacle | Current product behavior and historical board |
| Visual language | Grayscale surfaces, thin utility lines, deliberately sparse green/red status | `a3a5cbd:web/brand/TOKENS.css` |
| Type | JetBrains Mono for product-adjacent labels and code; validate a companion reading face only if the landing needs long-form editorial copy | Existing live site and historical board |

## Candidate token set

The historical system is viable and accessibility-aware. Preserve its semantic roles rather
than copying individual hex values into new components:

- Near-black / near-white primary surfaces with an optional light mode.
- Three ink levels for hierarchy; primary text must maintain normal-text contrast.
- Green only for affirmative/online/continue states.
- Red only for destructive/blocked/stop states.
- 8px base radius and restrained elevation; avoid decorative gradients and neon effects.
- Respect `prefers-reduced-motion`; motion communicates a real attention transition,
  never fills empty space.

## What the kit needs before implementation

1. Use **LeSearch Mesh** on every public, legal, and campaign surface; retain `MeshWatch`
   only for existing technical identifiers until a separate migration is approved.
2. Confirmation that the current orbital mark is the launch mark, plus a source-of-truth
   SVG and light/dark lockups.
3. Three supplied visual references to tune the visual temperature without abandoning the
   product's existing restraint.
4. A public-use clearance list for screenshots, video frames, device mockups, and any
   generated illustration.

## Practical constraints

- Keep real product captures central; a mockup may frame proof but must not replace it.
- Do not generate fictitious terminals, dashboards, machine names, or security claims.
- Use the existing Scrollcraft workspace and static HTML/CSS capability before adding a
  rendering library or a second animation system.
- The public privacy page currently says there is no analytics SDK, cookies, or replay.
  Brand and funnel instrumentation cannot silently contradict that promise.
