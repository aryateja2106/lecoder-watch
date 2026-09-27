# openspec/specs/ — accepted, current requirements per product capability (only one so far)

**Read first:** `terminal-sessions/spec.md` (the only accepted capability spec), `docs/product/PRODUCT.md` (the enforced product spec)
**Surface:** specs
**Serialized (one agent at a time):** every `*/spec.md`; change them via the `openspec-sync-specs` / `openspec-archive-change` skills, not by hand
**Prove a change:** `openspec validate --specs --no-interactive`
**Traps:**
- One capability here vs the whole product in `docs/product/PRODUCT.md`: two places define behaviour and only PRODUCT.md is checked (`scripts/check-product-spec.sh`). When they disagree, PRODUCT.md wins; fix the spec here.
- Specs change only when a change in `../changes/` is archived, and none ever has been.
**SDLC stage:** Design — accepted requirements that later changes are checked against (see [docs/sdlc/2-design.html](../../docs/sdlc/2-design.html))
**Map:** see the file list above
