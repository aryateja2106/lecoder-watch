# Market and fundraising research — LeSearch AI / LeSearch Mesh

Retrieved 2026-08-31. This is a pre-seed research memo, not investment, legal, tax, or valuation advice. External claims are linked to their authoritative source; product statements are limited to the repository’s current [launch brief](../BRIEF.md).

## Direct answer

The credible pre-seed story is a narrow one: **LeSearch Mesh helps people supervise long-running AI-agent work on machines they own, from the iPhone or Apple Watch already in hand.** The problem is not generic remote desktop. It is the interruption between an agent continuing useful work and a human needing to notice, inspect context, and deliberately answer.

**Inference:** the strongest early wedge is agent-native developers, solo builders, and technical founders who already run long-lived local/owned-machine work. The cited evidence supports the growth of AI-assisted development and asynchronous agents; it does not prove demand, retention, willingness to pay, or a general-audience market for LeSearch Mesh.

## Product-truth boundary

**Repository fact:** the beta pairs owned Mac or Linux machines through the canonical `install/payload/meshd/` daemon; iPhone and Apple Watch can show machines, sessions, terminal output, and attention states; users can send deliberate input; supported host controls include iPhone remote screen/trackpad; APNs can carry attention notifications after local-hook installation. Access requires a reachable LAN or an existing VPN. There is no LeSearch hosted relay or account product today. [Launch brief](../BRIEF.md), [launch HQ](../README.md)

Accordingly, do **not** claim universal reachability, hosted remote access, fully self-hosted/no-cloud, end-to-end encryption, zero telemetry, generic remote desktop replacement, or a feature beyond a reproducible current capture.

## Customer problem

### Fact

