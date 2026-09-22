## Purpose

Gates that keep this change to handoff specs, name the finished draft tips, and stop a later agent from rebuilding speech, notes, holds, spoken replaces, the spoken-note draft, or the spoken replace speak.

## ADDED Requirements

### Requirement: Finished drafts are not new work

An agent MUST treat local PDF notes, spoken-out via a local `MESH_TTS` binary, the note-to-held-file draft, the route-gated draft, spoken-in via a local `MESH_STT` binary, the in-place note replace, the replaced-note draft, the replaced-note hold, the spoken note replace, the spoken-note draft, and the spoken replace speak as already drafted. Pull request 139 is the local PDF notes (tip `9d2827b` on `cursor/local-knowledge-e469` when verified). Pull request 145 is spoken-out (tip `ea86b77` on `cursor/spoken-note-e469`). Pull request 154 is the note to a held file (tip `cba3ac7` on `cursor/note-to-app-e469`). Pull request 160 is the route-gated draft (tip `4c8a73a` on `cursor/note-route-draft-e469`); Jev chooses a route and does not write the reply, and there is no live gateway call in that draft. Pull request 162 is spoken-in (tip `4e14cab` on `cursor/spoken-note-in-e469`); a remote URL does not run, and a second speech-in path MUST NOT be started. Pull request 174 is the in-place note replace (tip `426d66d7ae016a67b66b809a7cb4a10aaa300460` on `cursor/knowledge-note-update-e469`). Pull request 176 is the replaced-note draft (tip `ff4d633cf15c69776a314c79a4c243d39bf5cd31` on `cursor/updated-note-draft-e469`). Pull request 182 is the replaced-note hold (tip `56d8ae73883ac3276e7be01f16a949a016bb1253` on `cursor/updated-note-hold-e469`). Pull request 183 is the spoken note replace (tip `52ce62929a7c7e3c660943767311ac3c32d36ca8` on `cursor/spoken-note-replace-e469`). `server.ts` still calls `handleKnowledge` once on that tip. Pull request 187 is the spoken-note draft (tip `0baf37761f4dc6f42af017fb52513de3fb927e39` on `cursor/spoken-note-draft-e469`). It adds only `scripts/check-spoken-note-draft.sh`. Daemon CI and Xcode CI are both green on that tip. Pull request 189 is the spoken replace speak (tip `611f32131b3609580fb888916a263920b4452dc3` on `cursor/spoken-replace-speak-e469`). It speaks a replaced note with a local TTS binary. Daemon CI and Xcode CI are both green on that tip (check run `35714316679`). Neither pull request 187 nor pull request 189 proves a microphone or a speaker. A second `/knowledge` route MUST NOT be added.

The agent MUST re-check each pull request tip with `gh` before editing any of those files, and MUST NOT open a second implementation from this change.

#### Scenario: The named tip is still the draft

- **WHEN** an agent re-checks pull request 139, 145, 154, 160, 162, 174, 176, 182, 183, 187, or 189 and the tip still matches the design
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

- **WHEN** an agent begins to add a knowledge module, an in-place note replace, a replaced-note draft, a replaced-note hold, a spoken note replace, a spoken-note draft, a spoken replace speak, a TTS path, an STT path, a held-file check, a route-gated draft, or a daemon route while executing this change
- **THEN** the agent stops that edit
- **AND** the finished slice stays on its existing pull request: notes on 139, spoken-out on 145, held file on 154, route-gated draft on 160, spoken-in on 162, in-place replace on 174, replaced-note draft on 176, replaced-note hold on 182, spoken note replace on 183, spoken-note draft on 187, spoken replace speak on 189

### Requirement: server.ts registration is a later, single edit

