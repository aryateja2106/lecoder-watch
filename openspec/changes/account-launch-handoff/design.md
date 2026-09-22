## Context

LeSearch Mesh already lets a person install a daemon and pair a phone with an 8-character code, with no account. The website account is a later, optional identity. It is not a copy of `~/.mesh`, and signing in on the website does not move a mesh token, a tailnet address, or a host list onto a second device.

The implementation of the launch slices that already exist is on draft pull requests. Re-check each tip before editing the same files. This design does not replace those drafts.

| Slice | Where it already lives | Tip named on 2026-09-22 |
|---|---|---|
| Account pages, entry, device labels, delete control | PR 150, branch `cursor/account-site-e469`, base `cursor/account-copy-e469` | `41cdbbc` |
| Identity SQL | PR 135, branch `cursor/account-schema-e469` | the open draft; passed on a throwaway local database; applied to no remote project |
| Note draft that writes a held file | PR 154, branch `cursor/note-to-app-e469` | `cba3ac7` |
| Device private key file, mode 600 | PR 155, branch `cursor/device-key-file-e469` | `03e40f5` |
| Swift reader of that 64-byte file, and the key-file format | PR 157, branch `cursor/swift-device-key-e469` | `bb1dd5c` |
| Node seal/open helper | PR 138, branch `cursor/sealed-mailbox-e469` | `45904dd` |
| Swift seal check | PR 141, branch `cursor/swift-seal-e469` | `781613e` |
| Menu-bar sealed upload bodies | PR 152, branch `cursor/menu-bar-sync-e469` | `e890e4d`; the file is not in the Xcode target |
| Jev filter and the note route that holds a secret | PR 156, branch `cursor/jev-note-route-e469` | open draft; the check passed with no gateway call |
| Account flow check | PR 158, branch `cursor/account-flow-stub-e469` | `ec5014f` |
| Sealed mailbox round trip | PR 159, branch `cursor/device-sync-roundtrip-e469` | `e4dd9e0` |
| Route-gated draft | PR 160, branch `cursor/note-route-draft-e469` | `4c8a73a` |

The only Supabase project in the LeSearch AI org is the heartbeat database `zmisjteztezaqfflwbgf`. Identity SQL is not applied there. Production `mesh.lesearch.ai` is unchanged. The Vercel preview of PR 150 still redirects to Vercel sign-in.

Stakeholders: the person with the account (email and password only), Ritik (confirms the new project and the open product decisions), and the agent executing this change (spec files only).

## Goals / Non-Goals

**Goals:**

- Give the next agent one contract for what an account is, which database it uses, and which calls are still blocked.
- Keep install and pairing working with nobody signed in.
- Keep machine addresses, mailbox plaintext, and the device private key off the website and off the account database.
- Make the two waits obvious: Ritik's $10/month project, and a credit card on the Vercel team.

**Non-Goals:**