- Current cloud agent products explicitly support asynchronous work. Cursor says its Background Agents run remotely, can be viewed or taken over later, and run by default in isolated Ubuntu machines; its docs also state that code executes in AWS infrastructure while the agent is accessible. [Cursor Background Agents](https://docs.cursor.com/background-agent)
- GitHub says Copilot cloud agent works in its own ephemeral GitHub Actions environment, where it can explore code, change it, and run tests/linters; standard GitHub-hosted runners are the default. [GitHub: development environment](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/customize-the-agent-environment), [GitHub: runner configuration](https://docs.github.com/en/copilot/how-tos/administer-copilot/manage-for-organization/configure-runner-for-coding-agent)
- macOS already offers Screen Sharing to view and control another Mac on a network. [Apple Support: Screen Sharing](https://support.apple.com/guide/mac-help/share-the-screen-of-another-mac-mh14066/mac)

### Pitch implication (inference)

As agents work asynchronously, the human problem shifts from “how do I start an agent?” to “how do I supervise it without remaining at the terminal?” LeSearch Mesh should demonstrate a single **attention handoff**—machine task → needs-you state → legible Watch/iPhone context → intentional response → task continues. It should not compete on a generic claim to create agents, provide a cloud runtime, or replace full remote desktop.

## Why now

| Fact | What it supports—and does not support |
| --- | --- |
| GitHub’s 2025 Octoverse reports 180M+ developer accounts, 36M new accounts in the year, 4.3M AI-related repositories, and 1.1M public repositories importing an LLM SDK (+178% YoY). It also reports 80% of new GitHub users used Copilot in their first week. [GitHub Octoverse 2025](https://github.blog/news-insights/octoverse/octoverse-a-new-developer-joins-github-every-second-as-ai-leads-typescript-to-1/) | A large, growing developer/AI-workflow universe and a credible developer-first wedge. It is **not** a buyer count or TAM. |
| Stanford HAI’s 2025 AI Index reports that inference for GPT-3.5-level MMLU performance fell from $20 per million tokens in Nov. 2022 to $0.07 in Oct. 2024; it also reports open-weight models closing some benchmark gaps. [Stanford HAI, *AI Index Report 2025*](https://hai.stanford.edu/assets/files/hai_ai_index_report_2025.pdf) | More agent/model configurations are technically and economically available. It does **not** prove a given customer’s local-model cost or that owned hardware is cheaper. |
| Tailscale documents a tailnet as a private, authenticated collection of users, devices, and resources; a device must be added/authenticated before use. [Tailscale: tailnets](https://tailscale.com/docs/concepts/tailnet), [Tailscale: add a device](https://tailscale.com/docs/features/access-control/device-management/how-to/set-up) | Existing private-network tools make owned-machine remote reach feasible, but setup, access policy, and failure states are real customer concerns. It does **not** remove LeSearch Mesh’s current reachable-network requirement. |

## Market framing: no invented TAM

Do not turn GitHub’s developer count or Apple’s “over 2B active devices” into a revenue TAM. Apple’s number is distribution scale, not the number of iPhone/Watch owners who run long-lived agents on an owned machine. [Apple Developer Program](https://developer.apple.com/programs/whats-included/)

Use a bottom-up, measured model instead:

```text
qualified leads
× owned-machine, long-running-agent users
× pairing completion
× weekly attention-loop completion
× D30 retained installations
× paid conversion
× annual net revenue per paying account
= served-cohort opportunity
```

Every term after qualified leads is an **assumption until observed**. Present the denominator, date range, channel, and consent coverage. Page views, waitlist count, installs, and notification deliveries are not activation.

## Comparable categories and position

| Category | Fresh fact | Position for LeSearch Mesh |
| --- | --- | --- |
| Cloud coding agents | Cursor’s background agents and GitHub Copilot cloud agent execute in provider/Actions environments. [Cursor](https://docs.cursor.com/background-agent), [GitHub](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/customize-the-agent-environment) | Complementary: supervise work on the customer’s own machine rather than claiming to replace cloud execution. Do not describe competitors as insecure; their respective security controls differ. |
| Private connectivity | Tailscale uses authenticated devices in a tailnet; device-to-device connections can be direct or relayed by Tailscale when direct connectivity is impossible. [Tailscale connectivity](https://tailscale.com/docs/reference/device-connectivity) | A network underlay, not an agent-supervision experience. Current Mesh must honestly rely on the customer’s reachable LAN/VPN; it has no LeSearch relay. |
| Remote desktop | Apple Screen Sharing already supports remote Mac viewing/control on a network. [Apple Support](https://support.apple.com/guide/mac-help/share-the-screen-of-another-mac-mh14066/mac) | Generic remote control is table stakes. The distinct proposed value is agent-aware attention, compact context, and intentional input—not an attempt to copy every desktop control surface. |
| App distribution | Apple says App Store search uses product-page metadata and customer behavior; primary category influences discovery. [Apple App Store discoverability](https://developer.apple.com/app-store/discoverability/) | A potential channel after public-readiness. Do not forecast organic installs; test listing positioning, screenshots, and video once release eligibility exists. |

This is a category map, not a feature-complete competitive analysis. Revalidate all vendor behavior and pricing immediately before investor use.

## Plausible business-model hypotheses

These are hypotheses, not current offers or forecasts:

1. **Individual Pro:** paid multi-machine, advanced supervision, or reliability/administration features once those capabilities are built and a price test shows willingness to pay.
2. **Team plan:** only after permissions, onboarding, support, and shared-machine administration are proved; do not imply this exists today.
3. **No hosted-agent inference assumption:** local-first supervision does not establish that LeSearch provides or pays for model inference or customer hardware. Keep customer-owned compute/model spend separate from company COGS.

If digital features/subscriptions are sold through Apple’s App Store, Apple lists a $99/year Developer Program fee and a 30% commission on digital goods/services, with 15% for qualifying subscriptions/programs. Confirm eligibility, location, and terms with counsel before using it in a revenue model. [Apple Developer Program membership and fees](https://developer.apple.com/programs/whats-included/)

## $1M pre-seed framing—without a prescribed valuation

### Facts

- Carta reports that US startups on its platform raised $3.19B across 11,500+ pre-seed instruments in Q2 2026; the average instrument size was $276K, and few pre-seed deals exceeded $2.5M. [Carta, *State of Pre-Seed: Q2 2026*, 2026-08-13](https://carta.com/data/state-of-pre-seed-q2-2026/)
- Carta reports 93% of Q2 2026 pre-seed rounds on its platform used SAFEs and explains that a valuation cap is a future-conversion ceiling, not an actual present company valuation. [Carta, SAFE valuation-cap analysis, 2026-08-25](https://carta.com/uk/en/data/safe-valuation-caps-q2-2026/)
- In a narrow, historical comparison of hundreds of companies raising $1M–$1.5M on post-money SAFEs in 2025, Carta reported clustering around a $10M cap but emphasizes demand, founder context, and geography. [Carta, 2026-02-09](https://carta.com/data/linkedin-startup-valuation-caps-consistent-by-city/)
- Carta separately warns that pre-seed caps are not a measure of underlying value and cites roughly-$1M SAFE rounds spanning $5M–$30M caps. [Carta, 2026-01-24](https://carta.com/data/linkedin-preseed-vc-valuation-caps-unfair/)

### Interpretation

Treat **$1M as requested capital**, not an intended valuation. A $10M post-money SAFE cap would mechanically imply about 10% ownership for $1M before other dilution; $5M implies about 20%, and $15M about 6.7%. This is arithmetic illustration, not a price recommendation or ownership-model substitute.

The externally honest raise: **$1M to harden the beta, make pairing/reliability legible, test paid demand, and prove recurring supervision/retention.** Price is earned by a dated traction packet and investor/founder context, not by the AI label. Before accepting terms, use startup counsel to review all existing instruments, option pool, SAFE mechanics, jurisdiction, and disclosures.

## KPIs and investor diligence

### First metrics

Use the consented, coarse event boundary in [ANALYTICS.md](../ANALYTICS.md); currently, the apps have no analytics SDK and the public contract disallows stealth tracking/replay.

| Question | Minimum evidence |
| --- | --- |
| Can the customer start? | Lead → qualified workflow → pairing completion; time-to-first reachable machine; failure class. |
| Does the core loop work? | Attention received → context viewed → intentional resolution; resolution-time bucket; session resumes where observable. |
| Does it recur? | D7/D30 retained installations with a paired machine and meaningful supervision event; cohort/channel split. |
| Is it monetizable? | Pre-registered pricing test, conversion, refund/churn reason, support time per active installation. |
| Can it be trusted? | Connection failure/recovery rates, permission-related support, security issues, and evidence that forbidden customer content never enters analytics. |

Apple requires disclosures that accurately cover data collected by the app and third-party SDKs; it says data is often linked to identity unless protections de-identify it before collection. This supports the allow-list/no-content/no-replay discipline, but does not exempt future analytics from disclosure. [Apple App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)

### Diligence packet before a serious pitch

1. Current, redacted, reproducible demo on a spare daemon; physical Watch/iPhone behavior human-verified.
2. Feature and permission inventory that matches all public claims, including the LAN/VPN/APNs caveats.
3. Dated cohort table: acquisition source, qualification, activation, attention-loop usage, D7/D30 retention, and opt-in denominator.
4. One pricing experiment and a basic company-Cash/COGS/support model based on actual vendor quotes—not presumed cloud savings.
5. Security/privacy review of daemon, hook, pairing, and telemetry; no prompts, terminal text, paths, hostnames, IPs, tokens, screenshots, or notification bodies in analytics.

## Evidence limits and reusable takeaway

No source establishes target-segment size, traction, CAC, conversion, retention, ARPA, gross margin, or an appropriate valuation for LeSearch Mesh. Those must come from its own consented beta cohort.

**Reusable takeaway:** pitch LeSearch Mesh as the human-in-the-loop attention surface for long-running agent work on an owned machine. Prove the attention handoff, retention, and paid demand in a developer-first cohort before claiming a broader market, repeatable distribution, or a valuation range.
