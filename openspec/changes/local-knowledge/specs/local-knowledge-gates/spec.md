## Purpose

Gates that keep this change to handoff specs, name the finished draft tips, and stop a later agent from rebuilding speech, notes, holds, spoken replaces, the spoken-note draft, the spoken replace speak, the spoken replace draft, the local note search, the query-note draft, the local PDF note, or the PDF note draft.

## ADDED Requirements

### Requirement: Finished drafts are not new work

An agent MUST treat local PDF notes, spoken-out via a local `MESH_TTS` binary, the note-to-held-file draft, the route-gated draft, spoken-in via a local `MESH_STT` binary, the in-place note replace, the replaced-note draft, the replaced-note hold, the spoken note replace, the spoken-note draft, the spoken replace speak, the spoken replace draft, the local note search, the query-note draft, the local PDF note, and the PDF note draft as already drafted. Pull request 139 is the local PDF notes (tip `9d2827b` on `cursor/local-knowledge-e469` when verified). Pull request 145 is spoken-out (tip `ea86b77` on `cursor/spoken-note-e469`). Pull request 154 is the note to a held file (tip `cba3ac7` on `cursor/note-to-app-e469`). Pull request 160 is the route-gated draft (tip `4c8a73a` on `cursor/note-route-draft-e469`); Jev chooses a route and does not write the reply, and there is no live gateway call in that draft. Pull request 162 is spoken-in (tip `4e14cab` on `cursor/spoken-note-in-e469`); a remote URL does not run, and a second speech-in path MUST NOT be started. Pull request 174 is the in-place note replace (tip `426d66d7ae016a67b66b809a7cb4a10aaa300460` on `cursor/knowledge-note-update-e469`). Pull request 176 is the replaced-note draft (tip `ff4d633cf15c69776a314c79a4c243d39bf5cd31` on `cursor/updated-note-draft-e469`). Pull request 182 is the replaced-note hold (tip `56d8ae73883ac3276e7be01f16a949a016bb1253` on `cursor/updated-note-hold-e469`). Pull request 183 is the spoken note replace (tip `52ce62929a7c7e3c660943767311ac3c32d36ca8` on `cursor/spoken-note-replace-e469`). `server.ts` still calls `handleKnowledge` once on that tip. Pull request 187 is the spoken-note draft (tip `0baf37761f4dc6f42af017fb52513de3fb927e39` on `cursor/spoken-note-draft-e469`). It adds only `scripts/check-spoken-note-draft.sh`. Daemon CI and Xcode CI are both green on that tip. Pull request 189 is the spoken replace speak (tip `611f32131b3609580fb888916a263920b4452dc3` on `cursor/spoken-replace-speak-e469`). It speaks a replaced note with a local TTS binary. Daemon CI and Xcode CI are both green on that tip (check run `35714316679`). Pull request 192 (tip `6faf3f30d32e7d866853f3090e552b3e465ec571`) already named pull request 189. Pull request 193 is the spoken replace draft (tip `37d417aa7b4f1ca8833136bb029f5b64aae611e0` on `cursor/spoken-replace-draft-e469`). It adds only `scripts/check-spoken-replace-draft.sh`. Daemon CI is green on that tip. Pull request 194 (tip `cfe2b179f78938764e3b5d6949d81981b34c50ef`) already named pull request 193. Pull request 195 is the local note search (tip `1238daabce256e6d46c1fd7dd24680cf810d34f6` on `cursor/local-note-search-e469`, base `cursor/spoken-replace-draft-e469`). `GET /knowledge?q=` matches the title or the body, case-insensitive, and returns only `{ id, title }`. A missing or empty `q` returns every note as `{ id, title }`. A remote URL, a scheme, a protocol-relative value, or any string containing `://` is 400 and is not opened. A pairing-code match and a hosts.json match do not return those bodies. `POST /agent-note` still drafts only the matching paper note to one relative file, mode 600, not executed. A command without confirm does not run. `server.ts` was not edited. `handleKnowledge` is still one call. Daemon CI and Xcode CI are both green on `1238daa` (check run `35736830546`). Pull request 197 is the query-note draft (tip `e11483d4f823ed5a647a59d647566236c8d381ab` on `cursor/query-note-draft-e469`, base `cursor/local-note-search-e469`). `POST /agent-note` accepts a local `q` when `id` is absent and selects with `listNotes`. One match drafts one relative file, mode 600, not executed. Zero matches is 404. Several matches is 409. A remote or empty `q` is 400. None of those call the model. The hold matches `textMovesSecret` and does not import `route.ts` or `filter.ts`. `id` without `q` still drafts. `server.ts` was not edited. Daemon CI and Xcode CI are both green on `e11483d` (check run `35739420177`). Daemon CI and Xcode CI are both green on handoff tip `1e78b081f2c64b038008054bedad1fd3a037ec6b` (check run `35740060386`). Daemon CI and Xcode CI are both green on handoff tip `c140ce7bf73c7f979a28d55d9a4784cc723e0027` (check run `35741550431`). Daemon CI and Xcode CI are both green on handoff tip `978bdbe17099174c5ff5f4cb5b401fa7f6555f6c` (check run `35743157250`). Daemon CI and Xcode CI are both green on handoff tip `dcfa77f5894058d1b815a0400c7396b17e356f87` (check run `35744449505`). Pull request 198 is the local PDF note (tip `42211d0ed6531d335fb099ab203a9dc473dacf8c` on `cursor/local-pdf-note-e469`, base `cursor/query-note-draft-e469`). `POST /knowledge` accepts `{ pdf, title? }`. `MESH_PDF` must be a local executable. Its stdout is the note body. A remote value, a value containing `://`, a missing file, a non-executable, empty stdout, or a nonzero exit writes nothing. The list stays `{ id, title }`. `server.ts` was not edited. The coordinator re-ran `sh scripts/check-local-pdf-note.sh` and `sh scripts/check-local-note-search.sh` on `127.0.0.1:8898` at `42211d0`. Both exited 0. The proof is a stub executable. A `path` that is a real PDF still uses the in-daemon `extractPdf` scrape. Do not rebuild either path. Daemon CI and Xcode CI are both green on `42211d0` (check run `35742140469`). Pull request 199 is the PDF note draft (tip `bd04cc0fe9b56933fd5a23c3b64d6cb654075c2e` on `cursor/pdf-note-draft-e469`, base `cursor/local-pdf-note-e469`). It adds only `scripts/check-pdf-note-draft.sh`. A stub `MESH_PDF` sentence that includes "summarize this paper" becomes one note. A query with no id drafts it to one relative file, mode 600, not executed. A pairing-code note and a hosts.json note stay on the existing hold and the model is not called. A pdf value containing `://` and a remote `MESH_PDF` write nothing. `server.ts` was not edited. The coordinator re-ran `sh scripts/check-pdf-note-draft.sh` on `127.0.0.1:8898` at `bd04cc0` and it exited 0. Daemon CI and Xcode CI are both green on `bd04cc0` (check run `35743446950`). Neither pull request 187, pull request 189, pull request 193, pull request 195, pull request 197, pull request 198, nor pull request 199 proves a microphone or a speaker. Pull request 198 and pull request 199 also do not prove that a paper was read. A second `/knowledge` route MUST NOT be added.

