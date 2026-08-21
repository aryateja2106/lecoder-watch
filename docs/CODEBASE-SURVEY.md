# Codebase survey — what to keep from the 12 LeCoder/LeSearch folders

*2026-08-21, produced by a 6-agent parallel sweep. The active product is THIS repo
(lecoder-watch, meshd + watch/phone, 0.4.x). Rule applied throughout: pull **assets**
(sites, specs, brand, one Swift file), never merge old code lineages — meshd and the
apps here have already superseded every earlier architecture.*

## The verdict table

| Folder | Verdict | The one-line truth |
|---|---|---|
| `~/Projects/lecoder` | **merge-source** | The May–Aug monorepo: best unused landing (redesign, Jul 15), brand SVGs, and the entire strategy/spec corpus |
| `~/Projects/lecoder-mconnect/apps/website` | **merge-source** | CONFIRMED source of the LIVE lecoder.lesearch.ai (byte-identical hero); rest of that repo is an older clone of `lecoder` |
| `~/Projects/lesearch-ai` | **merge-source** | Previous-generation Swift app; holds `CredentialVault.swift` (Keychain + Secure Enclave) — the ready-made fix for this app's plaintext token storage |
| `~/Desktop/Work/LeCoder` | reference-only | Backup of the mconnect monorepo; best reference for tunnel (cloudflared), command guardrails, and the zod pairing protocol |
| `~/Projects/lesearch` | reference-only | Container-stack control plane (dead end per memory); keep its README positioning copy + typed health enum idea |
| `~/Projects/meshwatch-publish` | reference-only | June public snapshot; mine its README marketing copy + `Branding/appicon.svg` |
| `~/Agent-Working-Plans/lesearch-ai-…abstract-pixel.md` | reference-only | Best written thinking on approval-gating (risk tiers, audit JSONL, ISC checklist) |
| `~/Projects/lecoder-watch-cmux-bridge` | **salvaged** | Worktree of this repo; its orphaned Jul-7 WIP is now checkpointed (`a037ff5` on `fix/cmux-bridge-slice-d`); worktree can be removed |
| `~/Projects/lecoder-mconnect` | archive | Older clone of `lecoder`; unique docs already copied to `lecoder/docs/legacy-mconnect/` |
| `~/Desktop/Work/mconnect-prep` | archive | Dead HRM fine-tune pivot; move the 4 research docs to SecondBrain-OKF, then archive |
| `~/Projects/lescout` | archive (parked product) | Coherent standalone ingestion CLI; not part of this merge; `Plans/BRAND.md` is the naming bible |
| `~/Projects/lecoder-watch-fix-merge-widgets` | delete | Clean worktree, purpose served, commits preserved on origin |
| `~/Agent-Working-Plans/lescreen-restore-realvnc.sh` | ignore | Personal Mac-recovery runbook; lives with ResetPlaybook |

## The sites map (the "good looking sites")

| Site | Status | Source | Vercel project |
|---|---|---|---|
| **lesearch.ai** | LIVE ("Every Agent. Every Machine. One Terminal.") | **NO LOCAL SOURCE FOUND** — CLI-deployed, no git link. Recoverable from Vercel | `lesearch-website` (prj_18CQ5GNF…) |
| **lecoder.lesearch.ai** | LIVE, but one product-generation stale (sells the npx CLI, links the OLD TestFlight pB2TbMrX) | `~/Projects/lecoder-mconnect/apps/website` (confirmed byte-identical) | `lecoder-mconnect-web`, root `apps/website` |
| **The unused redesign** | never deployed — hero "Run agents here. Control them anywhere.", waitlist + blog | `~/Projects/lecoder/apps/website` (Jul 15) | drops into `lecoder-mconnect-web` unchanged (same root path) |
| **Mesh landing** (this repo, `web/`) | live at lesearch-mesh-web.vercel.app; **mesh.lesearch.ai DNS still missing** (the known Cloudflare CNAME) | `web/index.html` — tight, on-brand, matches 0.4.x | `lesearch-mesh-web` |

## What to actually pull, in order

1. **`CredentialVault.swift`** from lesearch-ai → replace this app's UserDefaults-plaintext
   machine tokens with Keychain/Secure Enclave. Security gap, small diff, ready-made.
2. **Landing refresh**: deploy `lecoder/apps/website` over the `lecoder-mconnect-web`
   Vercel project (one product-name/copy pass first — it still says `npx lecoder-mconnect`),
   or redirect lecoder.lesearch.ai to the Mesh landing. Today it advertises a superseded
   product with a dead TestFlight link.
3. **Docs corpus** from `lecoder/docs`: POSITIONING.md (the "four rows nobody owns" wedge),
   PRICING.md, STATUS.md (116-requirement gap map — a merge checklist), and the openspec
   watch/voice/onboarding/live-notification specs. Copy into `docs/strategy/` here.
4. **Brand**: `lecoder/brand-assets/` + `meshwatch-publish/Branding/appicon.svg`.
5. Later, as features come up: tunnel integration (Desktop/Work/LeCoder `packages/cli/src/tunnel`)
   for control beyond the tailnet; command guardrails + the abstract-pixel risk-tier spec
   when hardening the approval flow; `lesearch` README copy for marketing.

## Risks found

- **lesearch.ai has no local source.** It exists only as a CLI deploy in Vercel. Pull the
  deployment down (`vercel pull` / download) into a repo before touching that project.
- Both live sites are **CLI-deployed with no git link** — nothing rebuilds them if Vercel
  state is lost. Bring their source into version control as part of the merge.
- `~/Desktop/Work/*` is macOS-TCC-gated for some agent processes — move anything
  load-bearing out of Desktop and into `~/Projects`.
