## Context

LeSearch Mesh already lets a person install a daemon and pair a phone with an 8-character code, with no account. The website account is a later, optional identity. The account is identity. The phone talks to the machine. A cloud copy of the mesh is out of scope. Install still works logged out. It is not a copy of `~/.mesh`, and signing in on the website does not move a mesh token, a tailnet address, or a host list onto a second device.

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
| Account flow check | PR 158, branch `cursor/account-flow-stub-e469` | `ec5014fd6209f975d0b63614cb50347616551820` |
| Sealed mailbox round trip | PR 159, branch `cursor/device-sync-roundtrip-e469` | `e4dd9e0d90254b14e97548b1419b2bc386cb6c17` |
| Route-gated draft | PR 160, branch `cursor/note-route-draft-e469` | `4c8a73a485cfb7acd6d4c83d577a2cf19f8ab29c` |
| Spoken note in | PR 162, branch `cursor/spoken-note-in-e469` | `4e14cab8c9a5edef4f509b7096fcf238f02ffc2d`; do not add a second speech-in path; does not prove a microphone |
| Spoken note to a held file | PR 164, branch `cursor/spoken-note-to-app-e469` | `f8031958bc9778d260931ea189ad002b1a5c5a02`; the held file is not executed |
| Account handlers | PR 165, branch `cursor/account-handler-check-e469` | `a519e171d909acded25f7b52c7a58f5c08740fc3`; service role stays on the admin delete |
| Sealed sync isolation | PR 166, branch `cursor/sync-rls-proof-e469` | `43696bf90ed2fa4d31c6dff6e3c05ccc6cd4b6d2`; user B cannot read user A's rows; SQL sha256 `cd47695328f67abb077b62e48b670ed7cf78d6f4a916348958229d1862445253`; a Mac skip when Postgres is absent is not the proof |
| Local sign-up | PR 167, branch `cursor/local-auth-proof-e469` | `54c896b180453861fc93182fadb9275fc138191f`; local stack, not the hosted project; a green Xcode job does not repeat Docker |
| Account delete cascade | PR 168, branch `cursor/account-delete-cascade-e469` | `7ee035703aa08e05102d6a10f013fbc2a6352dab`; deleting user A removes A's rows; user B stays |
| Pairing-code hold | PR 169, branch `cursor/jev-pairing-hold-e469` | `25c8672a6986df77314d2cc0dae44a8c8ac9d11a`; holds a pairing code, `hosts.json`, `~/.mesh/token`, and a mesh bearer; "summarize this paper" and "send a message" still allow; no live gateway call |
| Account pages on local auth | PR 170, branch `cursor/account-pages-local-auth-e469` | `e019f19eb7221672799b8cc7827717c425d4f40d`; `account.js` was not edited; this local stack returns a session on sign-up |
| Device and mailbox inserts through local PostgREST | PR 171, branch `cursor/local-device-rest-e469` | `f587e50b47e76f0bcfbafb4f6faa4b30ce8049d5`; user B cannot read user A's rows; daemon and Xcode CI green; identity SQL sha256 `cd47695328f67abb077b62e48b670ed7cf78d6f4a916348958229d1862445253` |
| Reset page sets a new password | PR 172, branch `cursor/local-password-reset-e469` | `e1ad9c374e704db11a34cc07ce65919238729e66`; the old password does not sign in; daemon and Xcode CI green |
| Account delete against local GoTrue | PR 175, branch `cursor/local-account-delete-e469` | `092a3df4db55a2a5092b56f81d74b5bb1ed395e4`; `delete-account.js` against local GoTrue; sign-in fails after delete; the other user stays; the handler was not edited; daemon and Xcode CI green |
| Signed-in device labels | PR 177, branch `cursor/account-device-labels-e469` | `4cadb598c486af1762c919b885f2a5c2ee26fbeb`; the signed-in page lists label and platform only; empty state is "Pairing still happens on the machine. This page lists labels only."; `account.js` was not edited; daemon CI and apps (Xcode) were green on check run 35709487427 |
| Email confirmation before first sign-in | PR 178, branch `cursor/account-email-confirm-e469` | `60fe069f4ecb253048a6f4a9f0455fe56a4c9846`; sign-up returns no session and writes no profile; after the local confirmation link, sign-in writes `{id, username}`; the other user cannot select that profile; `account.js` was not edited; the script turns confirmations on for the run and restores them to off; identity SQL sha256 `cd47695328f67abb077b62e48b670ed7cf78d6f4a916348958229d1862445253`; daemon CI green on check run 35710247197; apps (Xcode) pending when recorded |
| Confirmation message omits sealed material | PR 184, branch `cursor/confirm-mail-leak-e469` | `1fbb977cd3c1c43ddfbcbce91edceb55995cc10c`; adds only `experiments/local-auth/prove-confirm-mail.sh`; the local confirmation message, sign-up response, and confirmation redirect omit mailbox ciphertext, the device public key, and a mesh-token sentinel; sign-in writes `{id, username}`; a second user cannot select the first profile, device, or mailbox; the owner reads ciphertext from the database; `account.js` and `001_identity.sql` were not edited; identity SQL sha256 `cd47695328f67abb077b62e48b670ed7cf78d6f4a916348958229d1862445253`; the stack run is on the draft; this handoff did not re-run Docker; daemon CI and apps (Xcode) were both green on check run 35712017549; not the hosted Supabase project |
| Recovery message omits sealed material | PR 188, branch `cursor/recovery-mail-leak-e469` | `c3d8f0fc291c3780dc04fd81c467a4fc46b75af3`; adds only `experiments/local-auth/prove-recovery-mail.sh`; after a confirmed local user exists, the recovery email, the recovery response, and the redirect omit mailbox ciphertext, the device public key, and a mesh-token sentinel; the private key is not stored; the reset page submits `new-password`; the new password signs in; the old password does not; the owner reads ciphertext from the database; a second user cannot select the first profile, device, or mailbox; `account.js` and `001_identity.sql` were not edited; identity SQL sha256 `cd47695328f67abb077b62e48b670ed7cf78d6f4a916348958229d1862445253`; the stack run is on the draft; this handoff did not re-run Docker; daemon CI and apps (Xcode) were both green on check run 35714118771; not the hosted Supabase project |