The agent MUST re-check each pull request tip with `gh` before editing any of those files, and MUST NOT open a second implementation from this change.

#### Scenario: The named tip is still the draft

- **WHEN** an agent re-checks pull request 139, 145, 154, 160, 162, 174, 176, 182, 183, 187, 189, 193, 195, 197, 198, or 199 and the tip still matches the design
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

- **WHEN** an agent begins to add a knowledge module, an in-place note replace, a replaced-note draft, a replaced-note hold, a spoken note replace, a spoken-note draft, a spoken replace speak, a spoken replace draft, a local note search, a query-note draft, a local PDF note, a PDF note draft, a TTS path, an STT path, a held-file check, a route-gated draft, or a daemon route while executing this change
- **THEN** the agent stops that edit
- **AND** the finished slice stays on its existing pull request: notes on 139, spoken-out on 145, held file on 154, route-gated draft on 160, spoken-in on 162, in-place replace on 174, replaced-note draft on 176, replaced-note hold on 182, spoken note replace on 183, spoken-note draft on 187, spoken replace speak on 189, spoken replace draft on 193, local note search on 195, query-note draft on 197, local PDF note on 198, PDF note draft on 199

### Requirement: server.ts registration is a later, single edit

This pull request MUST NOT edit `install/payload/meshd/server.ts`. On `origin/main`, `/knowledge` is unregistered. This line registers `handleKnowledge` once. A later agent MUST NOT add a second `/knowledge` route. Pull request 174 and pull request 176 did not edit `server.ts`. Pull request 182 and pull request 183 did not edit `server.ts`. On the spoken-replace tip, `server.ts` still calls `handleKnowledge` once. Pull request 187 did not edit `server.ts`. It adds only `scripts/check-spoken-note-draft.sh`. Pull request 189 did not edit `server.ts`. On that tip, `server.ts` still calls `handleKnowledge` once. Pull request 193 did not edit `server.ts`. It adds only `scripts/check-spoken-replace-draft.sh`. Pull request 195 did not edit `server.ts`. On that tip, `handleKnowledge` is still one call. The files are `install/payload/meshd/knowledge.ts` and `scripts/check-local-note-search.sh`. Pull request 197 did not edit `server.ts`. The files are `install/payload/meshd/agent-note.ts` and `scripts/check-query-note-draft.sh`. Pull request 198 did not edit `server.ts`. The files are `install/payload/meshd/knowledge.ts` and `scripts/check-local-pdf-note.sh`. Pull request 199 did not edit `server.ts`. It adds only `scripts/check-pdf-note-draft.sh`.

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