This pull request MUST NOT edit `install/payload/meshd/server.ts`. On `origin/main`, `/knowledge` is unregistered. This line registers `handleKnowledge` once. A later agent MUST NOT add a second `/knowledge` route. Pull request 174 and pull request 176 did not edit `server.ts`. Pull request 182 and pull request 183 did not edit `server.ts`. On the spoken-replace tip, `server.ts` still calls `handleKnowledge` once. Pull request 187 did not edit `server.ts`. It adds only `scripts/check-spoken-note-draft.sh`. Pull request 189 did not edit `server.ts`. On that tip, `server.ts` still calls `handleKnowledge` once.

A later agent MUST check whether knowledge routes are already registered in the tree being edited. If they are, that agent MUST say so and MUST NOT add a second `/knowledge` route. If they are not, one later task MAY register the existing handler only when no other agent holds `server.ts`.

#### Scenario: Routes are already registered

- **WHEN** a later agent finds the knowledge handler already registered in `server.ts`
- **THEN** the agent records that `/knowledge` is already registered once
- **AND** the agent does not add a second `/knowledge` route

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

No task in this change requires Arya's physical iPhone, Apple Watch, microphone, or speaker. An agent MUST NOT claim that a microphone or a speaker was proven. A spoken note is a local binary transcript or a local TTS exit code. Those device checks are handed back to a human.

#### Scenario: A task would need a real microphone

- **WHEN** a later agent reaches a step whose only proof is that a physical microphone or speaker works
- **THEN** the agent stops and says that agents cannot prove that
- **AND** the agent records a local binary transcript or a local TTS exit code

### Requirement: The in-place note replace is already proven

Pull request 174 (`cursor/knowledge-note-update-e469`, tip `426d66d7ae016a67b66b809a7cb4a10aaa300460`, verified with `gh` on 2026-09-22) SHALL remain the in-place note replace. `POST /knowledge/:id` replaces that note's body in the same file. The list stays `{ id, title }`. A missing id creates nothing. A remote URL does not write. That pull request did not edit `server.ts`. Daemon CI and Xcode CI on that pull request are green. An agent MUST NOT rebuild this slice. Notes stay on the machine. Nothing from the note is stored in Supabase.

#### Scenario: The note-update tip still matches

- **WHEN** an agent re-checks pull request 174 and the tip is `426d66d7ae016a67b66b809a7cb4a10aaa300460`
- **THEN** the agent leaves that pull request as the in-place replace
- **AND** this change gains no second replace path and no second `/knowledge` route

#### Scenario: The note-update tip has moved

- **WHEN** the tip of pull request 174 differs from `426d66d7ae016a67b66b809a7cb4a10aaa300460`
- **THEN** the agent reads the new tip before any conclusion about the replace
- **AND** the agent still does not rebuild the slice

### Requirement: The replaced-note draft is already proven

Pull request 176 (`cursor/updated-note-draft-e469`, tip `ff4d633cf15c69776a314c79a4c243d39bf5cd31`, verified with `gh` on 2026-09-22) SHALL remain the replaced-note draft. After the in-place replace, the agent-note path drafts the new body. The held file is mode 600 and is not executed. A missing id does not call the model. An unconfirmed command stays unrun. Daemon CI and Xcode CI on that pull request are green. `sh scripts/check-updated-note-draft.sh` passed on `127.0.0.1:8898`. An agent MUST NOT rebuild this slice. Notes stay on the machine. Nothing from the note is stored in Supabase.

#### Scenario: The replaced-note draft tip still matches

- **WHEN** an agent re-checks pull request 176 and the tip is `ff4d633cf15c69776a314c79a4c243d39bf5cd31`
- **THEN** the agent leaves that pull request as the replaced-note draft
- **AND** this change gains no second draft check

#### Scenario: An agent starts another replaced-note check

- **WHEN** an agent is about to add another check that replaces a note and then drafts it
- **THEN** the agent uses `sh scripts/check-updated-note-draft.sh` on pull request 176
- **AND** the agent does not rebuild that slice

### Requirement: The replaced-note hold is already proven