The only Supabase project in the LeSearch AI org is the heartbeat database `zmisjteztezaqfflwbgf`. Identity SQL is not applied there. Production `mesh.lesearch.ai` is unchanged. The Vercel preview of PR 150 still redirects to Vercel sign-in. Local proofs on pull requests 166, 167, 168, 170, 171, 172, 175, 177, 178, 184, and 188 are local stacks. They are not a hosted Supabase project, a production deploy, a live Jev call, or app sign-in. Pull request 177's daemon check and apps (Xcode) check were both green on check run 35709487427. Pull request 184's stack run stays on that draft. Daemon CI and apps (Xcode) were both green on check run 35712017549. Pull request 188's stack run stays on that draft. This handoff did not re-run Docker. Daemon CI and apps (Xcode) were both green on check run 35714118771.

Stakeholders: the person with the account (email and password only), Ritik (confirms the new project and the open product decisions), and the agent executing this change (spec files only).

## Goals / Non-Goals

**Goals:**

- Give the next agent one contract for what an account is, which database it uses, and which calls are still blocked.
- Keep install and pairing working with nobody signed in.
- Keep machine addresses, mailbox plaintext, and the device private key off the website and off the account database.
- Make the two waits obvious: Ritik's $10/month project, and a credit card on the Vercel team.
- Point later agents at the finished drafts so those slices are not rebuilt.

**Non-Goals:**