Pull request 189 (`cursor/spoken-replace-speak-e469`, tip `611f32131b3609580fb888916a263920b4452dc3`, verified with `gh` on 2026-09-22) SHALL remain the speak of a replaced note. That pull request speaks a replaced note with a local TTS binary. `POST /knowledge/:id` SHALL accept `{ audio, speak }`. When `speak` is true, the title plus the new transcript SHALL be handed to a local `MESH_TTS` binary. `spoken` SHALL be true only when that binary is a local file and the process exits 0. When `speak` is false, or the TTS binary is missing, the transcript SHALL be stored and `spoken` SHALL stay false. A remote URL, a scheme, or a protocol-relative path for the audio or for `MESH_TTS` MUST return before `MESH_STT` and before any write. An empty transcript SHALL keep the old body and MUST NOT speak. A missing id SHALL create nothing. The title SHALL stay. The list SHALL stay `{ id, title }`. `sh scripts/check-spoken-replace-speak.sh` passed on `127.0.0.1:8898`. `server.ts` was not edited. On that tip, `server.ts` still calls `handleKnowledge` once. Daemon CI and Xcode CI are both green on `611f321` (check run `35714316679`). This does not prove a microphone or a speaker. An agent MUST NOT rebuild this speak path, MUST NOT add a second `/knowledge` route, and MUST NOT call the Vercel AI Gateway. Pull request 192 (tip `6faf3f30d32e7d866853f3090e552b3e465ec571`) already named this pull request.

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

### Requirement: The spoken replace draft is already proven

Pull request 193 (`cursor/spoken-replace-draft-e469`, tip `37d417aa7b4f1ca8833136bb029f5b64aae611e0`, verified with `gh` on 2026-09-22) SHALL remain the spoken replace draft. That pull request adds only `scripts/check-spoken-replace-draft.sh`. `speak: true` with local `MESH_STT` and local `MESH_TTS` SHALL return `spoken` true and SHALL draft that new transcript to a held file. That file SHALL be mode 600 and SHALL NOT be executed. A pairing-code transcript and a hosts.json transcript SHALL stay on hold. The body "summarize this paper" SHALL still draft. A missing id and a remote audio or TTS path MUST NOT write and MUST NOT call the model. There SHALL be no `liveGatewayCall`. `server.ts` was not edited. On that tip, `server.ts` still calls `handleKnowledge` once. Daemon CI is green on `37d417aa`. This does not prove a microphone or a speaker. An agent MUST NOT rebuild this check, MUST NOT add a second `/knowledge` route, and MUST NOT call the Vercel AI Gateway. Pull request 174 stays the in-place note replace at `426d66d`. Pull request 176 stays the replaced-note draft at `ff4d633`. Pull request 182 stays the replaced-note hold at `56d8ae7`. Pull request 183 stays the spoken note replace at `52ce629`. Pull request 187 stays the spoken-note draft at `0baf377`. Pull request 189 stays the spoken replace speak at `611f321`. Pull request 192 (tip `6faf3f3`) already named pull request 189. Pull request 194 (tip `cfe2b17`) already named pull request 193.

