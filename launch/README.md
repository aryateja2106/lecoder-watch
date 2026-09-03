# LeSearch Mesh launch HQ

Status: active planning workspace. Created 2026-08-31 after the former Lecoder monorepo moved to archive. This folder contains launch decisions and evidence only; it does not replace runtime code or deploy the site.

## Source of truth

- **Company:** LeSearch AI.
- **Product:** LeSearch Mesh. This is the locked public product name. Keep legacy `MeshWatch` Xcode targets, bundle IDs, and paths stable until a separate migration is approved.
- **Tagline:** Less Search. More Agents.
- **Current product repository:** this repository.
- **Landing:** `web/index.html`, served at `mesh.lesearch.ai`.
- **Shipping daemon:** `install/payload/meshd/`. Never create or merge a second daemon copy.
- **Current telemetry/privacy boundary:** `install/payload/meshd/telemetry.ts`, `supabase/migrations/20260824120000_telemetry_events.sql`, `README.md`, and `web/privacy.html`.

`/Users/aryateja/4-Archive/lecoder` is historical planning/reference material only. Do not copy its runtime code, Next.js landing, package dependencies, or old absolute paths into this repository.

## Launch materials

| Need | Source |
| --- | --- |
| Product truth, story, pitch spine | [BRIEF.md](BRIEF.md) |
| Canonical code/assets and archive boundaries | [SOURCE-INVENTORY.md](SOURCE-INVENTORY.md) |
| Candidate identity foundation | [BRAND-FOUNDATION.md](BRAND-FOUNDATION.md) |
| Locked naming, tokens, and launch assets | [BRAND-KIT.md](BRAND-KIT.md) |
| Current-site gaps and proof | [WEBSITE-AUDIT.md](WEBSITE-AUDIT.md) |
| Static landing implementation handoff | [LANDING-SPEC.md](LANDING-SPEC.md) |
| Capture inventory and redaction needs | [DEMO-ASSETS.md](DEMO-ASSETS.md) |
| Reproducible 90–120 second demo | [DEMO-RUNBOOK.md](DEMO-RUNBOOK.md) |
| Privacy-safe product measurement decision | [ANALYTICS.md](ANALYTICS.md) |
| Verified Vercel production target | [DEPLOYMENT-INVENTORY.md](DEPLOYMENT-INVENTORY.md) |
| Ten-slide investor narrative | [PITCH-DECK.md](PITCH-DECK.md) |
| Market/fundraising evidence | [research/market-and-fundraising.md](research/market-and-fundraising.md) |
| Scrollcraft/Scroll World implementation research | [research/scroll-experience.md](research/scroll-experience.md) |

## Launch promise

LeSearch Mesh lets people supervise agents running on machines they own from iPhone and Apple Watch. The product is local-first: no LeSearch relay is in the terminal path, but APNs carries attention notifications and the daemon may make an optional minimal telemetry request with a random, non-account-linked install ID.

Do not claim universal reachability, accounts, a hosted relay, zero telemetry, or capabilities not proven by the current beta. A reachable LAN or a VPN the customer already uses remains a real requirement.

## Work order

1. Use `BRIEF.md` to lock the brand/story before generating any visual asset.
2. Replace stale landing proof with a current, redacted demo capture from a spare daemon.
3. Correct claims and create a static landing storyboard before adding one small attention-handoff scroll interaction.
4. Keep analytics inside the privacy boundary defined in `ANALYTICS.md`; no PostHog SDK, survey, or replay ships by accident.
5. Build the pitch and demo from verified product behavior and cited research, not valuation assumptions or planned features.

## Ready-to-assign lanes

| Lane | Boundary | Prerequisite |
| --- | --- | --- |
| Landing claims and story | `web/` only; no daemon/client contract edits. | Current proof capture. |
| Demo capture | Redacted assets and manifest only; human verifies physical Watch/iPhone behavior. | Spare daemon and sterile demo machine. |
| Scroll peak | Reuse existing HTML/CSS; one responsive, reduced-motion-safe handoff state sequence. | Static storyboard. |
| Analytics | One owner across telemetry, privacy copy, consent, and tests. | Explicit privacy/product decision. |
| Pitch and video | `launch/` content and real product capture only. | Current demo sequence. |
| Product consolidation | Serialize `Shared/`, pairing/auth, `server.ts`, and `project.yml`. | Architecture and license decisions. |

No deployment, DNS, Vercel-link, analytics-project, or source-archive change has been made from this workspace.
