# web/brand/ — the brand board: logo, colours and type for LeSearch AI, served at lesearch.ai/brand

**Read first:** `index.html` (usage rules and contrast derivation), `TOKENS.css` (the colour and theme variables)
**Surface:** web
**Serialized (one agent at a time):** `TOKENS.css`
**Prove a change:** no dedicated check — add `scripts/check-brand-tokens.sh`; `sh scripts/check-brand.sh` covers `web/index.html`, not this folder (`check-brand.sh:56`)
**Traps:**
- `TOKENS.css:2` still says "LeSearch AI / MeshWatch"; MeshWatch is a retired name (CONTEXT.md "Names").
- The contrast table (`TOKENS.css:20-26`) is hand-computed; change a colour and it is wrong until recomputed.
- Brand lives in several places (`docs/product/RESET-2026-09-06.md:54-55`); `docs/product/design-system.md` is the app-side reference.
**SDLC stage:** Design — brand policy an agent should apply while writing, not find in review.
**Map:** see the file list above (2 files)
