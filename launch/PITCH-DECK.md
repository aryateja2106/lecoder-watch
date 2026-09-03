# LeSearch AI investor deck

Status: content draft for visual design. **LeSearch Mesh** is the locked public product name; legacy technical identifiers retain `MeshWatch` until a separate migration.

Communication job: by the end, a pre-seed investor should understand why agent supervision on owned machines is a timely wedge, what the beta proves today, which commercial claims remain hypotheses, and what a $1M raise is intended to validate.

## Slide 1 — Agents keep working while people keep moving

**On-slide message**

**LeSearch AI**  
**LeSearch Mesh**  
Supervise agent work on machines you own—from iPhone and Apple Watch.

**Visual proof needed:** One strong, current product composition: owned Mac in the background, a real needs-you state on Watch in the foreground, and no speculative interface.

**Presenter notes (30–45 seconds):** Agents can run for hours, but people still have to return to a terminal whenever the work needs context or a decision. LeSearch Mesh makes that supervision loop portable. A small daemon runs on a machine the customer owns; the iPhone and Apple Watch show live sessions, terminal output, and attention states, and let the user respond deliberately. This is an early beta, not a claim that every workflow or network is solved. The company is LeSearch AI; LeSearch Mesh is the product.

## Slide 2 — Agent work is becoming asynchronous; human attention is not

**On-slide message**

**Problem hypothesis:** when a long-running agent pauses for a decision, useful work stops until the person notices, restores context, and answers.

**Visual proof needed:** A real agent question waiting on the owned machine, paired with the same legible needs-you state on Watch. The timestamp and content must come from a reproducible, redacted run.