#### Scenario: The spoken replace draft tip still matches

- **WHEN** an agent re-checks pull request 193 and the tip is `37d417aa7b4f1ca8833136bb029f5b64aae611e0`
- **THEN** the agent leaves that pull request as the spoken replace draft
- **AND** this change gains no second draft check and no second `/knowledge` route

#### Scenario: Speak true drafts the new transcript to a held file

- **WHEN** `speak` is true, local `MESH_STT` prints a transcript, and local `MESH_TTS` exits 0
- **THEN** the response reports spoken as true
- **AND** the agent-note path drafts that new transcript to a held file that is mode 600 and is not executed

#### Scenario: A pairing-code or hosts.json transcript stays on hold

- **WHEN** the spoken replacement transcript asks to send a pairing code or to copy hosts.json
- **THEN** that transcript stays on hold
- **AND** the model is not called

#### Scenario: A paper summary still drafts

- **WHEN** the spoken replacement transcript is "summarize this paper" and a client asks the agent-note path to draft that id
- **THEN** the draft is from that new transcript
- **AND** the held file is not executed

#### Scenario: A missing id or remote audio or TTS does not write

- **WHEN** the id is missing, or the audio or `MESH_TTS` path is remote
- **THEN** the daemon does not write a note
- **AND** the model is not called

#### Scenario: There is no liveGatewayCall

- **WHEN** `sh scripts/check-spoken-replace-draft.sh` runs
- **THEN** the check, the knowledge path, and the draft path contain no `liveGatewayCall`
- **AND** no request is sent to the AI Gateway

#### Scenario: An agent treats the spoken replace draft as a microphone or a speaker

- **WHEN** an agent is about to claim that pull request 193 proved a microphone or a speaker
- **THEN** the agent records the local STT transcript, the local TTS exit code, and that daemon CI is green on `37d417aa`
- **AND** the agent says that this does not prove a microphone or a speaker

### Requirement: The local note search is already proven

Pull request 195 (`cursor/local-note-search-e469`, tip `1238daabce256e6d46c1fd7dd24680cf810d34f6`, base `cursor/spoken-replace-draft-e469`, verified with `gh` on 2026-09-22) SHALL remain the local note search. `GET /knowledge?q=` SHALL match the title or the body, without case, and SHALL return only `{ id, title }` for each note. A missing or empty `q` SHALL return every note as `{ id, title }`. A remote URL, a scheme, a protocol-relative value, or any string containing `://` MUST be answered with 400 and MUST NOT be opened. A pairing-code match and a hosts.json match MUST NOT return those bodies. `POST /agent-note` SHALL still draft only the matching paper note to one relative file. That file SHALL be mode 600 and SHALL NOT be executed. A command without confirm MUST NOT run. `server.ts` was not edited. On that tip, `handleKnowledge` is still one call. The coordinator re-ran `sh scripts/check-local-note-search.sh` on `127.0.0.1:8898` at `1238daa` and it exited 0. The gateway key was unset. Daemon CI and Xcode CI are both green on `1238daa` (check run `35736830546`). This does not prove a microphone or a speaker. An agent MUST NOT rebuild this search, MUST NOT add a second `/knowledge` route, and MUST NOT call the Vercel AI Gateway. On `origin/main`, `/knowledge` is unregistered. This line registers `handleKnowledge` once. Pull request 174 stays the in-place note replace at `426d66d`. Pull request 176 stays the replaced-note draft at `ff4d633`. Pull request 182 stays the replaced-note hold at `56d8ae7`. Pull request 183 stays the spoken note replace at `52ce629`. Pull request 187 stays the spoken-note draft at `0baf377`. Pull request 189 stays the spoken replace speak at `611f321`. Pull request 193 stays the spoken replace draft at `37d417aa`. Pull request 194 (tip `cfe2b17`) already named pull request 193.

#### Scenario: The local note search tip still matches

- **WHEN** an agent re-checks pull request 195 and the tip is `1238daabce256e6d46c1fd7dd24680cf810d34f6`
- **THEN** the agent leaves that pull request as the local note search
- **AND** this change gains no second search and no second `/knowledge` route

