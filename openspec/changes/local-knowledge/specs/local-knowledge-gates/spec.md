## Purpose

Gates that keep this change to handoff specs, name the finished draft tips, and stop a later agent from rebuilding speech, notes, or held drafts.

## ADDED Requirements

### Requirement: Finished drafts are not new work

An agent MUST treat local PDF notes, spoken-out via a local `MESH_TTS` binary, the note-to-held-file draft, the route-gated draft, and spoken-in via a local `MESH_STT` binary as already drafted. Pull request 139 is the local PDF notes (tip `9d2827b` on `cursor/local-knowledge-e469` when verified). Pull request 145 is spoken-out (tip `ea86b77` on `cursor/spoken-note-e469`). Pull request 154 is the note to a held file (tip `cba3ac7` on `cursor/note-to-app-e469`). Pull request 160 is the route-gated draft (tip `4c8a73a` on `cursor/note-route-draft-e469`); Jev chooses a route and does not write the reply, and there is no live gateway call in that draft. Pull request 162 is spoken-in (tip `4e14cab` on `cursor/spoken-note-in-e469`); a remote URL does not run, and a second speech-in path MUST NOT be started.

The agent MUST re-check each pull request tip with `gh` before editing any of those files, and MUST NOT open a second implementation from this change.

#### Scenario: The named tip is still the draft

- **WHEN** an agent re-checks pull request 139, 145, 154, 160, or 162 and the tip still matches the design
- **THEN** the agent leaves that pull request as the implementation
- **AND** this change gains no product file for that slice

#### Scenario: A pull request tip has moved

- **WHEN** the tip of one of those pull requests differs from the hash named in the design
- **THEN** the agent reads the new tip before any conclusion about that slice
- **AND** the agent still does not rebuild the slice inside this change

### Requirement: This change is spec files only

An agent executing this change MUST NOT edit `Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `install/payload/meshd/pair.ts`, or `project.yml`. The diff for this change SHALL contain only files under `openspec/changes/local-knowledge/`.

#### Scenario: The change is opened as a pull request

- **WHEN** the branch for this change is compared with `main`
- **THEN** every changed path is under `openspec/changes/local-knowledge/`
- **AND** `Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `install/payload/meshd/pair.ts`, and `project.yml` are absent from the diff

#### Scenario: An executing agent starts a product edit

- **WHEN** an agent begins to add a knowledge module, a TTS path, an STT path, a held-file check, a route-gated draft, or a daemon route while executing this change
- **THEN** the agent stops that edit
- **AND** the finished slice stays on its existing pull request: notes on 139, spoken-out on 145, held file on 154, route-gated draft on 160, spoken-in on 162

### Requirement: server.ts registration is a later, single edit

This pull request MUST NOT edit `install/payload/meshd/server.ts`. On `origin/main` at the tip this handoff branched from, knowledge routes are not registered. Pull request 139 already registers them on its tip.

A later agent MUST check whether knowledge routes are already registered in the tree being edited. If they are, that agent MUST say so and MUST NOT add a second route. If they are not, one later task MAY register them only when no other agent holds `server.ts`.

#### Scenario: Routes are already registered

- **WHEN** a later agent finds the knowledge handler already registered in `server.ts`
- **THEN** the agent records that the route exists
- **AND** the agent does not add a second knowledge route

#### Scenario: Routes are missing and server.ts is free

- **WHEN** a later agent finds no knowledge registration and no other agent holds `server.ts`
- **THEN** one task may register the existing handler once
- **AND** that edit is outside this handoff pull request

### Requirement: No keys and no live gateway call

An agent MUST NOT commit an API key, a JWT, or a database URL. An agent MUST NOT call the AI Gateway from this change. Knowledge bodies MUST NOT go to the cloud. The local-brain harness proposal stays a spike and MUST NOT be merged as the shipping loop in this change.

#### Scenario: The change is searched for secrets

- **WHEN** an agent searches the change for a JWT-shaped string, a database URL, or a pasted gateway key
- **THEN** the search finds none
- **AND** the change contains no fetch or curl of the AI Gateway

#### Scenario: The harness proposal is treated as shipping work

- **WHEN** an agent is about to merge `openspec/changes/local-brain-and-harness/` as the coding loop
- **THEN** the agent stops
- **AND** that proposal remains a spike

### Requirement: Agents cannot prove a physical microphone or speaker

No task in this change requires Arya's physical iPhone, Apple Watch, microphone, or speaker. An agent MUST NOT claim that physical speech capture or playback works. Those checks are handed back to a human.

#### Scenario: A task would need a real microphone

- **WHEN** a later agent reaches a step whose only proof is that a physical microphone or speaker works
- **THEN** the agent stops and says that agents cannot prove that
- **AND** the spare-daemon checks against local binaries remain the agent-side proof