**Presenter notes (30–45 seconds):** Cloud-agent products already make asynchronous execution a normal workflow: Cursor describes background agents that run remotely and can be viewed or taken over later, while GitHub’s coding agent works in an ephemeral Actions environment. Those facts establish the workflow shift, not demand for our product. Our customer hypothesis is narrower: people running long-lived work need a reliable way to notice, inspect, and resolve the few moments that still require them. We need interviews and retained usage to quantify how often that interruption is painful. [Cursor Background Agents](https://docs.cursor.com/background-agent), [GitHub coding-agent environment](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/customize-the-agent-environment)

## Slide 3 — The agent ecosystem is large enough to support a focused wedge

**On-slide message**

GitHub reported **4.3M AI-related repositories** and **1.1M public repositories importing an LLM SDK, up 178% year over year** in 2025. This signals workflow growth—not LeSearch Mesh TAM. [GitHub Octoverse 2025](https://github.blog/news-insights/octoverse/octoverse-a-new-developer-joins-github-every-second-as-ai-leads-typescript-to-1/)

**Visual proof needed:** A restrained two-number evidence slide. Do not turn developer-account or device counts into a market-size chart.

**Presenter notes (30–45 seconds):** The timing is driven by behavior, not a generic AI headline. More developers are building with LLMs, and agent work increasingly continues after the person steps away. Stanford also reports that the cost of GPT-3.5-level inference fell sharply between 2022 and 2024, supporting broader experimentation with models and agents. Neither source proves our target segment, willingness to pay, or local-compute economics. It does support testing a focused supervision product now, while these workflows are becoming routine. [Stanford HAI, AI Index Report 2025](https://hai.stanford.edu/assets/files/hai_ai_index_report_2025.pdf)

## Slide 4 — LeSearch Mesh is the supervision layer for an owned machine

**On-slide message**

Pair a Mac or Linux machine. See its sessions and attention states. Read the terminal. Respond from Watch or iPhone. Take supported Mac screen control when more context is needed.

**Visual proof needed:** A simple current-state topology—owned machine running `meshd`, direct LAN or existing VPN connection to iPhone, Watch through iPhone, and APNs only for installed attention notifications—plus one real screenshot per surface.

**Presenter notes (30–45 seconds):** The current beta uses a small local daemon and requires no LeSearch account. It works when the machine is reachable on the same network or through a VPN the customer already uses. The local hook can send an attention notification through APNs, and the user can inspect and answer from the app. There is no LeSearch-hosted relay today, so universal connectivity is not part of this claim. Transport is currently bearer-token HTTP on a trusted private network; security hardening and broader reachability remain product work. [Current product truth](../README.md#what-is-and-is-not-true-yet)

## Slide 5 — The proof is one complete attention handoff

**On-slide message**

**Agent pauses → Watch surfaces the question → user answers deliberately → the same session continues.**

**Visual proof needed:** A 90–120 second live demo captured on a spare daemon. Show the real task, real question, real device state, intentional response, and continued output. Add iPhone screen control only if it proves a distinct recovery step.

**Presenter notes (30–45 seconds):** This is the product’s defining moment and the center of the pitch. We should show one harmless agent task stop for a real question, reach the user, receive an intentional answer, and continue in the same persistent session. The demo should not rely on generated terminal content or a future interface. Physical Watch and iPhone notification behavior must be checked by a person; simulator footage alone does not prove the handoff. The current capture and redaction plan is documented in the [demo asset inventory](DEMO-ASSETS.md).

## Slide 6 — The wedge is agent-aware control, not another remote desktop

**On-slide message**

LeSearch Mesh combines three current surfaces around one task: **attention state, a real Watch terminal, and supported phone screen control.**

**Visual proof needed:** One continuous task shown across the agent feed, Watch terminal, and iPhone remote screen. Avoid a feature grid and avoid “only product” or “no competitor” claims.

**Presenter notes (30–45 seconds):** Generic remote desktop already exists, and mature mobile terminals are deep products. Our wedge is the workflow between them: an agent asks for attention, the person gets compact context on the wrist, and can move to a terminal or supported screen control without losing the session. The internal competitive review suggests this combination is differentiated, but that conclusion needs a fresh, cited competitor audit before investor distribution. We should sell the completed workflow we can demonstrate, not claim category ownership. [Current competitive position](../docs/competitive-position.md)

## Slide 7 — Start with people who already run long-lived agents on owned machines

**On-slide message**

**Initial customer hypothesis:** agent-native developers, solo builders, and technical founders with a reachable Mac or Linux machine and recurring supervision needs.

```text
qualified leads × workflow fit × pairing completion × D30 retention
× paid conversion × annual revenue per account
= served-cohort opportunity
```

**Visual proof needed:** A bottom-up cohort funnel with every term labelled **unmeasured** until real data exists. Do not show a top-down TAM.

**Presenter notes (30–45 seconds):** We do not yet have evidence for a broad professional or general-audience market, so the first segment is deliberately narrow. GitHub’s developer scale is a useful source of qualified leads, not a buyer count. We will measure the served opportunity from actual cohorts: who has the workflow, who pairs successfully, who completes the attention loop, who returns at day 30, and who pays. This keeps the market claim tied to observable behavior instead of multiplying unrelated device and developer totals. [Market framing](research/market-and-fundraising.md#market-framing-no-invented-tam)

## Slide 8 — Distribution expands only when activation and retention earn it

**On-slide message**

1. **First 1,000 qualified users:** design partners and demo-led agent communities.  
2. **Next 10,000:** referrals, creator proof, and App Store discovery after onboarding retains.  
3. **Toward 100,000:** broader prosumer and professional workflows only after reachability, trust, and support scale.

Revenue hypotheses: paid individual multi-machine or advanced supervision features; team plans only after permissions and administration exist.

**Visual proof needed:** A three-stage path with an evidence gate under each stage. No hockey-stick curve, CAC forecast, price, or revenue projection without test data.

**Presenter notes (30–45 seconds):** The go-to-market plan starts where the problem is already legible: people actively running agents on machines they own. A reproducible attention-handoff demo can recruit qualified design partners and reveal onboarding failures quickly. Expansion to ten thousand should depend on referral behavior and retained activation, not raw waitlist growth. A hundred-thousand-user story is a later possibility, not a current forecast. The same discipline applies to revenue: individual Pro and later team plans are hypotheses until pricing tests establish conversion, support cost, and churn.

## Slide 9 — The next proof is retained supervision, not download count

**On-slide message**

**Proven today:** early TestFlight beta, daily use on a small fleet, one-command install and uninstall.  
**Still to prove:** pairing conversion, time to first reachable machine, attention-loop completion, D7/D30 retention, and paid demand.

**Visual proof needed:** Use current product evidence now. Replace it with a dated cohort table only after consented data exists; never fabricate a traction chart or count passive page views as users.

**Presenter notes (30–45 seconds):** We have product evidence, but not an investor-grade traction dataset. The current apps collect no analytics, and the privacy page promises no analytics SDK or tracking cookies. Before adding product analytics, we need an explicit consent model, an allow-listed event schema, updated public disclosures, and no session replay on terminal, pairing, remote-screen, or control surfaces. The first useful metrics are activation, completion of the attention loop, retained meaningful use, and a pre-registered paid test. [Analytics boundary](ANALYTICS.md)

## Slide 10 — $1M turns a working beta into a repeatable, trusted product

**On-slide message**

**Capital sought: $1M** to prove four milestones:

- reliable onboarding and reachable-machine setup;
- consented, content-free product measurement;
- retained supervision and paid demand;
- product, security, and launch hardening.

Financing structure and terms remain open; this deck does not assert a valuation.

**Visual proof needed:** A milestone-based use-of-funds path. Add allocation percentages or runway only after a reviewed operating model exists.

**Presenter notes (30–45 seconds):** We are raising one million dollars as the capital required to move from a working beta to evidence of a repeatable business. The financing price should be discussed against a current traction packet and with counsel, not inferred from the AI category. Carta reports that SAFEs represented 93% of pre-seed rounds on its platform in Q2 2026 and emphasizes that a valuation cap is a conversion ceiling, not a present company valuation. That informs instrument context, not our price. [Carta SAFE analysis](https://carta.com/uk/en/data/safe-valuation-caps-q2-2026/)

## Appendix — likely investor questions and evidence needed

This is a diligence checklist, not a second deck.

| Question | Honest answer now | Evidence required before a strong claim |
| --- | --- | --- |
| Who is the first customer? | Agent-native developers and builders are the current hypothesis. | Qualified interview set, workflow frequency, alternatives used, and cohort definition. |
| How painful is the interruption? | The beta demonstrates the loop; frequency and severity are unmeasured. | Dated attention events, completion rate, resolution-time buckets, and qualitative interviews. |
| Why Watch instead of phone only? | The Watch offers immediate attention and a current real terminal; relative value is unproved. | Surface-level usage, task outcomes, and interview evidence without collecting content. |
| Does it work away from home? | Only over a reachable LAN or an existing VPN today; there is no LeSearch relay. | Reachability strategy, threat model, reliability tests, and shipped-product evidence. |
| Is it secure and private? | No account; current bearer-token HTTP assumes a trusted private network; optional daemon heartbeat exists. | Independent security review, disclosure audit, transport roadmap, and analytics schema verification. |
| What is the traction? | Early TestFlight and daily small-fleet use; no investor-grade cohort data yet. | Consented activation and D7/D30 cohorts with dates, denominators, channels, and failure classes. |
| How does it make money? | Individual Pro and later team plans are hypotheses; no validated price is claimed. | Pricing experiment, paid conversion, churn/refund reasons, support load, and gross-margin model. |
| Why $1M? | It funds the next proof milestones, not a predetermined valuation. | Reviewed operating budget, hiring/vendor plan, milestone timing, and financing counsel. |