- A second copy of any finished draft in the table above, including the node seal/open helper (PR 138), the Swift seal check (PR 141), the menu-bar sealed upload bodies (PR 152; that file is not in the Xcode target), the account flow check (PR 158), the sealed mailbox round trip (PR 159), the route-gated draft (PR 160), spoken note in (PR 162), spoken note to a held file (PR 164), the account handlers (PR 165), sealed sync isolation (PR 166), local sign-up (PR 167), account delete cascade (PR 168), the pairing-code hold (PR 169), account pages on local auth (PR 170), device and mailbox inserts through local PostgREST (PR 171), the reset page (PR 172), account delete against local GoTrue (PR 175), signed-in device labels (PR 177), email confirmation before first sign-in (PR 178), the confirmation-mail omission proof (PR 184), and the recovery-mail omission proof (PR 188).
- A second speech-in path beside PR 162.
- Creating the Supabase project, pasting SQL into the heartbeat project, or writing any key into git.
- Calling the AI Gateway.
- Editing `Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `project.yml`, or pairing code (`install/payload/meshd/pair.ts` and the pairing flow). This change is spec files only.
- A sign-in screen in the iPhone, Watch, or menu-bar app.
- A price, a Pro flag, a machine cap, or a relay.
- Treating a Mac Postgres skip, a green Xcode job, or a local Docker stack as hosted proof.

## Decisions

### 1. The account database is a new project, not the heartbeat

An account stores email, username, device labels, public keys, and sealed blobs. The heartbeat stores version, platform, uptime in whole hours, coarse numeric counters, and a random install id. Linking them would let a heartbeat row identify a person.

Alternative considered: reuse `zmisjteztezaqfflwbgf` and add account tables beside the heartbeat. Rejected. That is the telemetry project. Do not apply identity SQL to the telemetry project. Do not add a foreign key from an account table to the heartbeat install id. The anon key already committed for heartbeats stays insert-only for heartbeats.

The new project does not exist yet. Real sign-up waits on Ritik confirming a new $10/month Supabase project. Do not create that project. Local auth proofs (PR 167, PR 170) run on a local stack only.

### 2. Finished drafts are the implementation

PR 135 is the identity SQL. PR 150 is the account pages. PR 138 is the node seal/open helper. PR 141 is the Swift seal check. PR 152 is the menu-bar sealed upload bodies, and that file is not in the Xcode target. PR 155 and PR 157 are the key file and its Swift reader. PR 154 is the note draft. PR 156 is the Jev filter. PR 158 is the account flow check. PR 159 is the sealed mailbox round trip. PR 160 is the route-gated draft. PR 162 is spoken note in. PR 164 is spoken note to a held file. PR 165 is the account handlers. PR 166 is sealed sync isolation. PR 167 is local sign-up. PR 168 is account delete cascade. PR 169 is the pairing-code hold. PR 170 is account pages on local auth. PR 171 is device and mailbox inserts through local PostgREST. PR 172 is the reset page. PR 175 is account delete against local GoTrue. PR 177 is signed-in device labels. PR 178 is email confirmation before first sign-in. PR 184 is the confirmation-mail omission proof, and it adds only `experiments/local-auth/prove-confirm-mail.sh`. PR 188 is the recovery-mail omission proof, and it adds only `experiments/local-auth/prove-recovery-mail.sh`. An agent who needs one of those behaviors opens that pull request and re-checks the tip. Do not start another copy of any of them.

Alternative considered: re-implement each slice on `main` inside this change so the spec and the code land together. Rejected. A second copy is how a finished slice gets lost, and this change is spec files only.

### 3. The website shows labels, and the private key stays on the machine

The website does not render machine IPs, including for the signed-in owner. The schema has nowhere to put an address. Password reset sets a new password and does not grant mailbox plaintext. PR 172 is that reset proof: the reset page sets a new password, and the old password does not sign in. The signed-in page lists label and platform only. PR 177 is that labels proof. Its empty state is "Pairing still happens on the machine. This page lists labels only." `account.js` was not edited on PR 177. The device private key stays on the machine: Apple Keychain, or `~/.mesh/device.key` mode 600. The upload is the public key and ciphertext.

Alternative considered: let password reset or a new device download host list plaintext so a second phone "just works." Rejected. That is the cloud copy of `~/.mesh` this launch exists to avoid. Losing every device means pairing again with the 8-character code. The account still exists; the secrets were never in it.

The key-file format is PR 157. Do not start another format. PR 138 is the node seal/open helper. PR 141 is the Swift seal check. PR 152 is the menu-bar sealed upload bodies, and that file is not in the Xcode target. Do not start another copy of any of those three.

### 4. Jev stays a local filter until a card exists

PR 156 already holds the filter. PR 169 extends the hold list for a pairing code, `hosts.json`, `~/.mesh/token`, and a mesh bearer, while "summarize this paper" and "send a message" still allow. A live Jev call waits on a credit card on the Vercel team. Do not call the gateway. Do not commit a key. `AI_GATEWAY_API_KEY` absent means skip. The marketing site does not proxy agent state.

Alternative considered: mint a gateway key or retry `POST https://ai-gateway.vercel.sh/v1/evaluate` from this agent. Rejected. There is no card, and a key in git is a leak.

