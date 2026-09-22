## ADDED Requirements

### Requirement: Real sign-up waits on a confirmed project

Real sign-up SHALL wait until Ritik confirms a new $10/month Supabase project. Until that confirmation, an agent MUST NOT create that project, MUST NOT apply identity SQL to any remote project, and MUST NOT put keys in git.

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are set on the Vercel project outside git, and only after the new project exists. The service role is only for delete.

Local sign-up on pull request 167, account pages on local auth on pull request 170, device and mailbox inserts on pull request 171, the reset page on pull request 172, account delete on pull request 175, signed-in device labels on pull request 177, email confirmation before first sign-in on pull request 178, and the confirmation-mail omission proof on pull request 184 are local stacks. They are not the hosted project. A green Xcode job does not repeat Docker. Pull request 177's daemon check and apps (Xcode) check were both green on check run 35709487427. Pull request 178's daemon check was green on check run 35710247197; apps (Xcode) was pending when recorded. Pull request 184 adds only `experiments/local-auth/prove-confirm-mail.sh`. The stack run is on that draft. This handoff did not re-run Docker. Daemon CI and apps (Xcode) were both green on check run 35712017549.

#### Scenario: Ritik has not confirmed the project

- **WHEN** an agent reaches the step that would create a Supabase project or run identity SQL on a remote host
- **THEN** the agent stops
- **AND** no new Supabase project exists because of this change
- **AND** the diff contains no Supabase URL, anon key, or service role key

#### Scenario: Someone points sign-up at the heartbeat project

- **WHEN** an agent uses project `zmisjteztezaqfflwbgf` as the account database
- **THEN** sign-up is not configured
- **AND** identity SQL is not applied there

#### Scenario: The new project is confirmed later

- **WHEN** Ritik has confirmed the new project in writing and a human pastes the existing identity SQL from pull request 135 into that project's SQL editor
- **THEN** the keys are entered in Vercel environment settings and stay out of git
- **AND** this spec change still does not contain those keys

#### Scenario: A local auth proof is treated as hosted

- **WHEN** an agent reads pull request 167, 170, 171, 172, 175, 177, 178, or 184
- **THEN** that proof remains a local stack
- **AND** the agent does not claim a hosted Supabase project, a production deploy, or app sign-in
- **AND** pull request 184's daemon check and apps (Xcode) check were both green on check run 35712017549
- **AND** the agent re-checks pull request 177 or 178 with `gh pr checks` before calling apps (Xcode) green again

### Requirement: A live Jev call waits on a credit card

A live Jev call SHALL wait until a credit card is on the Vercel team. Until that card exists, an agent MUST NOT call the gateway and MUST NOT commit a key. The existing filter on pull request 156 remains the filter. The pairing-code hold on pull request 169 holds a pairing code, `hosts.json`, `~/.mesh/token`, and a mesh bearer, while "summarize this paper" and "send a message" still allow, with no live gateway call. A missing `AI_GATEWAY_API_KEY` means the check skips.

#### Scenario: No card is on the team

- **WHEN** an agent is about to call `POST https://ai-gateway.vercel.sh/v1/evaluate` or any other AI Gateway URL
- **THEN** the agent does not send the request
- **AND** the diff contains no `AI_GATEWAY_API_KEY` value

#### Scenario: The filter is missing from the branch an agent is editing

- **WHEN** an agent needs the Jev filter and it is not in the current tree
- **THEN** the agent uses pull request 156
- **AND** the agent does not write a second filter in this change

#### Scenario: The pairing-code hold is needed

- **WHEN** an agent needs the hold for a pairing code, `hosts.json`, `~/.mesh/token`, or a mesh bearer
- **THEN** the agent uses pull request 169
- **AND** the agent does not claim a live gateway call

### Requirement: This change is spec files only

An agent executing this change MUST NOT edit `Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `project.yml`, or pairing code. The diff for this change SHALL contain only files under `openspec/changes/account-launch-handoff/`.

#### Scenario: The change is opened as a pull request

- **WHEN** the branch for this change is compared with `main`
- **THEN** every changed path is under `openspec/changes/account-launch-handoff/`
- **AND** `Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `project.yml`, and `install/payload/meshd/pair.ts` are absent from the diff

#### Scenario: An executing agent starts a product edit

- **WHEN** an agent begins to add an account page, a SQL file, a node seal/open helper, a Swift seal check, menu-bar sealed upload bodies, a key file, a note draft, a Jev filter, an account flow check, a sealed mailbox round trip, a route-gated draft, a spoken-note path, an account handler check, a sync RLS proof, a local-auth proof, an account delete cascade, a pairing-code hold, account pages on local auth, a local PostgREST device proof, a reset-page proof, a local GoTrue delete proof, a device-labels proof, an email-confirmation proof, a confirmation-mail proof, or a daemon route while executing this change
- **THEN** the agent stops that edit
- **AND** the finished slice stays on its existing pull request: pages on 150, identity SQL on 135, the node seal/open helper on 138, the Swift seal check on 141, the menu-bar sealed upload bodies on 152 (that file is not in the Xcode target), the key file on 155 and 157, the note draft on 154, the Jev filter on 156, the account flow check on 158, the sealed mailbox round trip on 159, the route-gated draft on 160, spoken note in on 162, spoken note to a held file on 164, the account handlers on 165, sealed sync isolation on 166, local sign-up on 167, account delete cascade on 168, the pairing-code hold on 169, account pages on local auth on 170, device and mailbox inserts through local PostgREST on 171, the reset page on 172, account delete against local GoTrue on 175, signed-in device labels on 177, email confirmation before first sign-in on 178, the confirmation-mail omission proof on 184