#### Scenario: A query matches the title or the body

- **WHEN** `q` appears in a note title or in a note body, in any case
- **THEN** the matching notes are returned
- **AND** each note is only `{ id, title }`

#### Scenario: A missing or empty query lists every note

- **WHEN** `q` is missing or empty
- **THEN** every note is returned as `{ id, title }`

#### Scenario: A remote query is refused

- **WHEN** `q` is a remote URL, a scheme, a protocol-relative value, or any string containing `://`
- **THEN** the daemon answers 400
- **AND** that value is not opened

#### Scenario: A pairing-code or hosts.json match does not return that body

- **WHEN** `q` matches a pairing-code note or a hosts.json note
- **THEN** the response includes that note as `{ id, title }`
- **AND** that body is not in the response

#### Scenario: The agent-note path drafts only the matching paper note

- **WHEN** a client posts `/agent-note` after that search
- **THEN** only the matching paper note is drafted to one relative file
- **AND** that file is mode 600 and is not executed
- **AND** a command without confirm does not run

#### Scenario: An agent treats the local note search as a microphone or a speaker

- **WHEN** an agent is about to claim that pull request 195 proved a microphone or a speaker
- **THEN** the agent records the spare-daemon check on `127.0.0.1:8898` at `1238daa` (exit 0, gateway key unset) and that daemon CI and Xcode CI are both green on `1238daa` (check run `35736830546`)
- **AND** the agent says that this does not prove a microphone or a speaker

### Requirement: The query-note draft is already proven

Pull request 197 (`cursor/query-note-draft-e469`, tip `e11483d4f823ed5a647a59d647566236c8d381ab`, base `cursor/local-note-search-e469`, verified with `gh` on 2026-09-22) SHALL remain the query-note draft. When `id` is absent, `POST /agent-note` SHALL accept a local `q` and SHALL select with `listNotes`. One match SHALL draft one relative file. That file SHALL be mode 600 and SHALL NOT be executed. Zero matches MUST answer 404. Several matches MUST answer 409. A remote or empty `q` MUST answer 400. Those results MUST NOT call the model. The hold SHALL match `textMovesSecret` for a pairing code, hosts.json, a mesh token, `.mesh/token`, and the upload/send sentence, and MUST NOT import `route.ts` or `filter.ts`. `id` without `q` SHALL still draft. `server.ts` was not edited. The coordinator re-ran `bun x tsc --noEmit -p install/payload/meshd/tsconfig.json` and `sh scripts/check-query-note-draft.sh` on `127.0.0.1:8898` at `e11483d`. Both exited 0. The gateway key was unset. Daemon CI and Xcode CI are both green on `e11483d` (check run `35739420177`). Daemon CI and Xcode CI are both green on handoff tip `1e78b081f2c64b038008054bedad1fd3a037ec6b` (check run `35740060386`). Daemon CI and Xcode CI are both green on handoff tip `c140ce7bf73c7f979a28d55d9a4784cc723e0027` (check run `35741550431`). Daemon CI and Xcode CI are both green on handoff tip `978bdbe17099174c5ff5f4cb5b401fa7f6555f6c` (check run `35743157250`). Daemon CI and Xcode CI are both green on handoff tip `dcfa77f5894058d1b815a0400c7396b17e356f87` (check run `35744449505`). An agent MUST NOT rebuild this draft, MUST NOT add a second `/knowledge` route, and MUST NOT call the Vercel AI Gateway. This does not prove a microphone or a speaker. Pull request 195 stays the local note search at `1238daa`, with daemon CI and Xcode CI both green (check run `35736830546`). Pull request 174 stays `426d66d`. Pull request 176 stays `ff4d633`. Pull request 182 stays `56d8ae7`. Pull request 183 stays `52ce629`. Pull request 187 stays `0baf377`. Pull request 189 stays `611f321`. Pull request 193 stays `37d417aa`.

#### Scenario: The query-note draft tip still matches

- **WHEN** an agent re-checks pull request 197 and the tip is `e11483d4f823ed5a647a59d647566236c8d381ab`
- **THEN** the agent leaves that pull request as the query-note draft
- **AND** this change gains no second query draft and no second `/knowledge` route

