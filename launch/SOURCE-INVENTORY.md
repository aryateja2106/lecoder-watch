# Source inventory

_Checked 2026-08-31 against `main` at `ce2e63f`._

## Canonical launch source

| Area | Canonical path | Notes |
| --- | --- | --- |
| Product daemon | `install/payload/meshd/` | The only shipping daemon. Never revive a root-level `meshd/` copy. |
| Shared protocol | `Shared/` | Wire contracts are serialized work; changes require coordinated client and daemon verification. |
| iPhone, Watch, Mac apps | `iOS/`, `Watch/`, `MeshDesktop/` | Use these for truthful product captures and demo flows. |
| Marketing site | `web/` | Static Vercel site; the current public name is **LeSearch Mesh**. |
| Scroll workspace | `web/.scrollcraft/`, `web/.scrollcraft.json` | Existing starting point; extend it rather than importing a second scroll system. |
| Product proof | `docs/screenshots/`, `web/shots/`, `Reference-images/` | `web/shots/` duplicates the screenshots. Treat all terminal/browser captures as sensitive until redacted. |

## Naming decision and claim boundaries

| Surface | Current identity or claim |
| --- | --- |
| README and marketing site | LeSearch Mesh — “Use your Mac from your wrist.” |
| Product-domain documentation | Historical MeshWatch material, published by LeSearch AI |
| Native targets and bundle identifiers | MeshWatch / `com.lecoder.meshwatch` |
| Operational reality | No account and no cloud relay; devices communicate over a reachable LAN or an existing VPN. |
| Privacy promise | No analytics SDK, cookies, or replay; an optional minimal daemon heartbeat with a random, non-account-linked install ID. |

**Locked rule:** describe the company as **LeSearch AI** and the public product as
**LeSearch Mesh**. Do not rename existing Xcode targets, bundle IDs, module names, or legacy
paths without a separate migration plan.

## Useful existing material

- `docs/competitive-position.md` — strong product positioning; refresh any competitor,
  pricing, or market facts before investor use.
- `docs/launch-posts.md` and `docs/PRODUCT-SPEC-V1.md` — source material for launch
  messaging and the product story.
- Git commit `a3a5cbd` — historical `web/brand/TOKENS.css` and `web/brand/index.html`.
  Recover and review those before creating a new brand system.
- `reference-video/ScreenRecording_08-29-2026 17-15-42_1.MP4` — useful raw demo source,
  but it must be trimmed and redacted before external use.
- `/Users/aryateja/4-Archive/lecoder/apps/website/` — a historical Next.js landing with
  unique design concepts and public-product image candidates under `design-concepts/` and
  `public/product/`. Review each asset for current product truth, naming, and redaction
  before selective reuse. Do not import its framework, `.next/` output, Vercel linkage, or
  `.env.local`.

## Do not consolidate blindly

- The old publish snapshot is at
  `/Users/aryateja/1-Projects/lesearch/meshwatch-publish`; it is a June snapshot with a
  historical root-level daemon copy, not a merge source.
- The older archive is at `/Users/aryateja/4-Archive/lecoder`; preserve it for research,
  but make no changes there.
- Branches such as `release/consolidated` and `codex/redesign-exp-1` include root-level
  daemon copies. Never cherry-pick them without a file-level review.
- Active companion worktrees may have WIP. Do not harvest changes without their owner,
  tests, and a current diff review.

## Safe delivery sequence

1. Lock public product name, launch CTA, and privacy/analytics policy.
2. Recover and audit the historical brand board; retain only what serves the chosen story.
3. Build the landing page in `web/` from real, redacted product captures.
4. Validate every public claim against the README, daemon behavior, and privacy page.
5. Verify with the existing check suite, native builds, daemon TypeScript check, and a
   spare-port daemon smoke test before shipping product changes.