### Requirement: Finished slices are not new work

An agent MUST treat the account pages, the identity SQL, the node seal/open helper, the Swift seal check, the menu-bar sealed upload bodies, the key file, the note draft, the Jev filter, the account flow check, the sealed mailbox round trip, the route-gated draft, spoken note in, spoken note to a held file, the account handlers, sealed sync isolation, local sign-up, account delete cascade, the pairing-code hold, account pages on local auth, device and mailbox inserts through local PostgREST, the reset page, account delete against local GoTrue, signed-in device labels, email confirmation before first sign-in, and the confirmation-mail omission proof as already drafted. Pull request 138 is the node seal/open helper. Pull request 141 is the Swift seal check. Pull request 152 is the menu-bar sealed upload bodies, and that file is not in the Xcode target. Pull request 158 is the account flow check. Pull request 159 is the sealed mailbox round trip. Pull request 160 is the route-gated draft. Pull request 162 is spoken note in; do not add a second speech-in path; it does not prove a microphone. Pull request 164 is spoken note to a held file; the held file is not executed. Pull request 165 is the account handlers; the service role stays on the admin delete. Pull request 166 is sealed sync isolation; user B cannot read user A's rows; SQL sha256 `cd47695328f67abb077b62e48b670ed7cf78d6f4a916348958229d1862445253`; a Mac skip when Postgres is absent is not the proof. Pull request 167 is local sign-up on a local stack. Pull request 168 is account delete cascade; deleting user A removes A's rows and user B stays. Pull request 169 is the pairing-code hold. Pull request 170 is account pages on local auth; `account.js` was not edited; that local stack returns a session on sign-up. Pull request 171 is device and mailbox inserts through local PostgREST; user B cannot read user A's rows; daemon and Xcode CI were green; identity SQL sha256 `cd47695328f67abb077b62e48b670ed7cf78d6f4a916348958229d1862445253`. Pull request 172 is the reset page; it sets a new password; the old password does not sign in; daemon and Xcode CI were green. Pull request 175 is account delete against local GoTrue; `delete-account.js`; sign-in fails after delete; the other user stays; the handler was not edited; daemon and Xcode CI were green. Pull request 177 is signed-in device labels; the page lists label and platform only; the empty state is "Pairing still happens on the machine. This page lists labels only."; `account.js` was not edited; daemon CI and apps (Xcode) were green on check run 35709487427. Pull request 178 is email confirmation before first sign-in; sign-up returns no session and writes no profile; after the local confirmation link, sign-in writes `{id, username}`; the other user cannot select that profile; `account.js` was not edited; the script turns confirmations on for the run and restores them to off; identity SQL sha256 `cd47695328f67abb077b62e48b670ed7cf78d6f4a916348958229d1862445253`; daemon CI was green on check run 35710247197; apps (Xcode) was pending when recorded. Pull request 184 is the confirmation-mail omission proof; it adds only `experiments/local-auth/prove-confirm-mail.sh`; the local confirmation message, sign-up response, and confirmation redirect omit mailbox ciphertext, the device public key, and a mesh-token sentinel; sign-in writes `{id, username}`; a second user cannot select the first profile, device, or mailbox; the owner reads ciphertext from the database; `account.js` and `001_identity.sql` were not edited; identity SQL sha256 `cd47695328f67abb077b62e48b670ed7cf78d6f4a916348958229d1862445253`; the stack run is on the draft; this handoff did not re-run Docker; daemon CI and apps (Xcode) were both green on check run 35712017549; it is not the hosted project. The agent MUST re-check the pull request tip before editing any of those files, and MUST NOT open a second implementation from this change.

No task in this change requires Arya's physical iPhone or Apple Watch.

#### Scenario: The named tip is still the draft

- **WHEN** an agent re-checks pull request 150, 135, 138, 141, 152, 154, 155, 156, 157, 158, 159, 160, 162, 164, 165, 166, 167, 168, 169, 170, 171, 172, 175, 177, 178, or 184 and the tip still matches the design
- **THEN** the agent leaves that pull request as the implementation
- **AND** this change gains no product file

#### Scenario: A pull request tip has moved

- **WHEN** the tip of one of those pull requests differs from the hash named in the design
- **THEN** the agent reads the new tip before any conclusion about that slice
- **AND** the agent still does not rebuild the slice inside this change

#### Scenario: An agent is asked to rebuild a sealed slice

- **WHEN** an agent is asked to rebuild the node seal/open helper, the Swift seal check, the menu-bar sealed upload bodies, the account flow check, the sealed mailbox round trip, the route-gated draft, spoken note in, spoken note to a held file, the account handlers, sealed sync isolation, local sign-up, account delete cascade, the pairing-code hold, account pages on local auth, device and mailbox inserts through local PostgREST, the reset page, account delete against local GoTrue, signed-in device labels, email confirmation before first sign-in, or the confirmation-mail omission proof
- **THEN** the agent points at pull requests 138, 141, 152, 158, 159, 160, 162, 164, 165, 166, 167, 168, 169, 170, 171, 172, 175, 177, 178, or 184
- **AND** the agent does not open a second copy
