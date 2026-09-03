# Current website audit

Audited 31 August 2026: `web/index.html`, `web/privacy.html`, shipped assets, `web/vercel.json`, `README.md`, and `ROADMAP.md`. Fresh captures were checked at 1440×900 and 390×844. Both pages rendered without console warnings, and the landing had no horizontal overflow at 390 px.

Update 3 September 2026: a source-only beta/privacy pass qualified device-dependent flows,
the trusted-network HTTP boundary, telemetry, and Watch fallback behavior. Fresh browser
revalidation is still required before a production deployment.

After the audit, a read-only Vercel CLI inspection confirmed that `mesh.lesearch.ai` aliases the
ready production deployment for `lesearch-mesh-web`; see [DEPLOYMENT-INVENTORY.md](DEPLOYMENT-INVENTORY.md).
That confirms the target hostname, not every installer, privacy, redirect, GitHub, or TestFlight link.

## Verdict

This is a credible beta page, not yet the launch story. Its strongest material is already here: one sharp use case, real product captures, direct setup, and unusually candid privacy copy. The main work is to make the first scroll demonstrate the attention handoff and to remove claims that read as shipped before the roadmap says they are proven.

## Baseline applied after this audit

`web/index.html` now has a skip link, labelled primary navigation, one main landmark, typed
Copy buttons, a polite live status with a clipboard-failure path, and stronger muted/red tokens.
An isolated localhost browser smoke test found zero console warnings and no horizontal overflow
at 390×844 or 1440×900; it also confirmed the expected landmarks, one `h1`, and live region.
The later beta/privacy pass also qualified unproven flows, explained the plain-HTTP boundary,
and aligned the privacy copy with the daemon payload and Watch fallback. It intentionally did
not rewrite assets, names, routes, analytics, or the page story. Those remain governed by the
launch gates below.

## What works

- The hero names a concrete pain: an agent blocks while the user is away from the desk.
- The TestFlight action is prominent and consistently labelled.
- Real iPhone and Watch captures provide better proof than generated hardware art would.
- The page explains setup and the reachable-network boundary instead of hiding them.
- Desktop hierarchy is calm and legible; the 390 px layout reflows without clipping.
- Image dimensions and useful alt text are present. Focus styles, native `details`, and reduced-motion handling provide a sound accessibility base.
- The privacy page clearly separates app traffic, daemon heartbeat, and Apple push delivery in its body copy.

## Remaining claim and naming gates

1. **Physical-device proof remains.** The landing now qualifies notification, session-matching,
   and cold-device behaviors as beta work. Do not remove those qualifiers until they pass on
   physical iPhone and Watch hardware.
2. **The Google Fonts request weakens the privacy posture.** The public pages contact Google to
   load JetBrains Mono. Self-host the final licensed brand fonts when the brand kit is locked.
3. **Keep the hierarchy fixed:** **LeSearch AI** is the company, **LeSearch Mesh** is the product,
   and **Less Search. More Agents.** is the company line. The page currently establishes the
   product but barely establishes the company. Add the hierarchy once; avoid introducing
   “Mesh,” “Meshwatch,” or another product name.
4. **Production routing still needs a final deploy check.** The Vercel inspection establishes the
   current alias, but recheck `mesh.lesearch.ai`, `/privacy`, `/install.sh`, GitHub, and TestFlight
   against the deployed build before treating a new release as public.


## Smallest high-impact story change

Do one signature sequence, using the current captures and CSS:

1. **Running:** a task continues on an owned Mac or Linux machine.
2. **Needs you:** the same task compresses into a Watch-sized, risk-labelled question.
3. **Answered:** the response is intentional; the task visibly continues.

Make that a short sticky “attention handoff” immediately after the hero. It replaces the current three explanatory cards rather than adding another section. Follow it with the three strongest real captures: Machines, iPhone terminal, Watch terminal. Then show multi-machine setup, the local-first boundary, FAQ, and one beta CTA.

This produces the intended scroll story without WebGL, a 3D framework, fake terminal states, or a new asset pipeline. On mobile, render the same three states as ordinary stacked panels and honor `prefers-reduced-motion` with a complete static state.

## Responsive and accessibility constraints

- Mobile is functional but long: five devices plus repeated card grids make the current page roughly 10,000 px tall at 390 px. Three proof captures are enough for the first launch pass.
- JetBrains Mono across every paragraph strongly codes the product as developer-only. Keep mono for terminals, labels, and technical proof; choose a readable brand text face for narrative copy after the brand kit is locked.
- The current `--ink-3` token measures **5.44:1** against the page background; white on the red risk chip measures **5.76:1**. Recheck both after any brand-token change.
- The landing and privacy pages now have labelled navigation and main landmarks; the landing also has a skip link.
- Copy buttons now announce success and give a manual-copy failure path. Preserve both behaviors.
- Preserve the current visible focus treatment, native disclosure controls, image dimensions/alts, and reduced-motion path.
- Verify at 320, 390, 768, and 1440 px; at 200% zoom; with keyboard only; and with reduced motion enabled. Screenshot review cannot establish full WCAG compliance.

## Verification order

1. Physically prove APNs, Watch action, and resume behavior before removing the current beta qualifiers.
2. Check the actual production routes: `lesearch.ai`, `mesh.lesearch.ai`, `/privacy`, `/install.sh`, GitHub, and TestFlight. Resolve DNS/redirect ownership first.
3. Ship the static attention-handoff sequence with current redacted captures; verify the no-motion version before scroll motion.
4. Run keyboard, landmarks, contrast, 200% zoom, and screen-reader smoke checks.
5. Test responsive layout and Safari performance on iPhone-class hardware, then verify all links, copy buttons, and FAQ states.
6. Before adding PostHog or surveys, approve the consented pseudonymous event schema and update the privacy page, telemetry promise, and consent/opt-out behavior together.

Stop condition: the live first scroll proves one honest attention handoff, all public claims match tested beta behavior, production routes resolve, and the page passes the responsive/accessibility checks above.