- A second copy of the account pages, the identity SQL, the node seal/open helper (PR 138), the Swift seal check (PR 141), the menu-bar sealed upload bodies (PR 152; that file is not in the Xcode target), the key file, the note draft, the Jev filter, the account flow check (PR 158), the sealed mailbox round trip (PR 159), or the route-gated draft (PR 160).
- Creating the Supabase project, pasting SQL into the heartbeat project, or writing any key into git.
- Calling the AI Gateway.
- Editing `Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `project.yml`, or pairing code (`install/payload/meshd/pair.ts` and the pairing flow). This change is spec files only.
- A sign-in screen in the iPhone, Watch, or menu-bar app.
- A price, a Pro flag, a machine cap, or a relay.

## Decisions

### 1. The account database is a new project, not the heartbeat

An account stores email, username, device labels, public keys, and sealed blobs. The heartbeat stores version, platform, uptime in whole hours, coarse numeric counters, and a random install id. Linking them would let a heartbeat row identify a person.

Alternative considered: reuse `zmisjteztezaqfflwbgf` and add account tables beside the heartbeat. Rejected. That is the telemetry project. Do not apply identity SQL to the telemetry project. Do not add a foreign key from an account table to the heartbeat install id. The anon key already committed for heartbeats stays insert-only for heartbeats.

The new project does not exist yet. Real sign-up waits on Ritik confirming a new $10/month Supabase project. Do not create that project.

### 2. Finished drafts are the implementation

PR 135 is the identity SQL. PR 150 is the account pages. PR 138 is the node seal/open helper. PR 141 is the Swift seal check. PR 152 is the menu-bar sealed upload bodies, and that file is not in the Xcode target. PR 155 and PR 157 are the key file and its Swift reader. PR 154 is the note draft. PR 156 is the Jev filter. PR 158 is the account flow check. PR 159 is the sealed mailbox round trip. PR 160 is the route-gated draft. An agent who needs one of those behaviors opens that pull request and re-checks the tip. Do not start another copy of any of them.

Alternative considered: re-implement each slice on `main` inside this change so the spec and the code land together. Rejected. A second copy is how a finished slice gets lost, and this change is spec files only.

### 3. The website shows labels, and the private key stays on the machine

The website does not render machine IPs, including for the signed-in owner. The schema has nowhere to put an address. Password reset sets a new password and does not grant mailbox plaintext. The device private key stays on the machine: Apple Keychain, or `~/.mesh/device.key` mode 600. The upload is the public key and ciphertext.

Alternative considered: let password reset or a new device download host list plaintext so a second phone "just works." Rejected. That is the cloud copy of `~/.mesh` this launch exists to avoid. Losing every device means pairing again with the 8-character code. The account still exists; the secrets were never in it.

The key-file format is PR 157. Do not start another format. PR 138 is the node seal/open helper. PR 141 is the Swift seal check. PR 152 is the menu-bar sealed upload bodies, and that file is not in the Xcode target. Do not start another copy of any of those three.

### 4. Jev stays a local filter until a card exists

PR 156 already holds the filter. A live Jev call waits on a credit card on the Vercel team. Do not call the gateway. Do not commit a key. `AI_GATEWAY_API_KEY` absent means skip. The marketing site does not proxy agent state.

Alternative considered: mint a gateway key or retry `POST https://ai-gateway.vercel.sh/v1/evaluate` from this agent. Rejected. There is no card, and a key in git is a leak.

### 5. Shared contracts stay untouched in this change

`Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `project.yml`, and pairing code are one-agent files. This change does not edit them. The daemon does not gain a login route or a Supabase client. Deleting an account does not rotate mesh tokens and does not reach a machine.

## Risks / Trade-offs

- [An agent applies PR 135's SQL to `zmisjteztezaqfflwbgf`] → The tasks refuse any remote apply. The heartbeat project stays the heartbeat. Identity SQL runs only after Ritik names a different project, and not inside this change.
- [An agent rebuilds the pages, SQL, node seal/open helper, Swift seal check, menu-bar sealed upload bodies, key file, note draft, filter, account flow check, sealed mailbox round trip, or route-gated draft] → The tasks point at the existing pull request and stop. A new file for one of those slices is a failed task.
- [A key lands in the diff] → The proof command searches the change for `eyJ`, `service_role`, and `AI_GATEWAY_API_KEY` and must find none.
- [The website shows an address, or reset decrypts the mailbox] → The specs treat both as failure. The existing pages are the UI; this change does not add a new one.
- [Someone treats the stale "implement task 1" handoff as the next job] → This change supersedes that handoff. Tasks 1–4 already sit on PR 150.
- [Native apps grow a sign-in screen in this window] → Out of scope. No task edits Swift or `project.yml`.

## Migration Plan

This change deploys nothing. Merging it adds the spec under `openspec/changes/account-launch-handoff/` and leaves production, the heartbeat project, and the daemon as they are.

Rollback is reverting that commit. There is no schema migration, no env var, and no feature flag in this change.

After Ritik confirms the new project, a later human pastes the existing SQL from PR 135 into that project's SQL editor and sets `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` on the Vercel project outside git. The service role is only for delete. That step is not a task for this change, and it is not a reason to create the project from an agent.

## Open Questions

Ritik still has to answer these. They do not block this spec, and an agent does not answer them by writing product code.

1. Price. Nothing in the app, daemon, or site checks a license today.
2. What Pro unlocks. No `plan` column until that answer exists.
3. Whether an account may see machine IPs. This design's default is no, including for the signed-in owner.
4. Whether an account is required to install. This design's default is no.
5. Whether email confirmation is required before the first sign-in. Default yes.
6. Whether username is the sign-in identifier. Default no. Sign-in is email. Username is the unique handle.
