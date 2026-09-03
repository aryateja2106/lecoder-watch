# Deployment inventory

_Read-only Vercel check, 2026-08-31. No deployment, DNS, alias, environment, or project
configuration was changed._

## Verified production surface

| Item | Current evidence |
| --- | --- |
| CLI access | Vercel CLI `52.0.0`, authenticated for the `aryateja2106-projects` scope. |
| Project | `lesearch-mesh-web` |
| Current production deployment | Created 2026-08-27, status **Ready** |
| Production alias | [`mesh.lesearch.ai`](https://mesh.lesearch.ai) |
| Vercel aliases | `lesearch-mesh-web.vercel.app`, `lesearch-mesh-web-aryateja2106-projects.vercel.app` |

The deployment’s Vercel URL is
`https://lesearch-mesh-d53z32kin-aryateja2106-projects.vercel.app`.

## Public-link smoke check

On 2026-08-31, read-only HTTP checks returned success for the Mesh root, `/privacy`,
`/install.sh`, the public GitHub repository, the public TestFlight destination, and
`lesearch.ai`. The installer correctly resolves through to its published release asset.
This verifies reachability only; it does not prove enrollment eligibility, installer behavior,
page accuracy, DNS ownership, or the product claims shown at each destination.

## Delivery implication

Treat `mesh.lesearch.ai` as the current landing target. Before an external launch, use a clean
browser to verify installation, TestFlight eligibility, copy, and the remaining DNS/redirect
ownership questions. The site audit identified historic redirect/DNS ambiguity; this check
confirms reachability rather than product behavior or content truth.

## Guardrail

Do not link, deploy, promote, change aliases, edit DNS, pull environment variables, or
remove older deployments from this consolidation workspace without an explicit release
decision and a review of the static site’s claims.