Pull request 182 (`cursor/updated-note-hold-e469`, tip `56d8ae73883ac3276e7be01f16a949a016bb1253`, verified with `gh` on 2026-09-22) SHALL remain the replaced-note hold. A replaced note that asks to send a pairing code or copy hosts.json stays on hold and the model is not called. "summarize this paper" still drafts the new body. Daemon CI and Xcode CI on that pull request are green. There is no live gateway call. An agent MUST NOT rebuild this slice. Notes stay on the machine. Nothing from the note is stored in Supabase.

#### Scenario: The hold tip still matches

- **WHEN** an agent re-checks pull request 182 and the tip is `56d8ae73883ac3276e7be01f16a949a016bb1253`
- **THEN** the agent leaves that pull request as the replaced-note hold
- **AND** this change gains no second hold path and no live gateway call

#### Scenario: An agent starts another pairing-code hold

- **WHEN** an agent is about to add another check that holds a replaced pairing-code or hosts.json body
- **THEN** the agent uses `sh scripts/check-updated-note-hold.sh` on pull request 182
- **AND** the agent does not rebuild that slice

### Requirement: The spoken note replace is already proven

Pull request 183 (`cursor/spoken-note-replace-e469`, tip `52ce62929a7c7e3c660943767311ac3c32d36ca8`, verified with `gh` on 2026-09-22) SHALL remain the spoken note replace. `POST /knowledge/:id` accepts `{ audio }`. A local `MESH_STT` transcript replaces that note body. The title stays. The list stays `{ id, title }`. A missing id creates nothing. A remote URL does not write. An empty transcript keeps the old body. `server.ts` still calls `handleKnowledge` once. `sh scripts/check-spoken-note-replace.sh` passed on `127.0.0.1:8898`. Daemon CI on that pull request is green. The first check showed apps (Xcode) still running. A later check of the same run reported apps (Xcode) pass. This handoff records that pass. It does not treat the job as green before that later check. This does not prove a microphone. An agent MUST NOT rebuild this slice and MUST NOT add a second `/knowledge` route.

#### Scenario: The spoken-replace tip still matches

- **WHEN** an agent re-checks pull request 183 and the tip is `52ce62929a7c7e3c660943767311ac3c32d36ca8`
- **THEN** the agent leaves that pull request as the spoken note replace
- **AND** this change gains no second speech-in path and no second `/knowledge` route

#### Scenario: An agent treats the local transcript as a microphone

- **WHEN** an agent is about to claim that pull request 183 proved a microphone
- **THEN** the agent records the local `MESH_STT` transcript and the spare-daemon check on `127.0.0.1:8898`
- **AND** the agent says that this does not prove a microphone

### Requirement: The spoken-note draft is already proven

Pull request 187 (`cursor/spoken-note-draft-e469`, tip `0baf37761f4dc6f42af017fb52513de3fb927e39`, verified with `gh` on 2026-09-22) SHALL remain the spoken-note draft. That pull request adds only `scripts/check-spoken-note-draft.sh`. A local `MESH_STT` transcript replaces one note and the agent-note path drafts that new body to `held-note.txt`. That file SHALL be mode 600 and SHALL NOT be executed. A pairing-code transcript and a hosts.json transcript SHALL stay on hold, and the loopback model MUST NOT be called for either. The body "summarize this paper" SHALL draft the new body. A missing id MUST NOT call the model. A remote audio path MUST NOT write. `sh scripts/check-spoken-note-draft.sh` passed on `127.0.0.1:8898` with the gateway key unset. Daemon CI and Xcode CI on that pull request are both green on `0baf377`. This does not prove a microphone or a speaker. An agent MUST NOT rebuild this check and MUST NOT add a second `/knowledge` route. Pull request 174 stays the in-place note replace at `426d66d`. Pull request 176 stays the replaced-note draft at `ff4d633`. Pull request 182 stays the replaced-note hold at `56d8ae7`. Pull request 183 stays the spoken note replace at `52ce629`.

#### Scenario: The spoken-note draft tip still matches

