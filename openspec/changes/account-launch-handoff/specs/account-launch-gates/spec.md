## ADDED Requirements

### Requirement: Real sign-up waits on a confirmed project

Real sign-up SHALL wait until Ritik confirms a new $10/month Supabase project. Until that confirmation, an agent MUST NOT create that project, MUST NOT apply identity SQL to any remote project, and MUST NOT put keys in git.

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are set on the Vercel project outside git, and only after the new project exists. The service role is only for delete.

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

### Requirement: A live Jev call waits on a credit card

A live Jev call SHALL wait until a credit card is on the Vercel team. Until that card exists, an agent MUST NOT call the gateway and MUST NOT commit a key. The existing filter on pull request 156 remains the filter. A missing `AI_GATEWAY_API_KEY` means the check skips.

#### Scenario: No card is on the team

- **WHEN** an agent is about to call `POST https://ai-gateway.vercel.sh/v1/evaluate` or any other AI Gateway URL
- **THEN** the agent does not send the request
- **AND** the diff contains no `AI_GATEWAY_API_KEY` value

#### Scenario: The filter is missing from the branch an agent is editing

- **WHEN** an agent needs the Jev filter and it is not in the current tree
- **THEN** the agent uses pull request 156
- **AND** the agent does not write a second filter in this change

### Requirement: This change is spec files only

An agent executing this change MUST NOT edit `Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `project.yml`, or pairing code. The diff for this change SHALL contain only files under `openspec/changes/account-launch-handoff/`.

#### Scenario: The change is opened as a pull request

- **WHEN** the branch for this change is compared with `main`
- **THEN** every changed path is under `openspec/changes/account-launch-handoff/`
- **AND** `Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `project.yml`, and `install/payload/meshd/pair.ts` are absent from the diff

#### Scenario: An executing agent starts a product edit

- **WHEN** an agent begins to add an account page, a SQL file, a seal, a key file, a note draft, a Jev filter, or a daemon route while executing this change
- **THEN** the agent stops that edit
- **AND** the finished slice stays on its existing pull request: pages on 150, identity SQL on 135, the seal on 152, the key file on 155 and 157, the note draft on 154, the Jev filter on 156

### Requirement: Finished slices are not new work

An agent MUST treat the account pages, the identity SQL, the seal, the key file, the note draft, and the Jev filter as already drafted. The agent MUST re-check the pull request tip before editing any of those files, and MUST NOT open a second implementation from this change.

No task in this change requires Arya's physical iPhone or Apple Watch.

#### Scenario: The named tip is still the draft

- **WHEN** an agent re-checks pull request 150, 135, 152, 154, 155, 156, or 157 and the tip still matches the design
- **THEN** the agent leaves that pull request as the implementation
- **AND** this change gains no product file

#### Scenario: A pull request tip has moved

- **WHEN** the tip of one of those pull requests differs from the hash named in the design
- **THEN** the agent reads the new tip before any conclusion about that slice
- **AND** the agent still does not rebuild the slice inside this change