#### Scenario: One match drafts one relative file

- **WHEN** `id` is absent and `q` matches exactly one note
- **THEN** the draft is one relative file
- **AND** that file is mode 600 and is not executed

#### Scenario: Zero or several matches do not call the model

- **WHEN** `q` matches no note, or more than one note
- **THEN** the daemon answers 404 or 409
- **AND** the model is not called

#### Scenario: A remote or empty query is refused

- **WHEN** `q` is remote or empty
- **THEN** the daemon answers 400
- **AND** the model is not called

#### Scenario: The hold matches textMovesSecret and does not import the route modules

- **WHEN** the selected note names a pairing code, hosts.json, a mesh token, `.mesh/token`, or the upload/send sentence
- **THEN** the note stays on hold
- **AND** the draft does not import `route.ts` or `filter.ts`

#### Scenario: An id without a query still drafts

- **WHEN** a client posts `/agent-note` with `id` and without `q`
- **THEN** that id is drafted

#### Scenario: An agent treats the query draft as a microphone or a speaker

- **WHEN** an agent is about to claim that pull request 197 proved a microphone or a speaker
- **THEN** the agent records that daemon CI and Xcode CI are both green on `e11483d` (check run `35739420177`) and on handoff tips `1e78b08` (check run `35740060386`) and `c140ce7` (check run `35741550431`), and that daemon CI and Xcode CI are both green on handoff tips `978bdbe` (check run `35743157250`) and `dcfa77f` (check run `35744449505`)
- **AND** the agent says that this does not prove a microphone or a speaker

### Requirement: The local PDF note is already proven

Pull request 198 (`cursor/local-pdf-note-e469`, tip `42211d0ed6531d335fb099ab203a9dc473dacf8c`, base `cursor/query-note-draft-e469`, verified with `gh` on 2026-09-22) SHALL remain the local PDF note. `POST /knowledge` SHALL accept `{ pdf, title? }`. `MESH_PDF` MUST be a local executable. Its stdout SHALL be the note body. A remote value, a value containing `://`, a missing file, a non-executable, empty stdout, or a nonzero exit MUST write nothing. The list SHALL stay `{ id, title }`. `server.ts` was not edited. The coordinator re-ran `sh scripts/check-local-pdf-note.sh` and `sh scripts/check-local-note-search.sh` on `127.0.0.1:8898` at `42211d0`. Both exited 0. The proof is a stub executable. A `path` that is a real PDF SHALL still use the in-daemon `extractPdf` scrape. An agent MUST NOT rebuild either path, MUST NOT add a second `/knowledge` route, and MUST NOT call the Vercel AI Gateway. Daemon CI and Xcode CI are both green on `42211d0` (check run `35742140469`). This does not prove a microphone, a speaker, or that a paper was read. Pull request 197 stays the query-note draft at `e11483d`, with daemon CI and Xcode CI both green (check run `35739420177`). Pull request 195 stays the local note search at `1238daa`, with daemon CI and Xcode CI both green (check run `35736830546`).

#### Scenario: The local PDF note tip still matches

- **WHEN** an agent re-checks pull request 198 and the tip is `42211d0ed6531d335fb099ab203a9dc473dacf8c`
- **THEN** the agent leaves that pull request as the local PDF note
- **AND** this change gains no second PDF note path and no second `/knowledge` route

#### Scenario: Stdout from a local executable is the note body

- **WHEN** a client posts `{ pdf, title? }` and `MESH_PDF` is a local executable
- **THEN** stdout is the note body
- **AND** the list stays `{ id, title }`

#### Scenario: A refused PDF writes nothing

- **WHEN** `pdf` is remote, contains `://`, names a missing file, `MESH_PDF` is not executable, stdout is empty, or the process exits nonzero
- **THEN** the daemon writes nothing

#### Scenario: A path that is a real PDF still uses extractPdf

- **WHEN** a client posts a `path` that is a real PDF
- **THEN** the in-daemon `extractPdf` scrape writes the note
- **AND** that path does not require `MESH_PDF`

#### Scenario: Green CI on the PDF note is not a paper that was read

