# Privacy-preserving analytics boundary

Status: current-state record and proposal. No product analytics, PostHog SDK, survey, replay, dashboard, or feature flag was added or changed.

## Current implementation

The only telemetry in the active product is the daemon's optional daily heartbeat in `install/payload/meshd/telemetry.ts`, stored through `supabase/migrations/20260824120000_telemetry_events.sql`.

It sends a pseudonymous, non-account-linked installation ID, daemon version, platform, uptime bucket, and fixed coarse hook-event counters. It excludes commands, keystrokes, terminal/screen content, prompts, paths, hostnames, and user-derived strings. `MESHD_TELEMETRY=off` disables it. `README.md` and `web/privacy.html` make the same promise.

The apps currently collect no analytics. `web/privacy.html` also promises no analytics SDK or tracking cookies. That is the current public contract.

## Existing PostHog workspace

Read-only inventory on 2026-08-30 found one LeSearch AI project (**Default project**, ID
`507240`). It already contains historical custom-event names `marketing_page_view`,
`terminal_ready`, `terminal_resized`, and `ws_connected`; it had no active surveys.

Those names are not authorization to instrument the current beta. The active repository has
no PostHog SDK or event contract, and no PostHog setting, dashboard, survey, feature flag, or
event was changed during this launch work. Treat the workspace as a future reporting destination
only after the decision gate below is satisfied.

## PostHog decision gate

The team has PostHog access, but this repository does not implement it. Do not add it as a background task or publish a survey before an explicit privacy/product decision updates all three of:

1. `install/payload/meshd/telemetry.ts` if daemon behavior changes.
2. `README.md` and `web/privacy.html`.
3. App Store privacy disclosures and in-product consent.

Session replay must stay off for terminal, remote-screen, pairing, and device-control surfaces. Those screens can contain code, prompts, paths, credentials, and personal data.

## If consented product analytics is approved

Use a separate pseudonymous installation ID and an allow-list only. Candidate events are:

| Event | Allowed properties |
| --- | --- |
| `analytics_consent_updated` | `enabled`, `surface` |
| `pairing_started` / `pairing_completed` | `surface`, `result`, `failure_class` |
| `machine_connection_changed` | `connection_state`, `transport_class`, `capability_count` |
| `attention_received` / `attention_resolved` | `surface`, `resolution_class`, `resolution_seconds_bucket` |
| `agent_session_viewed` | `surface`, `session_count_bucket` |
| `screen_engagement` | `screen`, `active_seconds_bucket` |
| `feedback_survey_answered` | `survey_id`, `answer`, `coarse_cohort` |

Never send terminal content, prompts, code, files, paths, hostnames, IP addresses, tokens, notification bodies, screenshots, screen frames, or free-form logs. Verify the actual event schema before creating PostHog insights or survey targeting.

## First useful measures

- Pairing-start to pairing-complete conversion.
- Time to first reachable machine.
- Attention received-to-resolved rate and resolution-time buckets.
- Weekly retained installations with a meaningful supervision event.
- Connection failure classes by surface, without device identity.

An active user is a consented installation that completes a meaningful value event, not a passive page view.