- **WHEN** an agent re-checks pull request 187 and the tip is `0baf37761f4dc6f42af017fb52513de3fb927e39`
- **THEN** the agent leaves that pull request as the spoken-note draft
- **AND** this change gains no second draft check and no second `/knowledge` route

#### Scenario: A spoken transcript is drafted to held-note.txt

- **WHEN** a local `MESH_STT` transcript replaces one note and the agent-note path drafts that id
- **THEN** the draft file is `held-note.txt`
- **AND** that file is mode 600 and is not executed

#### Scenario: A pairing-code or hosts.json transcript stays on hold

- **WHEN** the replacement transcript asks to send a pairing code or to copy hosts.json
- **THEN** that transcript stays on hold
- **AND** the loopback model is not called

#### Scenario: An agent treats the spoken-note draft as a microphone or a speaker

- **WHEN** an agent is about to claim that pull request 187 proved a microphone or a speaker
- **THEN** the agent records the local `MESH_STT` transcript, the spare-daemon check on `127.0.0.1:8898` with the gateway key unset, and that daemon CI and Xcode CI are both green on `0baf377`
- **AND** the agent says that this does not prove a microphone or a speaker

### Requirement: The spoken replace speak is already proven

Pull request 189 (`cursor/spoken-replace-speak-e469`, tip `611f32131b3609580fb888916a263920b4452dc3`, verified with `gh` on 2026-09-22) SHALL remain the speak of a replaced note. That pull request speaks a replaced note with a local TTS binary. `POST /knowledge/:id` SHALL accept `{ audio, speak }`. When `speak` is true, the title plus the new transcript SHALL be handed to a local `MESH_TTS` binary. `spoken` SHALL be true only when that binary is a local file and the process exits 0. When `speak` is false, or the TTS binary is missing, the transcript SHALL be stored and `spoken` SHALL stay false. A remote URL, a scheme, or a protocol-relative path for the audio or for `MESH_TTS` MUST return before `MESH_STT` and before any write. An empty transcript SHALL keep the old body and MUST NOT speak. A missing id SHALL create nothing. The title SHALL stay. The list SHALL stay `{ id, title }`. `sh scripts/check-spoken-replace-speak.sh` passed on `127.0.0.1:8898`. `server.ts` was not edited. On that tip, `server.ts` still calls `handleKnowledge` once. Daemon CI and Xcode CI are both green on `611f321` (check run `35714316679`). This does not prove a microphone or a speaker. An agent MUST NOT rebuild this speak path, MUST NOT add a second `/knowledge` route, and MUST NOT call the Vercel AI Gateway.

#### Scenario: The spoken replace speak tip still matches

- **WHEN** an agent re-checks pull request 189 and the tip is `611f32131b3609580fb888916a263920b4452dc3`
- **THEN** the agent leaves that pull request as the spoken replace speak
- **AND** this change gains no second TTS path and no second `/knowledge` route

#### Scenario: A local TTS binary speaks the replaced note

- **WHEN** `speak` is true and `MESH_TTS` names a local file that exits 0
- **THEN** that binary receives the title plus the new transcript
- **AND** the response reports spoken as true

#### Scenario: Speak is false or the TTS binary is missing

- **WHEN** `speak` is false, or `MESH_TTS` does not name a local file
- **THEN** the new transcript is stored
- **AND** spoken stays false

#### Scenario: A remote TTS path does not write

- **WHEN** `MESH_TTS` is a remote URL, a scheme, or a protocol-relative path
- **THEN** the daemon returns before `MESH_STT` and before any write
- **AND** the existing note body stays as it was

#### Scenario: An agent treats the spoken replace speak as a microphone or a speaker

- **WHEN** an agent is about to claim that pull request 189 proved a microphone or a speaker
- **THEN** the agent records the local TTS exit code, the spare-daemon check on `127.0.0.1:8898`, and that daemon CI and Xcode CI are both green on `611f321` (check run `35714316679`)
- **AND** the agent says that this does not prove a microphone or a speaker