- **WHEN** an agent is about to treat both green jobs on `42211d0` as a microphone, a speaker, or proof that a paper was read
- **THEN** the agent records that daemon CI and Xcode CI are both green on `42211d0` (check run `35742140469`)
- **AND** the agent says that this does not prove a microphone, a speaker, or that a paper was read

#### Scenario: An agent treats the stub check as a paper that was read

- **WHEN** an agent is about to claim that pull request 198 proved a microphone, a speaker, or that a paper was read
- **THEN** the agent records that the proof is a stub executable and that both spare-daemon checks exited 0 on `127.0.0.1:8898` at `42211d0`
- **AND** the agent says that this does not prove a microphone, a speaker, or that a paper was read

### Requirement: The PDF note draft is already proven

Pull request 199 (`cursor/pdf-note-draft-e469`, tip `bd04cc0fe9b56933fd5a23c3b64d6cb654075c2e`, base `cursor/local-pdf-note-e469`, verified with `gh` on 2026-09-22) SHALL remain the PDF note draft. It adds only `scripts/check-pdf-note-draft.sh`. A stub `MESH_PDF` sentence that includes "summarize this paper" SHALL become one note. A query with no id SHALL draft that note to one relative file. That file SHALL be mode 600 and SHALL NOT be executed. A pairing-code note and a hosts.json note SHALL stay on the existing hold and the model MUST NOT be called. A pdf value containing `://` and a remote `MESH_PDF` MUST write nothing. `server.ts` was not edited. The coordinator re-ran `sh scripts/check-pdf-note-draft.sh` on `127.0.0.1:8898` at `bd04cc0` and it exited 0. An agent MUST NOT rebuild this check, MUST NOT add a second `/knowledge` route, and MUST NOT call the Vercel AI Gateway. Daemon CI and Xcode CI are both green on `bd04cc0` (check run `35743446950`). This does not prove a microphone, a speaker, or that a paper was read. Pull request 198 stays the local PDF note at `42211d0`, with daemon CI and Xcode CI both green (check run `35742140469`). Pull request 197 stays the query-note draft at `e11483d`, with daemon CI and Xcode CI both green (check run `35739420177`). Pull request 195 stays the local note search at `1238daa`, with daemon CI and Xcode CI both green (check run `35736830546`). Daemon CI and Xcode CI are both green on handoff tip `978bdbe17099174c5ff5f4cb5b401fa7f6555f6c` (check run `35743157250`). Daemon CI and Xcode CI are both green on handoff tip `dcfa77f5894058d1b815a0400c7396b17e356f87` (check run `35744449505`).

#### Scenario: The PDF note draft tip still matches

- **WHEN** an agent re-checks pull request 199 and the tip is `bd04cc0fe9b56933fd5a23c3b64d6cb654075c2e`
- **THEN** the agent leaves that pull request as the PDF note draft
- **AND** this change gains no second PDF draft and no second `/knowledge` route

#### Scenario: A paper sentence becomes one note and one draft

- **WHEN** a stub `MESH_PDF` sentence includes "summarize this paper" and a query has no id
- **THEN** that sentence becomes one note
- **AND** the draft is one relative file, mode 600, and is not executed

#### Scenario: A pairing-code note and a hosts.json note stay on hold

- **WHEN** the note is a pairing code or names hosts.json
- **THEN** the note stays on the existing hold
- **AND** the model is not called

#### Scenario: A remote PDF value writes nothing

- **WHEN** the pdf value contains `://` or `MESH_PDF` is remote
- **THEN** the daemon writes nothing

#### Scenario: Green CI on the PDF draft is not a paper that was read

- **WHEN** an agent is about to treat both green jobs on `bd04cc0` or on handoff tip `dcfa77f` as a microphone, a speaker, or proof that a paper was read
- **THEN** the agent records that daemon CI and Xcode CI are both green on `bd04cc0` (check run `35743446950`) and on handoff tip `dcfa77f` (check run `35744449505`)
- **AND** the agent says that this does not prove a microphone, a speaker, or that a paper was read

#### Scenario: An agent treats the PDF draft as a paper that was read

- **WHEN** an agent is about to claim that pull request 199 proved a microphone, a speaker, or that a paper was read
- **THEN** the agent records that the spare-daemon check exited 0 on `127.0.0.1:8898` at `bd04cc0`
- **AND** the agent says that this does not prove a microphone, a speaker, or that a paper was read