### 5. Shared contracts stay untouched in this change

`Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `project.yml`, and pairing code are one-agent files. This change does not edit them. The daemon does not gain a login route or a Supabase client. Deleting an account does not rotate mesh tokens and does not reach a machine.

### 6. Local proofs stay local

PR 166 proves user B cannot read user A's rows against a throwaway Postgres cluster. The identity SQL sha256 is `cd47695328f67abb077b62e48b670ed7cf78d6f4a916348958229d1862445253`. A Mac skip when Postgres is absent is not that proof. PR 171 inserts a device and a mailbox ciphertext through local PostgREST. User B cannot read user A's rows. The same identity SQL sha256 applies. Daemon and Xcode CI were green. PR 168 deletes user A and removes A's rows while user B stays. PR 175 runs `delete-account.js` against local GoTrue. Sign-in fails after delete. The other user stays. The handler was not edited. Daemon and Xcode CI were green. PR 172 runs the reset page on a local stack. The new password is set. The old password does not sign in. Daemon and Xcode CI were green. PR 167 and PR 170 exercise a local Supabase CLI stack; they are not the hosted project. A green Xcode job does not repeat Docker. PR 170 returns a session on sign-up because confirmations stay off in that stack. PR 178 turns confirmations on for its run only, restores them to off on exit, and proves sign-up returns no session and writes no profile until the local confirmation link is opened; sign-in then writes `{id, username}`; the other user cannot select that profile; `account.js` was not edited; the same identity SQL sha256 applies. Daemon CI was green on check run 35710247197; apps (Xcode) was pending when recorded. PR 184 proves the local confirmation message, the sign-up response, and the confirmation redirect omit mailbox ciphertext, the device public key, and a mesh-token sentinel. Sign-in writes `{id, username}`. A second user cannot select the first profile, device, or mailbox. The owner reads ciphertext from the database. The proof adds only `experiments/local-auth/prove-confirm-mail.sh`. `account.js` and `001_identity.sql` were not edited. The same identity SQL sha256 applies. The stack run is on the draft. This handoff did not re-run Docker. Daemon CI and apps (Xcode) were both green on check run 35712017549. It is not the hosted project. PR 188 proves that after a confirmed local user exists, the recovery email, the recovery response, and the redirect omit mailbox ciphertext, the device public key, and a mesh-token sentinel. The private key is not stored. The reset page submits `new-password`. The new password signs in. The old password does not. The owner reads ciphertext from the database. A second user cannot select the first profile, device, or mailbox. The proof adds only `experiments/local-auth/prove-recovery-mail.sh`. `account.js` and `001_identity.sql` were not edited. The same identity SQL sha256 applies. The stack run is on the draft. This handoff did not re-run Docker. Daemon CI and apps (Xcode) were both green on check run 35714118771. It is not the hosted project. PR 177 lists label and platform only on the signed-in page, with the empty state "Pairing still happens on the machine. This page lists labels only." `account.js` was not edited. Daemon CI and apps (Xcode) were green on check run 35709487427. PR 165 keeps the service role on the admin delete. PR 162 does not prove a microphone. PR 164's held file is not executed. PR 170 did not edit `account.js`.

## Risks / Trade-offs

- [An agent applies PR 135's SQL to `zmisjteztezaqfflwbgf`] → The tasks refuse any remote apply. The heartbeat project stays the heartbeat. Identity SQL runs only after Ritik names a different project, and not inside this change.
- [An agent rebuilds a finished draft from the table] → The tasks point at the existing pull request and stop. A new file for one of those slices is a failed task.
- [An agent treats a Postgres skip, a green Xcode job, or a local Docker stack as hosted proof] → The design names those limits. Hosted sign-up still waits on Ritik's project.
- [A key lands in the diff] → The proof command searches the change for `eyJ`, `service_role`, and `AI_GATEWAY_API_KEY` and must find none.
- [The website shows an address, or reset decrypts the mailbox] → The specs treat both as failure. The existing pages are the UI; this change does not add a new one.
- [Someone treats the stale "implement task 1" handoff as the next job] → This change supersedes that handoff. Tasks 1–4 already sit on PR 150.
- [Native apps grow a sign-in screen in this window] → Out of scope. No task edits Swift or `project.yml`.
- [An agent adds a second speech-in path] → PR 162 is the speech-in path. Do not open another.

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
