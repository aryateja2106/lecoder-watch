## Purpose

Local notes from a PDF or a local speech-in binary stay under `MESHD_STATE`, an existing note's body can be replaced in the same file, a local `MESH_STT` transcript can replace that body, a local `MESH_TTS` binary can speak that replaced note, optional local TTS speaks a note, a held app draft waits for confirm before any further command, a replaced note that asks to send a pairing code or copy hosts.json stays on hold, a spoken replace drafts that new body to `held-note.txt`, a spoken replace with `speak: true` drafts that new transcript to a held file, `GET /knowledge?q=` matches a title or a body and returns only `{ id, title }`, a local `q` on `POST /agent-note` selects one note when `id` is absent, `POST /knowledge` accepts `{ pdf, title? }` whose body is stdout from a local `MESH_PDF` executable, a stub `MESH_PDF` sentence that includes "summarize this paper" becomes one note that a query with no id drafts to one relative file, and `POST /knowledge` accepts `{ pdf, title?, speak? }` where `spoken: true` requires a local `MESH_TTS` that exits 0, `POST /agent-note` accepts an optional local `ask` that the model receives after the note and a blank line, and a stub `MESH_PDF` sentence spoken by a local `MESH_TTS` can then be asked, an allowed ask saves the model reply as one knowledge note, a later local query that matches only that saved reply drafts it to one relative file, and a later ask of that saved reply sends the reply, a blank line, and the ask. A spoken note is a local binary transcript or a local TTS exit code. Notes stay on the machine. Nothing from the note is stored in Supabase. Pull request 187, pull request 189, pull request 193, pull request 195, pull request 197, pull request 198, pull request 199, and pull request 200 do not prove a microphone or a speaker. Pull request 200 does not prove a speaker played audio. Pull request 201 and pull request 202 do not prove a microphone or a speaker. Pull request 202 does not prove a speaker played audio or that a paper was read. Pull request 203 does not prove a speaker or that a paper was read. Pull request 204 does not prove a speaker or that a paper was read. Pull request 205 does not prove a speaker or that a paper was read. Pull request 198 and pull request 199 also do not prove that a paper was read. Pull request 192 (tip `6faf3f3`) already named pull request 189. Pull request 194 (tip `cfe2b17`) already named pull request 193, and a second saved reply can be drafted alone.

## ADDED Requirements

### Requirement: A local PDF becomes one note under MESHD_STATE

The daemon SHALL accept a filesystem path to a PDF on the machine, read that file, and write exactly one note under the daemon state directory. The state directory is `MESHD_STATE` when that variable is set, and `~/.mesh` otherwise. Notes live in a `knowledge` directory inside it. That directory SHALL be mode 700. The note file SHALL be mode 600 and unreadable by other users.

Knowledge bodies, PDF bytes, and note text MUST NOT be sent to Supabase or to any other cloud store.

#### Scenario: Spare daemon ingests a PDF

- **WHEN** a client posts a local PDF path to the knowledge route on a spare daemon with `MESHD_STATE` pointed at a temp directory
- **THEN** a note file exists under that state directory's `knowledge` directory
- **AND** that directory is mode 700
- **AND** the note file is mode 600
- **AND** the note records a title

#### Scenario: The path is not a local file

- **WHEN** the path is an `http` or `https` URL, or names something that is not a PDF file
- **THEN** the daemon rejects the request
- **AND** it does not write a note

### Requirement: A later request can list the title

A second request SHALL list the note's title and id so a later agent can find what was stored. The list returns titles and ids. The PDF bytes and the full note body are not required in the list response.

#### Scenario: Listing after a write

- **WHEN** a note has been written and a client requests the knowledge list
- **THEN** the response includes that note's id and title

### Requirement: Spoken-out uses a local MESH_TTS binary

The daemon MAY hand the note text to a TTS binary the user already has, and only when the request asks for speech and `MESH_TTS` names that local binary. The daemon SHALL NOT download a speech program. The note SHALL still be written when speech is not asked for or the binary is absent. Spoken is reported only when that local process exits 0. A spoken note is that local TTS exit code. An agent MUST NOT claim a speaker was proven.

#### Scenario: Speech was not requested

- **WHEN** a client posts a PDF path without asking for speech
- **THEN** the note is written
- **AND** no TTS process is started

#### Scenario: MESH_TTS names a local binary and speech is requested

- **WHEN** a client asks for speech and `MESH_TTS` names a local binary that exits 0
- **THEN** that binary receives the note text
- **AND** the response reports spoken as true
- **AND** the note remains on disk under `MESHD_STATE`

### Requirement: Spoken-in uses a local MESH_STT binary

The daemon MAY accept a local audio file and run only the local binary named by `MESH_STT`. A remote URL for the binary or for the audio path MUST NOT run. Do not start a second speech-in path beside the finished draft on pull request 162. When the binary is missing, unset, remote, nonzero, or timed out, the daemon SHALL write no note from that request. A spoken note is that local binary transcript. An agent MUST NOT claim a microphone was proven.

#### Scenario: A local transcript becomes the note body

- **WHEN** a client posts a local audio path and `MESH_STT` names a local binary that prints a transcript and exits 0
- **THEN** a note file exists under the state directory's `knowledge` directory
- **AND** the note body is that transcript

#### Scenario: A remote URL does not run

- **WHEN** `MESH_STT` or the audio path is an `http`, `https`, scheme, or protocol-relative URL
- **THEN** the daemon does not start that URL
- **AND** no note is written from that request

### Requirement: A held draft waits for confirm

A note MAY be drafted into one relative file in a session cwd. That draft file SHALL NOT be executed. A further shell command SHALL wait until confirm is true. A missing note SHALL NOT call the model. The model base URL, when recorded, is a hostname class (`local` or `user-subscription`), not a key.

#### Scenario: An unconfirmed command does not run

- **WHEN** a held draft file exists and confirm is false
- **THEN** no further shell command from that draft path runs
- **AND** the draft file remains on disk unexecuted

#### Scenario: A missing note does not call the model

- **WHEN** the requested note id is absent
- **THEN** the model is not called
- **AND** no draft file is created

### Requirement: Jev chooses a route and does not write the reply

Jev SHALL choose a dispatch route. Jev MUST NOT write the assistant reply, the shell command, or the app. A filtered note is posted to a local model stub only when the route is `allow-local-tool`. A secret-moving note, a graphical ask, a wait-for-human result, a high risk, or confidence below 0.6 MUST NOT connect and MUST NOT create the file. A live gateway call is outside this change.

#### Scenario: The route refuses the draft

- **WHEN** `route()` returns anything other than `allow-local-tool`
- **THEN** no local model connection is opened
- **AND** no draft file is created

#### Scenario: The gateway key is unset

- **WHEN** the route-gated draft check runs with the gateway key unset
- **THEN** the check still decides from the local route result
- **AND** no request is sent to the AI Gateway

### Requirement: POST /knowledge/:id replaces that note's body in the same file

When a note already exists, `POST /knowledge/:id` SHALL replace that note's body in the same file under the knowledge directory. The list SHALL stay `{ id, title }` for each note. A missing id SHALL create nothing. A remote URL SHALL NOT write. Notes stay on the machine. Nothing from the note is stored in Supabase. This behavior is pull request 174. An agent MUST NOT add a second replace path, and MUST NOT add a second `/knowledge` route. On `origin/main`, `/knowledge` is unregistered. This line registers `handleKnowledge` once.

#### Scenario: The same file receives the new body

- **WHEN** a client posts local text to `/knowledge/:id` for a note that is already on disk
- **THEN** that note's body is the posted text
- **AND** the write is the same file
- **AND** a list request still returns that note as id and title

#### Scenario: A missing id creates nothing

- **WHEN** the id in `POST /knowledge/:id` is not a note on disk
- **THEN** the daemon creates no note
- **AND** no new file is written under the knowledge directory

#### Scenario: A remote URL does not write

- **WHEN** the posted body, path, audio, or url is an `http`, `https`, scheme, or protocol-relative URL
- **THEN** the daemon does not write a note
- **AND** the existing note body stays as it was

### Requirement: After a replace, the agent-note path drafts the new body

After `POST /knowledge/:id` replaces a note, the agent-note path SHALL draft that new body. The held file SHALL be mode 600 and SHALL NOT be executed. A missing id SHALL NOT call the model. An unconfirmed command SHALL stay unrun. Notes stay on the machine. Nothing from the note is stored in Supabase. This behavior is pull request 176. An agent MUST NOT add a second draft of a replaced note.

#### Scenario: The draft follows the replaced body

- **WHEN** a note's body has been replaced in the same file and a client asks the agent-note path to draft that id
- **THEN** the draft is from the new body
- **AND** the held file is mode 600
- **AND** the held file is not executed

#### Scenario: A missing id does not call the model

- **WHEN** the agent-note path is asked for an id that is not on disk
- **THEN** the model is not called
- **AND** no draft file is created

#### Scenario: An unconfirmed command stays unrun

- **WHEN** the replaced-note draft has written a held file and confirm is not true
- **THEN** the command stays unrun
- **AND** the held file remains on disk unexecuted

### Requirement: A replaced note that asks to send a pairing code or copy hosts.json stays on hold

After a note body has been replaced, a body that asks to send a pairing code or to copy hosts.json SHALL stay on hold. The model MUST NOT be called. A live gateway call MUST NOT be made. The body "summarize this paper" SHALL still be drafted as the new body. This behavior is pull request 182. An agent MUST NOT add a second hold path.

#### Scenario: A pairing-code body stays on hold

- **WHEN** a replaced note asks to send a pairing code
- **THEN** that note stays on hold
- **AND** the model is not called
- **AND** no request is sent to the AI Gateway

#### Scenario: A hosts.json body stays on hold

- **WHEN** a replaced note asks to copy hosts.json
- **THEN** that note stays on hold
- **AND** the model is not called
- **AND** no held file is written from that ask

#### Scenario: A paper summary still drafts the new body

- **WHEN** a replaced note's new body is "summarize this paper" and a client asks the agent-note path to draft that id
- **THEN** the draft is from that new body
- **AND** the held file is not executed

### Requirement: POST /knowledge/:id accepts audio and a local transcript replaces that note body

`POST /knowledge/:id` SHALL accept `{ audio }` for a note that is already on disk. When `MESH_STT` names a local binary that prints a transcript and exits 0, that transcript SHALL replace that note's body. The title SHALL stay. The list SHALL stay `{ id, title }` for each note. A missing id SHALL create nothing. A remote URL SHALL NOT write. An empty transcript SHALL keep the old body. `server.ts` still calls `handleKnowledge` once. An agent MUST NOT add a second `/knowledge` route. This behavior is pull request 183. A spoken note is that local binary transcript. An agent MUST NOT claim a microphone was proven.

#### Scenario: A local transcript replaces the body

- **WHEN** a client posts `{ audio }` to `/knowledge/:id` for a note that is already on disk and `MESH_STT` names a local binary that prints a transcript and exits 0
- **THEN** that note's body is the transcript
- **AND** the title is unchanged
- **AND** a list request still returns that note as id and title

#### Scenario: A missing id creates nothing

- **WHEN** the id in `POST /knowledge/:id` with `{ audio }` is not a note on disk
- **THEN** the daemon creates no note
- **AND** the existing notes stay as they were

#### Scenario: A remote URL does not write

- **WHEN** the audio path is an `http`, `https`, scheme, or protocol-relative URL
- **THEN** the daemon does not write a note
- **AND** the existing note body stays as it was

#### Scenario: An empty transcript keeps the old body

- **WHEN** `MESH_STT` names a local binary that exits 0 and prints no transcript
- **THEN** the existing note body stays as it was
- **AND** the response does not replace that body

#### Scenario: The replace does not prove a microphone

- **WHEN** the new body came from a local `MESH_STT` transcript
- **THEN** the agent records that local binary transcript
- **AND** the agent does not claim a microphone was proven

### Requirement: A spoken replace drafts the new body to held-note.txt

After a local `MESH_STT` transcript replaces one note, the agent-note path SHALL draft that new body to `held-note.txt`. That file SHALL be mode 600 and SHALL NOT be executed. A pairing-code transcript and a hosts.json transcript SHALL stay on hold, and the loopback model MUST NOT be called for either. The body "summarize this paper" SHALL draft the new body. A missing id MUST NOT call the model. A remote audio path MUST NOT write. The check runs with the gateway key unset. This behavior is pull request 187, which adds only `scripts/check-spoken-note-draft.sh`. Daemon CI and Xcode CI are both green on `0baf377`. An agent MUST NOT rebuild that check and MUST NOT add a second `/knowledge` route. A spoken note is that local binary transcript. An agent MUST NOT claim a microphone or a speaker was proven.

#### Scenario: The new transcript is drafted to held-note.txt

- **WHEN** a local `MESH_STT` transcript replaces one note and a client asks the agent-note path to draft that id
- **THEN** the draft file is `held-note.txt`
- **AND** that file is mode 600
- **AND** that file is not executed

#### Scenario: A pairing-code transcript stays on hold

- **WHEN** the replacement transcript asks to send a pairing code
- **THEN** that transcript stays on hold
- **AND** the loopback model is not called

#### Scenario: A hosts.json transcript stays on hold

- **WHEN** the replacement transcript asks to copy hosts.json
- **THEN** that transcript stays on hold
- **AND** the loopback model is not called

#### Scenario: A paper summary drafts the new body

- **WHEN** the replacement transcript is "summarize this paper" and a client asks the agent-note path to draft that id
- **THEN** the draft is from that new body
- **AND** the held file is not executed

#### Scenario: A missing id does not call the model

- **WHEN** the spoken-note draft is asked for an id that is not on disk
- **THEN** the model is not called
- **AND** no draft file is created

#### Scenario: A remote audio path does not write

- **WHEN** the audio path is an `http`, `https`, scheme, or protocol-relative URL
- **THEN** the daemon does not write a note
- **AND** the model is not called

#### Scenario: The spoken-note draft does not prove a microphone or a speaker

- **WHEN** `sh scripts/check-spoken-note-draft.sh` passes on `127.0.0.1:8898` with the gateway key unset
- **THEN** the agent records that local `MESH_STT` transcript, that spare-daemon check, and that daemon CI and Xcode CI are both green on `0baf377`
- **AND** the agent does not claim a microphone or a speaker was proven

### Requirement: A replaced note is spoken with a local MESH_TTS binary

After a local `MESH_STT` transcript replaces one note, `POST /knowledge/:id` SHALL accept `speak`. When `speak` is true, the title plus the new transcript SHALL be handed to a local `MESH_TTS` binary. `spoken` SHALL be true only when that binary is a local file and the process exits 0. When `speak` is false, or the TTS binary is missing, the transcript SHALL be stored and `spoken` SHALL stay false. A remote URL, a scheme, or a protocol-relative path for the audio or for `MESH_TTS` MUST return before `MESH_STT` and before any write. An empty transcript SHALL keep the old body and MUST NOT speak. A missing id SHALL create nothing. The title SHALL stay. The list SHALL stay `{ id, title }`. `server.ts` still calls `handleKnowledge` once. An agent MUST NOT add a second `/knowledge` route and MUST NOT call the Vercel AI Gateway. This behavior is pull request 189. A spoken note is that local TTS exit code. An agent MUST NOT claim a microphone or a speaker was proven.

#### Scenario: A local TTS binary speaks the new transcript

- **WHEN** a client posts `{ audio, speak: true }` to `/knowledge/:id` for a note that is already on disk, `MESH_STT` prints a transcript and exits 0, and `MESH_TTS` names a local file that exits 0
- **THEN** that TTS binary receives the title plus the new transcript
- **AND** the response reports spoken as true
- **AND** the title is unchanged

#### Scenario: Speak is false

- **WHEN** a client posts `{ audio, speak: false }` and `MESH_STT` prints a transcript and exits 0
- **THEN** the note body is that transcript
- **AND** spoken stays false
- **AND** no TTS process is started

#### Scenario: A missing TTS binary stores the transcript

- **WHEN** `speak` is true and `MESH_TTS` does not name a local file
- **THEN** the new transcript is stored
- **AND** spoken stays false

#### Scenario: A remote TTS path does not write

- **WHEN** `speak` is true and `MESH_TTS` is a remote URL, a scheme, or a protocol-relative path
- **THEN** the daemon returns before `MESH_STT` and before any write
- **AND** the existing note body stays as it was

#### Scenario: An empty transcript does not speak

- **WHEN** `MESH_STT` exits 0 and prints no transcript
- **THEN** the existing note body stays as it was
- **AND** no TTS process is started

#### Scenario: The speak does not prove a microphone or a speaker

- **WHEN** `sh scripts/check-spoken-replace-speak.sh` passes on `127.0.0.1:8898`
- **THEN** the agent records that local TTS exit code and that daemon CI and Xcode CI are both green on `611f321` (check run `35714316679`)
- **AND** the agent does not claim a microphone or a speaker was proven

### Requirement: A spoken replace with speak true drafts the new transcript to a held file

After `speak: true` with local `MESH_STT` and local `MESH_TTS` returns `spoken` true, the agent-note path SHALL draft that new transcript to a held file. That file SHALL be mode 600 and SHALL NOT be executed. A pairing-code transcript and a hosts.json transcript SHALL stay on hold. The body "summarize this paper" SHALL still draft. A missing id and a remote audio or TTS path MUST NOT write and MUST NOT call the model. There SHALL be no `liveGatewayCall`. The check runs with the gateway key unset. This behavior is pull request 193, which adds only `scripts/check-spoken-replace-draft.sh`. Daemon CI is green on `37d417aa`. An agent MUST NOT rebuild that check, MUST NOT add a second `/knowledge` route, and MUST NOT call the Vercel AI Gateway. On `origin/main`, `/knowledge` is unregistered. This line registers `handleKnowledge` once. A spoken note is that local binary transcript or that local TTS exit code. An agent MUST NOT claim a microphone or a speaker was proven. Pull request 192 (tip `6faf3f3`) already named pull request 189. Pull request 194 (tip `cfe2b17`) already named pull request 193.

#### Scenario: Speak true drafts the new transcript

- **WHEN** a client posts `{ audio, speak: true }` to `/knowledge/:id`, local `MESH_STT` prints a transcript and exits 0, local `MESH_TTS` exits 0, and a client asks the agent-note path to draft that id
- **THEN** the response reports spoken as true
- **AND** the draft is that new transcript in a held file
- **AND** that file is mode 600 and is not executed

#### Scenario: A pairing-code transcript stays on hold

- **WHEN** the spoken replacement transcript asks to send a pairing code
- **THEN** that transcript stays on hold
- **AND** the model is not called

#### Scenario: A hosts.json transcript stays on hold

- **WHEN** the spoken replacement transcript asks to copy hosts.json
- **THEN** that transcript stays on hold
- **AND** the model is not called

#### Scenario: A paper summary still drafts

- **WHEN** the spoken replacement transcript is "summarize this paper" and a client asks the agent-note path to draft that id
- **THEN** the draft is from that new transcript
- **AND** the held file is not executed

#### Scenario: A missing id does not write or call the model

- **WHEN** the spoken replace draft is asked for an id that is not on disk
- **THEN** the model is not called
- **AND** no draft file is created

#### Scenario: A remote audio or TTS path does not write or call the model

- **WHEN** the audio path or `MESH_TTS` is an `http`, `https`, scheme, or protocol-relative URL
- **THEN** the daemon does not write a note
- **AND** the model is not called

#### Scenario: There is no liveGatewayCall

- **WHEN** `sh scripts/check-spoken-replace-draft.sh` runs
- **THEN** the check and the draft path contain no `liveGatewayCall`
- **AND** no request is sent to the AI Gateway

#### Scenario: The spoken replace draft does not prove a microphone or a speaker

- **WHEN** `sh scripts/check-spoken-replace-draft.sh` passes on `127.0.0.1:8898` with the gateway key unset
- **THEN** the agent records that local STT transcript, that local TTS exit code, and that daemon CI is green on `37d417aa`
- **AND** the agent does not claim a microphone or a speaker was proven

### Requirement: GET /knowledge?q= matches a title or a body and returns only id and title

`GET /knowledge?q=` SHALL match the title or the body, without case, and SHALL return only `{ id, title }` for each note. A missing or empty `q` SHALL return every note as `{ id, title }`. A query with no match SHALL return `{ notes: [] }`. A remote URL, a scheme, a protocol-relative value, or any string containing `://` MUST be answered with 400 and MUST NOT be opened. A pairing-code match and a hosts.json match MUST NOT return those bodies. `POST /agent-note` SHALL still draft only the matching paper note to one relative file. That file SHALL be mode 600 and SHALL NOT be executed. A command without confirm MUST NOT run. `server.ts` was not edited. `handleKnowledge` is still one call. The check runs with the gateway key unset. This behavior is pull request 195. Daemon CI and Xcode CI are both green on `1238daa` (check run `35736830546`). An agent MUST NOT rebuild this search, MUST NOT add a second `/knowledge` route, and MUST NOT call the Vercel AI Gateway. On `origin/main`, `/knowledge` is unregistered. This line registers `handleKnowledge` once. This does not prove a microphone or a speaker. Pull request 194 (tip `cfe2b17`) already named pull request 193.

#### Scenario: A query matches the title or the body

- **WHEN** a client requests `GET /knowledge?q=` with text that appears in a note title or in a note body, in any case
- **THEN** the matching notes are returned
- **AND** each note is only `{ id, title }`

#### Scenario: A missing or empty query lists every note

- **WHEN** a client requests `GET /knowledge` with `q` missing or empty
- **THEN** every note is returned
- **AND** each note is only `{ id, title }`

#### Scenario: No match is an empty list

- **WHEN** a client requests `GET /knowledge?q=` with text that is in no title and no body
- **THEN** the response is `{ notes: [] }`

#### Scenario: A remote query is refused

- **WHEN** `q` is a remote URL, a scheme, a protocol-relative value, or any string containing `://`
- **THEN** the daemon answers 400
- **AND** that value is not opened

#### Scenario: A pairing-code match does not return that body

- **WHEN** `q` matches a note whose body is a pairing code
- **THEN** the response includes that note as `{ id, title }`
- **AND** the pairing-code body is not in the response

#### Scenario: A hosts.json match does not return that body

- **WHEN** `q` matches a note whose body names hosts.json
- **THEN** the response includes that note as `{ id, title }`
- **AND** the hosts.json body is not in the response

#### Scenario: The agent-note path drafts only the matching paper note

- **WHEN** a client posts `/agent-note` for the note that matches the paper and not the pairing code or hosts.json
- **THEN** the draft is one relative file
- **AND** that file is mode 600 and is not executed
- **AND** a command without confirm does not run

#### Scenario: The search does not prove a microphone or a speaker

- **WHEN** `sh scripts/check-local-note-search.sh` passes on `127.0.0.1:8898` at `1238daa` with the gateway key unset
- **THEN** the agent records that spare-daemon check and that daemon CI and Xcode CI are both green on `1238daa` (check run `35736830546`)
- **AND** the agent does not claim a microphone or a speaker was proven

### Requirement: A local query selects one note when id is absent

When `id` is absent, `POST /agent-note` SHALL accept a local `q` and SHALL select with `listNotes`. One match SHALL draft one relative file. That file SHALL be mode 600 and SHALL NOT be executed. Zero matches MUST answer 404. Several matches MUST answer 409. A remote or empty `q` MUST answer 400. Those results MUST NOT call the model. The hold SHALL match `textMovesSecret` for a pairing code, hosts.json, a mesh token, `.mesh/token`, and the upload/send sentence, and MUST NOT import `route.ts` or `filter.ts`. `id` without `q` SHALL still draft. `server.ts` was not edited. This behavior is pull request 197. The typecheck and `sh scripts/check-query-note-draft.sh` on `127.0.0.1:8898` at `e11483d` both exited 0 with the gateway key unset. Daemon CI and Xcode CI are both green on `e11483d` (check run `35739420177`). Daemon CI and Xcode CI are both green on handoff tip `1e78b081f2c64b038008054bedad1fd3a037ec6b` (check run `35740060386`). Daemon CI and Xcode CI are both green on handoff tip `c140ce7bf73c7f979a28d55d9a4784cc723e0027` (check run `35741550431`). Daemon CI and Xcode CI are both green on handoff tip `978bdbe17099174c5ff5f4cb5b401fa7f6555f6c` (check run `35743157250`). Daemon CI and Xcode CI are both green on handoff tip `dcfa77f5894058d1b815a0400c7396b17e356f87` (check run `35744449505`). Daemon CI and Xcode CI are both green on handoff tip `b3e91609e5a8c488dded8cc4d3aeae1e840c1b2e` (check run `35745531307`). Daemon CI and Xcode CI are both green on handoff tip `2aad3fd833efbf725f57c9e3c76fbf470a07d44a` (check run `35746528962`). Daemon CI and Xcode CI are both green on handoff tip `bd904b19dc5dc85752888193ad365c2d3a176c8a` (check run `35747820842`). An agent MUST NOT rebuild this draft, MUST NOT add a second `/knowledge` route, and MUST NOT call the Vercel AI Gateway. This does not prove a microphone or a speaker. Pull request 195 stays the local note search at `1238daa`, with daemon CI and Xcode CI both green (check run `35736830546`).

#### Scenario: One match drafts one relative file

- **WHEN** `id` is absent and `q` matches exactly one note
- **THEN** the agent-note path drafts that note to one relative file
- **AND** that file is mode 600 and is not executed

#### Scenario: Zero matches is 404

- **WHEN** `id` is absent and `q` matches no note
- **THEN** the daemon answers 404
- **AND** the model is not called

#### Scenario: Several matches is 409

- **WHEN** `id` is absent and `q` matches more than one note
- **THEN** the daemon answers 409
- **AND** the model is not called

#### Scenario: A remote or empty query is 400

- **WHEN** `id` is absent and `q` is remote or empty
- **THEN** the daemon answers 400
- **AND** the model is not called

#### Scenario: A secret note is held without importing the route modules

- **WHEN** the selected note asks to move a pairing code, hosts.json, a mesh token, `.mesh/token`, or matches the upload/send sentence
- **THEN** the note stays on hold
- **AND** the draft does not import `route.ts` or `filter.ts`

#### Scenario: An id without a query still drafts

- **WHEN** a client posts `/agent-note` with `id` and without `q`
- **THEN** that id is drafted
- **AND** `listNotes` is not required to choose it

#### Scenario: The query draft does not prove a microphone or a speaker

- **WHEN** `sh scripts/check-query-note-draft.sh` passes on `127.0.0.1:8898` at `e11483d` with the gateway key unset
- **THEN** the agent records that spare-daemon check and that daemon CI and Xcode CI are both green on `e11483d` (check run `35739420177`) and on handoff tips `1e78b08` (check run `35740060386`) and `c140ce7` (check run `35741550431`), and that daemon CI and Xcode CI are both green on handoff tips `978bdbe` (check run `35743157250`) and `dcfa77f` (check run `35744449505`)
- **AND** the agent does not claim a microphone or a speaker was proven

### Requirement: A local PDF executable writes one note

`POST /knowledge` SHALL accept `{ pdf, title? }`. `MESH_PDF` MUST be a local executable. Its stdout SHALL be the note body. A remote value, a value containing `://`, a missing file, a non-executable, empty stdout, or a nonzero exit MUST write nothing. The list SHALL stay `{ id, title }`. `server.ts` was not edited. This behavior is pull request 198. The coordinator re-ran `sh scripts/check-local-pdf-note.sh` and `sh scripts/check-local-note-search.sh` on `127.0.0.1:8898` at `42211d0`. Both exited 0. The proof is a stub executable. A `path` that is a real PDF SHALL still use the in-daemon `extractPdf` scrape. An agent MUST NOT rebuild either path, MUST NOT add a second `/knowledge` route, and MUST NOT call the Vercel AI Gateway. Daemon CI and Xcode CI are both green on `42211d0` (check run `35742140469`). This does not prove a microphone, a speaker, or that a paper was read. Pull request 197 stays the query-note draft at `e11483d`, with daemon CI and Xcode CI both green (check run `35739420177`). Pull request 195 stays the local note search at `1238daa`, with daemon CI and Xcode CI both green (check run `35736830546`).

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

#### Scenario: The stub check does not prove a paper was read

- **WHEN** `sh scripts/check-local-pdf-note.sh` and `sh scripts/check-local-note-search.sh` pass on `127.0.0.1:8898` at `42211d0`
- **THEN** the agent records that both checks exited 0, that the proof is a stub executable, and that daemon CI and Xcode CI are both green on `42211d0` (check run `35742140469`)
- **AND** the agent does not claim a microphone, a speaker, or that a paper was read

### Requirement: A stub PDF sentence drafts one held note

Pull request 199 SHALL remain the PDF note draft. It adds only `scripts/check-pdf-note-draft.sh`. A stub `MESH_PDF` sentence that includes "summarize this paper" SHALL become one note. A query with no id SHALL draft that note to one relative file. That file SHALL be mode 600 and SHALL NOT be executed. A pairing-code note and a hosts.json note SHALL stay on the existing hold and the model MUST NOT be called. A pdf value containing `://` and a remote `MESH_PDF` MUST write nothing. `server.ts` was not edited. The coordinator re-ran `sh scripts/check-pdf-note-draft.sh` on `127.0.0.1:8898` at `bd04cc0` and it exited 0. An agent MUST NOT rebuild this check, MUST NOT add a second `/knowledge` route, and MUST NOT call the Vercel AI Gateway. Daemon CI and Xcode CI are both green on `bd04cc0` (check run `35743446950`). This does not prove a microphone, a speaker, or that a paper was read. Pull request 198 stays the local PDF note at `42211d0`, with daemon CI and Xcode CI both green (check run `35742140469`). Pull request 197 stays the query-note draft at `e11483d`, with daemon CI and Xcode CI both green (check run `35739420177`). Pull request 195 stays the local note search at `1238daa`, with daemon CI and Xcode CI both green (check run `35736830546`). Daemon CI and Xcode CI are both green on handoff tip `978bdbe17099174c5ff5f4cb5b401fa7f6555f6c` (check run `35743157250`). Daemon CI and Xcode CI are both green on handoff tip `dcfa77f5894058d1b815a0400c7396b17e356f87` (check run `35744449505`). Daemon CI and Xcode CI are both green on handoff tip `b3e91609e5a8c488dded8cc4d3aeae1e840c1b2e` (check run `35745531307`). Daemon CI and Xcode CI are both green on handoff tip `2aad3fd833efbf725f57c9e3c76fbf470a07d44a` (check run `35746528962`). Daemon CI and Xcode CI are both green on handoff tip `bd904b19dc5dc85752888193ad365c2d3a176c8a` (check run `35747820842`).

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

#### Scenario: The draft check does not prove a paper was read

- **WHEN** `sh scripts/check-pdf-note-draft.sh` passes on `127.0.0.1:8898` at `bd04cc0`
- **THEN** the agent records that the check exited 0 and that daemon CI and Xcode CI are both green on `bd04cc0` (check run `35743446950`) and on handoff tips `dcfa77f` (check run `35744449505`) and `b3e9160` (check run `35745531307`), and that daemon CI and Xcode CI are both green on handoff tip `2aad3fd` (check run `35746528962`)
- **AND** the agent does not claim a microphone, a speaker, or that a paper was read

### Requirement: A local TTS exit speaks a PDF note

`POST /knowledge` SHALL accept `{ pdf, title?, speak? }`. When `speak` is true, a local `MESH_TTS` that exits 0 SHALL return `spoken: true`. A remote value, a value containing `://`, or a protocol-relative `MESH_TTS` MUST return 400 before `MESH_PDF` runs and MUST write nothing. When `speak` is omitted, the response SHALL stay `{ id, title }` and TTS MUST NOT start. A missing or failing TTS binary SHALL still store the note and SHALL return `spoken: false`. `server.ts` was not edited. This behavior is pull request 200. The files are `install/payload/meshd/knowledge.ts` and `scripts/check-pdf-note-speak.sh` only. The coordinator re-ran `sh scripts/check-pdf-note-speak.sh`, `sh scripts/check-local-pdf-note.sh`, and `sh scripts/check-pdf-note-draft.sh` on `127.0.0.1:8898` at `d4486c4` and all exited 0. An agent MUST NOT rebuild `extractPdf` or `MESH_PDF`, MUST NOT add a second `/knowledge` route, and MUST NOT call the Vercel AI Gateway. Daemon CI and Xcode CI are both green on `d4486c4` (check run `35746494919`). This does not prove a speaker played audio. Pull request 199 stays the PDF note draft at `bd04cc0`, with daemon CI and Xcode CI both green (check run `35743446950`). Daemon CI and Xcode CI are both green on handoff tip `b3e91609e5a8c488dded8cc4d3aeae1e840c1b2e` (check run `35745531307`). Daemon CI and Xcode CI are both green on handoff tip `2aad3fd833efbf725f57c9e3c76fbf470a07d44a` (check run `35746528962`). Daemon CI and Xcode CI are both green on handoff tip `bd904b19dc5dc85752888193ad365c2d3a176c8a` (check run `35747820842`).

#### Scenario: A local TTS exit returns spoken true

- **WHEN** `speak` is true and `MESH_TTS` is a local executable that exits 0
- **THEN** the response has `spoken: true`

#### Scenario: A remote TTS value writes nothing

- **WHEN** `MESH_TTS` is remote, contains `://`, or is protocol-relative
- **THEN** the daemon answers 400 before `MESH_PDF` runs
- **AND** the daemon writes nothing

#### Scenario: Omitting speak does not start TTS

- **WHEN** `speak` is omitted
- **THEN** the response stays `{ id, title }`
- **AND** TTS does not start

#### Scenario: A missing TTS binary still stores the note

- **WHEN** `speak` is true and the TTS binary is missing or exits nonzero
- **THEN** the note is stored
- **AND** `spoken` is false

#### Scenario: The speak check does not prove a speaker played audio

- **WHEN** `sh scripts/check-pdf-note-speak.sh`, `sh scripts/check-local-pdf-note.sh`, and `sh scripts/check-pdf-note-draft.sh` pass on `127.0.0.1:8898` at `d4486c4`
- **THEN** the agent records that all three checks exited 0 and that daemon CI and Xcode CI are both green on `d4486c4` (check run `35746494919`)
- **AND** the agent does not claim a speaker played audio

### Requirement: An optional local ask is sent with the note

`POST /agent-note` SHALL accept an optional local `ask`. The model SHALL receive the note, a blank line, and the ask. An ask that would move a pairing code, `hosts.json`, `.mesh/token`, or a mesh token MUST be held before the model. An ask containing `://` MUST write nothing. A missing ask SHALL still draft the note text only. `knowledge.ts` was not edited. `server.ts` was not edited. This behavior is pull request 201. The files are `install/payload/meshd/agent-note.ts` and `scripts/check-note-ask.sh`. The coordinator re-ran `sh scripts/check-note-ask.sh`, `sh scripts/check-query-note-draft.sh`, and `sh scripts/check-pdf-note-draft.sh` on `127.0.0.1:8898` at `ae83b95` and all exited 0. An agent MUST NOT add a second `/knowledge` route and MUST NOT call the Vercel AI Gateway. Daemon CI and Xcode CI are both green on `ae83b95` (check run `35747085140`). Pull request 200 stays the PDF note speak at `d4486c4`, with daemon CI and Xcode CI both green (check run `35746494919`). Daemon CI and Xcode CI are both green on handoff tip `bd904b19dc5dc85752888193ad365c2d3a176c8a` (check run `35747820842`).

#### Scenario: The model receives the note, a blank line, and the ask

- **WHEN** `POST /agent-note` includes a local `ask`
- **THEN** the model receives the note, a blank line, and the ask

#### Scenario: A secret-moving ask is held before the model

- **WHEN** the ask would move a pairing code, `hosts.json`, `.mesh/token`, or a mesh token
- **THEN** the ask is held before the model

#### Scenario: An ask containing a scheme writes nothing

- **WHEN** the ask contains `://`
- **THEN** the daemon writes nothing

#### Scenario: A missing ask drafts the note text only

- **WHEN** the ask is omitted
- **THEN** the draft is the note text only

#### Scenario: Daemon-only CI on the note ask is not both jobs green

- **WHEN** `sh scripts/check-note-ask.sh`, `sh scripts/check-query-note-draft.sh`, and `sh scripts/check-pdf-note-draft.sh` pass on `127.0.0.1:8898` at `ae83b95`
- **THEN** the agent records that all three checks exited 0 and that daemon CI and Xcode CI are both green on `ae83b95` (check run `35747085140`)

### Requirement: A spoken PDF note can be asked

The new commit on pull request 202 SHALL add only `scripts/check-spoken-note-ask.sh` after merging pull request 201. A stub `MESH_PDF` sentence spoken by a local `MESH_TTS` that exits 0, then ask "build a reader", SHALL draft one relative file. That file SHALL be mode 600 and SHALL NOT be executed. A remote `MESH_TTS` MUST return 400 and MUST NOT start `MESH_PDF`. A pairing-code ask MUST NOT call the model. A command without confirm MUST NOT run. `server.ts` was not edited. The coordinator re-ran `sh scripts/check-spoken-note-ask.sh`, `sh scripts/check-pdf-note-speak.sh`, and `sh scripts/check-note-ask.sh` on `127.0.0.1:8898` at `b4ce6ac` and all exited 0. An agent MUST NOT add a second `/knowledge` route and MUST NOT call the Vercel AI Gateway. Daemon CI and Xcode CI are both green on `b4ce6ac` (check run `35748224297`). This does not prove a speaker played audio or that a paper was read. Pull request 201 stays the note ask draft at `ae83b95`. Pull request 200 stays `d4486c4`, with daemon CI and Xcode CI both green (check run `35746494919`).

#### Scenario: A spoken note and an ask draft one file

- **WHEN** a stub `MESH_PDF` sentence is spoken by a local `MESH_TTS` that exits 0 and the ask is "build a reader"
- **THEN** the draft is one relative file, mode 600, and is not executed

#### Scenario: A remote TTS value does not start MESH_PDF

- **WHEN** `MESH_TTS` is remote
- **THEN** the daemon answers 400
- **AND** `MESH_PDF` does not start

#### Scenario: A pairing-code ask does not call the model

- **WHEN** the ask is a pairing code
- **THEN** the model is not called

#### Scenario: A command without confirm does not run

- **WHEN** a further command has no confirm
- **THEN** that command does not run

#### Scenario: The spoken ask check does not prove a speaker or a paper

- **WHEN** `sh scripts/check-spoken-note-ask.sh`, `sh scripts/check-pdf-note-speak.sh`, and `sh scripts/check-note-ask.sh` pass on `127.0.0.1:8898` at `b4ce6ac`
- **THEN** the agent records that all three checks exited 0 and that daemon CI and Xcode CI are both green on `b4ce6ac` (check run `35748224297`).
- **AND** the agent does not claim a speaker played audio or that a paper was read

### Requirement: An allowed ask saves the model reply

An allowed local ask SHALL save the model reply as one knowledge note. The title SHALL be the ask, clipped to 200 characters, and the held file SHALL still be written. A missing or whitespace ask MUST add no note. A pairing-code ask, or a reply the route would hold, MUST write neither the file nor a draft. `server.ts` was not edited. This behavior is pull request 203. The files are `install/payload/meshd/agent-note.ts`, `install/payload/meshd/knowledge.ts`, `scripts/check-note-reply-save.sh`, and `scripts/check-spoken-note-ask.sh`. The coordinator re-ran `sh scripts/check-note-reply-save.sh`, `sh scripts/check-spoken-note-ask.sh`, `sh scripts/check-note-ask.sh`, and `sh scripts/check-pdf-note-speak.sh` on `127.0.0.1:8898` at `92d776c` and all exited 0. An agent MUST NOT add a second `/knowledge` route and MUST NOT call the Vercel AI Gateway. Daemon CI and Xcode CI are both green on `92d776c` (check run `35749935885`). Daemon CI and Xcode CI are both green on handoff tip `8fce18d` (check run `35749871537`). Daemon CI and Xcode CI are both green on handoff tip `3ad2a7d` (check run `35752461256`). Daemon CI and Xcode CI are both green on `b4ce6ac` (check run `35748224297`). Daemon CI and Xcode CI are both green on `ae83b95` (check run `35747085140`). This does not prove a speaker or that a paper was read.

#### Scenario: An allowed ask saves one note and the held file

- **WHEN** an allowed local ask returns a model reply
- **THEN** the daemon saves one knowledge note whose title is the ask clipped to 200 characters
- **AND** the held file is still written

#### Scenario: A missing or whitespace ask adds no note

- **WHEN** the ask is missing or whitespace
- **THEN** the daemon adds no knowledge note

#### Scenario: A held ask writes neither file nor draft

- **WHEN** the ask is a pairing code, or the reply is one the route would hold
- **THEN** the daemon writes neither the file nor a draft

#### Scenario: Green CI on the note reply save is not a speaker or a paper

- **WHEN** `sh scripts/check-note-reply-save.sh`, `sh scripts/check-spoken-note-ask.sh`, `sh scripts/check-note-ask.sh`, and `sh scripts/check-pdf-note-speak.sh` pass on `127.0.0.1:8898` at `92d776c`
- **THEN** the agent records that all four checks exited 0 and that daemon CI and Xcode CI are both green on `92d776c` (check run `35749935885`).
- **AND** the agent records that daemon CI and Xcode CI are both green on handoff tip `8fce18d` (check run `35749871537`).
- **AND** the agent records that daemon CI and Xcode CI are both green on `b4ce6ac` (check run `35748224297`).
- **AND** the agent records that daemon CI and Xcode CI are both green on `ae83b95` (check run `35747085140`).
- **AND** the agent does not claim a speaker or that a paper was read

### Requirement: A saved reply can be drafted alone

Pull request 204 SHALL add only `scripts/check-reply-note-draft.sh`. A later local query that matches only the saved reply SHALL draft that reply to one relative file. That file SHALL be mode 600 and SHALL NOT be executed. A query that matches the original note and the reply MUST return 409 and MUST write nothing. A pairing-code ask MUST save no note, and a query for that ask MUST NOT draft. `server.ts` was not edited. The coordinator re-ran `sh scripts/check-reply-note-draft.sh`, `sh scripts/check-note-reply-save.sh`, `sh scripts/check-spoken-note-ask.sh`, and `sh scripts/check-note-ask.sh` on `127.0.0.1:8898` at `4d6ddbb` and all exited 0. An agent MUST NOT add a second `/knowledge` route and MUST NOT call the Vercel AI Gateway. Daemon CI and Xcode CI are both green on `4d6ddbb` (check run `35750995976`). An agent MUST NOT claim CI on `fb0aab8`. An agent MUST NOT claim both jobs are green on `97278aa`. Daemon CI is green on handoff tip `97278aa` (check run `35751643074`). Apps (Xcode) was cancelled on that run. Do not claim both jobs are green on `97278aa`. An agent MUST NOT claim both jobs are green on `97278aa`. Daemon CI and Xcode CI are both green on handoff tip `8fce18d` (check run `35749871537`). Daemon CI and Xcode CI are both green on handoff tip `3ad2a7d` (check run `35752461256`). Daemon CI and Xcode CI are both green on `b4ce6ac` (check run `35748224297`). Daemon CI and Xcode CI are both green on `ae83b95` (check run `35747085140`). Daemon CI and Xcode CI are both green on `92d776c` (check run `35749935885`). This does not prove a speaker or that a paper was read.

#### Scenario: One matching reply drafts one file

- **WHEN** a later local query matches only the saved reply
- **THEN** the draft is that reply in one relative file, mode 600, and is not executed

#### Scenario: A query that matches the note and the reply writes nothing

- **WHEN** a query matches the original note and the reply
- **THEN** the daemon returns 409 and writes nothing

#### Scenario: A pairing-code ask does not draft

- **WHEN** the ask is a pairing code
- **THEN** the daemon saves no note
- **AND** a query for that ask does not draft

#### Scenario: Green CI on the reply note draft is not a speaker or a paper

- **WHEN** `sh scripts/check-reply-note-draft.sh`, `sh scripts/check-note-reply-save.sh`, `sh scripts/check-spoken-note-ask.sh`, and `sh scripts/check-note-ask.sh` pass on `127.0.0.1:8898` at `4d6ddbb`
- **THEN** the agent records that all four checks exited 0 and that Daemon CI and Xcode CI are both green on `4d6ddbb` (check run `35750995976`).
- **AND** the agent records that Daemon CI and Xcode CI are both green on handoff tip `3ad2a7d` (check run `35752461256`).
- **AND** the agent records that Daemon CI is green on handoff tip `97278aa` (check run `35751643074`). Apps (Xcode) was cancelled on that run. Do not claim both jobs are green on `97278aa`.
- **AND** the agent does not claim CI on `fb0aab8`
- **AND** the agent records that daemon CI and Xcode CI are both green on handoff tip `8fce18d` (check run `35749871537`), on `b4ce6ac` (check run `35748224297`), on `ae83b95` (check run `35747085140`), and on `92d776c` (check run `35749935885`)
- **AND** the agent does not claim a speaker or that a paper was read

### Requirement: A saved reply can be asked

Pull request 205 SHALL add only `scripts/check-saved-reply-ask.sh`. An allowed ask SHALL save one reply note. A later `POST /agent-note` with no id, a `q` that matches only that reply, and a new local ask SHALL send the saved reply, a blank line, and the ask. That call SHALL write one relative file, mode 600, not executed, and SHALL save the new reply as another note. A pairing-code second ask MUST write nothing. A second ask containing `://` MUST return 400 and MUST write nothing. A `q` that matches the original note and the saved reply MUST return 409 and MUST write nothing. The list SHALL stay `{ id, title }`. `server.ts` was not edited. The coordinator re-ran `sh scripts/check-saved-reply-ask.sh`, `sh scripts/check-reply-note-draft.sh`, and `sh scripts/check-note-ask.sh` on `127.0.0.1:8898` at `294d252` and all exited 0. The gateway key was unset. An agent MUST NOT add a second `/knowledge` route and MUST NOT call the Vercel AI Gateway. Daemon CI and Xcode CI are both green on `294d252` (check run `35753000381`). Daemon CI and Xcode CI are both green on `4d6ddbb` (check run `35750995976`). Daemon CI and Xcode CI are both green on handoff tip `3ad2a7d` (check run `35752461256`). Daemon CI and Xcode CI are both green on handoff tip `8fce18d` (check run `35749871537`). Daemon CI and Xcode CI are both green on `b4ce6ac` (check run `35748224297`). Daemon CI and Xcode CI are both green on `ae83b95` (check run `35747085140`). Daemon CI and Xcode CI are both green on `92d776c` (check run `35749935885`). Daemon CI is green on handoff tip `97278aa` (check run `35751643074`). Apps (Xcode) was cancelled on that run. Do not claim both jobs are green on `97278aa`. This does not prove a speaker or that a paper was read.

#### Scenario: A later ask sends the saved reply

- **WHEN** `POST /agent-note` has no id, a `q` that matches only the saved reply, and a new local ask
- **THEN** the model receives the saved reply, a blank line, and the ask
- **AND** the draft is one relative file, mode 600, and is not executed
- **AND** the new reply is saved as another note

#### Scenario: A pairing-code second ask writes nothing

- **WHEN** the second ask is a pairing code
- **THEN** the daemon writes nothing

#### Scenario: A second ask containing a scheme is 400

- **WHEN** the second ask contains `://`
- **THEN** the daemon returns 400 and writes nothing

#### Scenario: A query that matches the note and the reply is 409

- **WHEN** `q` matches the original note and the saved reply
- **THEN** the daemon returns 409 and writes nothing

#### Scenario: The list stays id and title

- **WHEN** the daemon lists notes after the saved reply ask
- **THEN** each note is `{ id, title }`

#### Scenario: Green CI on the saved reply ask is not a speaker or a paper

- **WHEN** `sh scripts/check-saved-reply-ask.sh`, `sh scripts/check-reply-note-draft.sh`, and `sh scripts/check-note-ask.sh` pass on `127.0.0.1:8898` at `294d252`
- **THEN** the agent records that all three checks exited 0 and that daemon CI and Xcode CI are both green on `294d252` (check run `35753000381`)
- **AND** the agent records that Daemon CI and Xcode CI are both green on `4d6ddbb` (check run `35750995976`).
- **AND** the agent records that Daemon CI and Xcode CI are both green on handoff tip `3ad2a7d` (check run `35752461256`).
- **AND** the agent records that Daemon CI is green on handoff tip `97278aa` (check run `35751643074`). Apps (Xcode) was cancelled on that run. Do not claim both jobs are green on `97278aa`.
- **AND** the agent does not claim a speaker or that a paper was read

### Requirement: A second saved reply can be drafted

Pull request 206 SHALL add only `scripts/check-second-reply-draft.sh`. `agent-note.ts` was not edited. An allowed ask SHALL save reply A. A later `POST /agent-note` with no id, a `q` that matches only A, and a new allowed ask SHALL send A, a blank line, and the ask. That call SHALL write one relative file, mode 600, not executed, and SHALL save reply B. A later `q` that matches only B SHALL draft B to one relative file, mode 600, not executed. That draft MUST NOT be A and MUST NOT be the original note. A `q` that matches A and B MUST return 409 and MUST write nothing. A pairing-code ask on the second hop MUST write nothing. The list SHALL stay `{ id, title }`. `server.ts` was not edited. The coordinator re-ran `sh scripts/check-second-reply-draft.sh`, `sh scripts/check-saved-reply-ask.sh`, and `sh scripts/check-reply-note-draft.sh` on `127.0.0.1:8898` at `0de3ba9` and all exited 0. The gateway key was unset. An agent MUST NOT add a second `/knowledge` route and MUST NOT call the Vercel AI Gateway. Daemon CI and Xcode CI are both green on `0de3ba9` (check run `35754767900`). Daemon CI and Xcode CI are both green on handoff tip `168d08e` (check run `35754719132`). Daemon CI and Xcode CI are both green on handoff tip `1aca048` (check run `35755761670`). Daemon CI and Xcode CI are both green on `294d252` (check run `35753000381`). Daemon CI and Xcode CI are both green on `4d6ddbb` (check run `35750995976`). Daemon CI and Xcode CI are both green on handoff tip `3ad2a7d` (check run `35752461256`). Daemon CI is green on handoff tip `97278aa` (check run `35751643074`). Apps (Xcode) was cancelled on that run. Do not claim both jobs are green on `97278aa`. This does not prove a speaker or that a paper was read.

#### Scenario: A later query drafts only reply B

- **WHEN** a later `q` matches only reply B
- **THEN** the draft is reply B in one relative file, mode 600, and is not executed
- **AND** the draft is not reply A and is not the original note

#### Scenario: A query that matches A and B is 409

- **WHEN** `q` matches reply A and reply B
- **THEN** the daemon returns 409 and writes nothing

#### Scenario: A pairing-code ask on the second hop writes nothing

- **WHEN** the ask on the second hop is a pairing code
- **THEN** the daemon writes nothing

#### Scenario: The list stays id and title

- **WHEN** the daemon lists notes after the second reply draft
- **THEN** each note is `{ id, title }`

#### Scenario: Green CI on the second reply draft is not a speaker or a paper

- **WHEN** `sh scripts/check-second-reply-draft.sh`, `sh scripts/check-saved-reply-ask.sh`, and `sh scripts/check-reply-note-draft.sh` pass on `127.0.0.1:8898` at `0de3ba9`
- **THEN** the agent records that all three checks exited 0 and that daemon CI and Xcode CI are both green on `0de3ba9` (check run `35754767900`)
- **AND** the agent records that daemon CI and Xcode CI are both green on handoff tip `168d08e` (check run `35754719132`)
- **AND** the agent records that daemon CI and Xcode CI are both green on `294d252` (check run `35753000381`)
- **AND** the agent records that daemon CI and Xcode CI are both green on `4d6ddbb` (check run `35750995976`)
- **AND** the agent records that daemon CI and Xcode CI are both green on handoff tip `3ad2a7d` (check run `35752461256`)
- **AND** the agent records that daemon CI is green on handoff tip `97278aa` (check run `35751643074`). Apps (Xcode) was cancelled on that run. Do not claim both jobs are green on `97278aa`.
- **AND** the agent does not claim a speaker or that a paper was read

### Requirement: A model class can be drafted

Pull request 207 SHALL add only `scripts/check-model-class.sh`. `agent-note.ts` was not edited. An allowed ask with a loopback model SHALL return `modelClass` `local`, SHALL write one relative file, mode 600, not executed, and the JSON MUST NOT contain `sk-secret`. A pairing-code ask with `https://llm.example/v1` SHALL return `modelClass` `user-subscription`, `held` true, and `draft` null, and the stub hit count MUST NOT increase. An allowed ask with `http://user:sk-secret@127.0.0.1:<stub>/v1` SHALL return `modelClass` `local`. The stub URL MUST have no userinfo. The stub body and the JSON MUST NOT contain `sk-secret`. The knowledge list SHALL stay `{ id, title }`. `server.ts` was not edited. The coordinator re-ran `sh scripts/check-model-class.sh` and `sh scripts/check-second-reply-draft.sh` on `127.0.0.1:8898` at `48f1970` and both exited 0. The gateway key was unset. An agent MUST NOT add a second `/knowledge` route and MUST NOT call the Vercel AI Gateway. An agent MUST NOT claim both jobs are green on `48f1970`. Apps (Xcode) failed on `48f1970` (check run `35757430003`). Self-checks failed because `scripts/check-model-class.sh` read `/proc`, which macOS does not have, and port 8898 stayed in use. Daemon CI stayed green. Do not claim both jobs are green on `48f1970`. The fix is not on that tip. Daemon CI and Xcode CI are both green on `0de3ba9` (check run `35754767900`). This does not prove a speaker or that a paper was read.

#### Scenario: A loopback model is local

- **WHEN** an allowed ask uses a loopback model
- **THEN** the response `modelClass` is `local`
- **AND** the draft is one relative file, mode 600, and is not executed
- **AND** the JSON has no `sk-secret`

#### Scenario: A pairing-code ask on a remote model is held

- **WHEN** the ask is a pairing code and the model is `https://llm.example/v1`
- **THEN** `modelClass` is `user-subscription`, `held` is true, and `draft` is null
- **AND** the stub hit count does not increase

#### Scenario: Userinfo is stripped from a loopback model

- **WHEN** an allowed ask uses `http://user:sk-secret@127.0.0.1:<stub>/v1`
- **THEN** `modelClass` is `local`
- **AND** the stub URL has no userinfo
- **AND** the stub body and the JSON do not contain `sk-secret`

#### Scenario: The list stays id and title

- **WHEN** the daemon lists notes after the model class draft
- **THEN** each note is `{ id, title }`

#### Scenario: Daemon-only CI on the model class draft is not both jobs green

- **WHEN** `sh scripts/check-model-class.sh` and `sh scripts/check-second-reply-draft.sh` pass on `127.0.0.1:8898` at `48f1970`
- **THEN** the agent records that both checks exited 0 and that daemon CI is green on `48f1970` (check run `35757430003`) while apps (Xcode) is still running
- **AND** the agent does not claim both jobs are green on `48f1970`
- **AND** the agent records that daemon CI and Xcode CI are both green on `0de3ba9` (check run `35754767900`)
- **AND** the agent does not claim a speaker or that a paper was read

### Requirement: A saved note omits the model URL

Pull request 208 SHALL add only `scripts/check-note-omits-model-url.sh`. `agent-note.ts` and `knowledge.ts` were not edited. An allowed ask with `http://user:sk-secret@127.0.0.1:<stub>/v1` SHALL return `modelClass` `local`, SHALL write one relative file, mode 600, not executed, and SHALL save one knowledge note whose title is the ask and whose body is the model reply only. No file under `MESHD_STATE` and no held draft MUST contain `sk-secret`, `user:sk-secret`, or that raw model URL. A pairing-code ask with `https://llm.example/v1` SHALL return `modelClass` `user-subscription`, `held` true, and `draft` null, MUST NOT call the stub, and no file under `MESHD_STATE` MUST contain `llm.example` or `sk-secret`. The knowledge list SHALL stay `{ id, title }`. `server.ts` was not edited. The coordinator re-ran `sh scripts/check-note-omits-model-url.sh` and `sh scripts/check-model-class.sh` on `127.0.0.1:8898` at `890a704` and both exited 0. The gateway key was unset. An agent MUST NOT add a second `/knowledge` route and MUST NOT call the Vercel AI Gateway. Daemon CI is green on `890a704` (check run `35759364727`). Apps (Xcode) is still running on that run. Do not claim both jobs are green on `890a704`. Pull request 208 tip is now `0a1b0e2cd13348983ec20954a9590259df58347c`. It merges `5f6d6b0` into the note-URL branch. No conflicts. History was not rewritten. `sh scripts/check-note-omits-model-url.sh` and `sh scripts/check-model-class.sh` exited 0 on `127.0.0.1:8898`. After each, `lsof -nP -iTCP:8898 -sTCP:LISTEN` printed nothing. Daemon CI and apps (Xcode) are both green on `0a1b0e2` (check run `35759941279`). Pull request 209 tip is now `bbff8dae533cf0373523d28935e758b3101419b7`. It merges `0a1b0e2` into the subscription branch. No conflicts. History was not rewritten. `sh scripts/check-subscription-note.sh` and `sh scripts/check-model-class.sh` exited 0 on `127.0.0.1:8898`. After each, nothing was listening on port 8898. Daemon CI and apps (Xcode) are both green on `bbff8da` (check run `35760223545`). Pull request 210 is https://github.com/aryateja2106/lecoder-watch/pull/210 on `cursor/subscription-reply-draft-e469`, base `cursor/subscription-note-draft-e469` (still `bbff8dae533cf0373523d28935e758b3101419b7`), tip `10da6b70c980660da264e19126b5272eef0c3de3`; the only added file is `scripts/check-subscription-reply.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-reply.sh` and `sh scripts/check-subscription-note.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; daemon CI and apps (Xcode) are both green on `10da6b7` (check run `35761104930`); this does not prove a speaker or that a paper was read. Pull request 211 is https://github.com/aryateja2106/lecoder-watch/pull/211 on `cursor/subscription-reply-ask-e469`, base `cursor/subscription-reply-draft-e469` (still `10da6b70c980660da264e19126b5272eef0c3de3`), tip `785bb6f9c33df2f28d79339360b2a073599317fa`; the only added file is `scripts/check-subscription-reply-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-reply-ask.sh` and `sh scripts/check-subscription-reply.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; daemon CI and apps (Xcode) are both green on `785bb6f` (check run `35762574523`); this does not prove a speaker or that a paper was read. Pull request 212 is https://github.com/aryateja2106/lecoder-watch/pull/212 on `cursor/subscription-second-reply-e469`, base `cursor/subscription-reply-ask-e469` (still `785bb6f9c33df2f28d79339360b2a073599317fa`), tip `29d68882b05952f238206e68ff9fd1c5a858d3c7`; the only added file is `scripts/check-subscription-second-reply.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-second-reply.sh` and `sh scripts/check-subscription-reply-ask.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; daemon CI and apps (Xcode) are both green on `29d6888` (check run `35763737894`); this does not prove a speaker or that a paper was read. Pull request 213 is https://github.com/aryateja2106/lecoder-watch/pull/213 on `cursor/subscription-reply-confirm-e469`, base `cursor/subscription-second-reply-e469` (still `29d68882b05952f238206e68ff9fd1c5a858d3c7`), tip `e424ae27f6aa08a41ae09d0f32e3b69d788ee82e`; the only added file is `scripts/check-subscription-reply-confirm.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-reply-confirm.sh` and `sh scripts/check-subscription-second-reply.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; daemon CI and apps (Xcode) are both green on `e424ae27` (check run `35765862595`); this does not prove a speaker or that a paper was read. Pull request 214 is https://github.com/aryateja2106/lecoder-watch/pull/214 on `cursor/subscription-confirm-draft-e469`, base `cursor/subscription-reply-confirm-e469` (still `e424ae27f6aa08a41ae09d0f32e3b69d788ee82e`), tip `a6bbd0205682d33c40a5b5900ba8567bbe8f9e92` (parent `7dbdbcb942fac63183aba3cc4bb764e7bf325ef0`); the only added file versus the confirm tip is `scripts/check-subscription-confirm-draft.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-confirm-draft.sh` and `sh scripts/check-subscription-reply-confirm.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; the later query is `margin-token-only` and matches only that confirmed ask; daemon CI and apps (Xcode) are both green on `a6bbd02` (check run `35768647989`); this does not prove a speaker or that a paper was read. Pull request 215 is https://github.com/aryateja2106/lecoder-watch/pull/215 on `cursor/subscription-confirm-ask-e469`, base `cursor/subscription-confirm-draft-e469` (still `a6bbd0205682d33c40a5b5900ba8567bbe8f9e92`), tip `5f2e35fabf971041c385126251908c4a98f90794`; the only added file is `scripts/check-subscription-confirm-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-confirm-ask.sh` and `sh scripts/check-subscription-confirm-draft.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a later ask `margin-ask-only` of only the confirmed note does not run the command, and `margin-ask-true` runs it only when confirm is true; daemon CI and apps (Xcode) are both green on `5f2e35f` (check run `35770492947`); this does not prove a speaker or that a paper was read. Pull request 216 is https://github.com/aryateja2106/lecoder-watch/pull/216 on `cursor/subscription-ask-draft-e469`, base `cursor/subscription-confirm-ask-e469` (still `5f2e35fabf971041c385126251908c4a98f90794`), tip `b584480daf55c67070aa96a202b4f8138f2018d5`; the only added file is `scripts/check-subscription-ask-draft.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-ask-draft.sh` and `sh scripts/check-subscription-confirm-ask.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a later query of only the note titled `margin-ask-only` does not run the command, and confirm true creates `held-saved-ran`; daemon CI and apps (Xcode) are both green on `b584480` (check run `35771113323`); this does not prove a speaker or that a paper was read. Pull request 217 is https://github.com/aryateja2106/lecoder-watch/pull/217 on `cursor/subscription-saved-ask-e469`, base `cursor/subscription-ask-draft-e469` (still `b584480daf55c67070aa96a202b4f8138f2018d5`), tip `fa36116ad9aad19b40e50e1afe503e517de980c1`; the only added file is `scripts/check-subscription-saved-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-saved-ask.sh` and `sh scripts/check-subscription-ask-draft.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a further ask `margin-saved-ask` of only the saved note does not run the command, and `margin-saved-true` runs it only when confirm is true; daemon CI and apps (Xcode) are both green on `fa36116` (check run `35771883445`); this does not prove a speaker or that a paper was read. Pull request 218 is https://github.com/aryateja2106/lecoder-watch/pull/218 on `cursor/subscription-secret-reply-e469`, base `cursor/subscription-saved-ask-e469` (still `fa36116ad9aad19b40e50e1afe503e517de980c1`), tip `e07856f2750bcdec4dde54bf3ab772361d6bd998`; the only added file is `scripts/check-subscription-secret-reply.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-secret-reply.sh` and `sh scripts/check-subscription-saved-ask.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a user-subscription reply that names a pairing code stays held when confirm is true, writes no file, saves no note, and does not run; daemon CI and apps (Xcode) are both green on `e07856f` (check run `35772919892`); this does not prove a speaker or that a paper was read. Pull request 219 is https://github.com/aryateja2106/lecoder-watch/pull/219 on `cursor/subscription-spoken-ask-e469`, base `cursor/subscription-secret-reply-e469` (still `e07856f2750bcdec4dde54bf3ab772361d6bd998`), tip `fc2a13c5e8ded0a976913b44c0e65f7d2ab6a6aa`; the only added file is `scripts/check-subscription-spoken-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-spoken-ask.sh` and `sh scripts/check-subscription-secret-reply.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a local spoken note is asked through `llm.example`, confirm omitted does not run the command, confirm true runs it once, and a pairing-code ask or transcript stays held; daemon CI and apps (Xcode) are both green on `fc2a13c` (check run `35775132183`); this does not prove a speaker or that a paper was read. Pull request 220 is https://github.com/aryateja2106/lecoder-watch/pull/220 on `cursor/subscription-spoken-secret-reply-e469`, base `cursor/subscription-spoken-ask-e469` (still `fc2a13c5e8ded0a976913b44c0e65f7d2ab6a6aa`), tip `56729000c7117d0430fa710fa9778bdc6da763aa`; the only added file is `scripts/check-subscription-spoken-secret-reply.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-spoken-secret-reply.sh` and `sh scripts/check-subscription-spoken-ask.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a spoken note asked through `llm.example` stays held when the model reply names a pairing code, even when confirm is true, and that reply is not saved; daemon CI and apps (Xcode) are both green on `5672900` (check run `35775998567`); this does not prove a speaker or that a paper was read. Pull request 221 is https://github.com/aryateja2106/lecoder-watch/pull/221 on `cursor/subscription-spoken-saved-ask-e469`, base `cursor/subscription-spoken-secret-reply-e469` (still `56729000c7117d0430fa710fa9778bdc6da763aa`), tip `9fea3cc93645072e61711e569313e6eadbb4a887`; the only added file is `scripts/check-subscription-spoken-saved-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-spoken-saved-ask.sh` and `sh scripts/check-subscription-spoken-secret-reply.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts`, `knowledge.ts`, and `server.ts` were not edited; after a held secret reply, asking only the note titled `spoken-cedar-hinge` through `llm.example` does not run the command when confirm is omitted and runs it once when confirm is true, and the knowledge list has no pairing-code title; daemon CI and apps (Xcode) are both green on `9fea3cc` (check run `35776596930`); this does not prove a speaker or that a paper was read. Pull request 222 is https://github.com/aryateja2106/lecoder-watch/pull/222 on `cursor/extracted-page-speak-e469`, base `cursor/subscription-spoken-saved-ask-e469` (still `9fea3cc93645072e61711e569313e6eadbb4a887`), tip `1f6def342d6fafbd5c15885523e680a494d3b689`; the only added file is `scripts/check-extracted-page-speak.sh`, which does not read `/proc` and on exit kills the daemon process group; `sh scripts/check-extracted-page-speak.sh` and `sh scripts/check-knowledge.sh` exited 0 on `127.0.0.1:8898` and after the new script nothing was listening on port 8898; `agent-note.ts`, `knowledge.ts`, and `server.ts` were not edited; `POST /knowledge` with a local PDF path and `speak: true` stores the extracted sentence `The oak margin names the extracted page.` under the title `Oak page` and a local `MESH_TTS` binary that exits 0 returns `spoken: true`; a remote `MESH_TTS` is not started and `spoken` is false; omitting `speak` leaves the binary idle; daemon CI and apps (Xcode) are both green on `1f6def3` (check run `35778325457`); this does not prove a speaker or that a paper was read. Pull request 223 is https://github.com/aryateja2106/lecoder-watch/pull/223 on `cursor/extracted-note-ask-e469`, base `cursor/extracted-page-speak-e469` (still `1f6def342d6fafbd5c15885523e680a494d3b689`), tip `3edd7de99a9eceeef4e5b18da6fc42b7ed8a21b5`; the only added file is `scripts/check-extracted-note-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the model stub; `sh scripts/check-extracted-note-ask.sh` and `sh scripts/check-extracted-page-speak.sh` exited 0 on `127.0.0.1:8898` and after the new script nothing was listening on port 8898; `agent-note.ts`, `knowledge.ts`, and `server.ts` were not edited; `POST /knowledge` with the oak page path and `speak: true` stores `The oak margin names the extracted page.` under the title `Oak page` and a local `MESH_TTS` that exits 0 returns `spoken: true`; asking `Oak page` with `build a reader` does not run when confirm is omitted and runs once when confirm is true; `modelClass` is `user-subscription`; the draft has no `sk-` and no `llm.example` userinfo; asking `Pairing page` with confirm true does not run, does not call the model, and writes no draft; daemon CI is green on `3edd7de` (check run `35781165080`); Apps (Xcode) is still running, so do not claim both jobs are green on `3edd7de`; this does not prove a speaker or that a paper was read. `sh scripts/check-note-omits-model-url.sh` exited 0 on `127.0.0.1:8898` at `890a704` and `lsof -nP -iTCP:8898 -sTCP:LISTEN` printed nothing afterward. That script no longer reads `/proc`. On exit it signals the daemon process group and the stub. `scripts/check-model-class.sh` was not edited on that commit, so the copy of that script on this branch is still the one that failed macOS CI. Pull request 207 tip `5f6d6b00b32421dcfe015becc378f2771d0eeff6` changes only `scripts/check-model-class.sh`. It no longer reads `/proc`. On exit it signals the daemon process group and the stub. `sh scripts/check-model-class.sh` exited 0, then `sh scripts/check-second-reply-draft.sh` exited 0 on `127.0.0.1:8898`. After each, `lsof -nP -iTCP:8898 -sTCP:LISTEN` printed nothing. A SIGTERM during the model-class check also left 8898 free. Daemon CI and apps (Xcode) are both green on `5f6d6b0` (check run `35759586722`). The failure on `48f1970` stays a failure. This later tip is the fix. An agent MUST NOT claim both jobs are green on `48f1970`. Daemon CI is green on `890a704` (check run `35759364727`). Apps (Xcode) is still running on that run. Do not claim both jobs are green on `890a704`. Pull request 208 tip is now `0a1b0e2cd13348983ec20954a9590259df58347c`. It merges `5f6d6b0` into the note-URL branch. No conflicts. History was not rewritten. `sh scripts/check-note-omits-model-url.sh` and `sh scripts/check-model-class.sh` exited 0 on `127.0.0.1:8898`. After each, `lsof -nP -iTCP:8898 -sTCP:LISTEN` printed nothing. Daemon CI and apps (Xcode) are both green on `0a1b0e2` (check run `35759941279`). Pull request 209 tip is now `bbff8dae533cf0373523d28935e758b3101419b7`. It merges `0a1b0e2` into the subscription branch. No conflicts. History was not rewritten. `sh scripts/check-subscription-note.sh` and `sh scripts/check-model-class.sh` exited 0 on `127.0.0.1:8898`. After each, nothing was listening on port 8898. Daemon CI and apps (Xcode) are both green on `bbff8da` (check run `35760223545`). Pull request 210 is https://github.com/aryateja2106/lecoder-watch/pull/210 on `cursor/subscription-reply-draft-e469`, base `cursor/subscription-note-draft-e469` (still `bbff8dae533cf0373523d28935e758b3101419b7`), tip `10da6b70c980660da264e19126b5272eef0c3de3`; the only added file is `scripts/check-subscription-reply.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-reply.sh` and `sh scripts/check-subscription-note.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; daemon CI and apps (Xcode) are both green on `10da6b7` (check run `35761104930`); this does not prove a speaker or that a paper was read. Pull request 211 is https://github.com/aryateja2106/lecoder-watch/pull/211 on `cursor/subscription-reply-ask-e469`, base `cursor/subscription-reply-draft-e469` (still `10da6b70c980660da264e19126b5272eef0c3de3`), tip `785bb6f9c33df2f28d79339360b2a073599317fa`; the only added file is `scripts/check-subscription-reply-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-reply-ask.sh` and `sh scripts/check-subscription-reply.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; daemon CI and apps (Xcode) are both green on `785bb6f` (check run `35762574523`); this does not prove a speaker or that a paper was read. Pull request 212 is https://github.com/aryateja2106/lecoder-watch/pull/212 on `cursor/subscription-second-reply-e469`, base `cursor/subscription-reply-ask-e469` (still `785bb6f9c33df2f28d79339360b2a073599317fa`), tip `29d68882b05952f238206e68ff9fd1c5a858d3c7`; the only added file is `scripts/check-subscription-second-reply.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-second-reply.sh` and `sh scripts/check-subscription-reply-ask.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; daemon CI and apps (Xcode) are both green on `29d6888` (check run `35763737894`); this does not prove a speaker or that a paper was read. Pull request 213 is https://github.com/aryateja2106/lecoder-watch/pull/213 on `cursor/subscription-reply-confirm-e469`, base `cursor/subscription-second-reply-e469` (still `29d68882b05952f238206e68ff9fd1c5a858d3c7`), tip `e424ae27f6aa08a41ae09d0f32e3b69d788ee82e`; the only added file is `scripts/check-subscription-reply-confirm.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-reply-confirm.sh` and `sh scripts/check-subscription-second-reply.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; daemon CI and apps (Xcode) are both green on `e424ae27` (check run `35765862595`); this does not prove a speaker or that a paper was read. Pull request 214 is https://github.com/aryateja2106/lecoder-watch/pull/214 on `cursor/subscription-confirm-draft-e469`, base `cursor/subscription-reply-confirm-e469` (still `e424ae27f6aa08a41ae09d0f32e3b69d788ee82e`), tip `a6bbd0205682d33c40a5b5900ba8567bbe8f9e92` (parent `7dbdbcb942fac63183aba3cc4bb764e7bf325ef0`); the only added file versus the confirm tip is `scripts/check-subscription-confirm-draft.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-confirm-draft.sh` and `sh scripts/check-subscription-reply-confirm.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; the later query is `margin-token-only` and matches only that confirmed ask; daemon CI and apps (Xcode) are both green on `a6bbd02` (check run `35768647989`); this does not prove a speaker or that a paper was read. Pull request 215 is https://github.com/aryateja2106/lecoder-watch/pull/215 on `cursor/subscription-confirm-ask-e469`, base `cursor/subscription-confirm-draft-e469` (still `a6bbd0205682d33c40a5b5900ba8567bbe8f9e92`), tip `5f2e35fabf971041c385126251908c4a98f90794`; the only added file is `scripts/check-subscription-confirm-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-confirm-ask.sh` and `sh scripts/check-subscription-confirm-draft.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a later ask `margin-ask-only` of only the confirmed note does not run the command, and `margin-ask-true` runs it only when confirm is true; daemon CI and apps (Xcode) are both green on `5f2e35f` (check run `35770492947`); this does not prove a speaker or that a paper was read. Pull request 216 is https://github.com/aryateja2106/lecoder-watch/pull/216 on `cursor/subscription-ask-draft-e469`, base `cursor/subscription-confirm-ask-e469` (still `5f2e35fabf971041c385126251908c4a98f90794`), tip `b584480daf55c67070aa96a202b4f8138f2018d5`; the only added file is `scripts/check-subscription-ask-draft.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-ask-draft.sh` and `sh scripts/check-subscription-confirm-ask.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a later query of only the note titled `margin-ask-only` does not run the command, and confirm true creates `held-saved-ran`; daemon CI and apps (Xcode) are both green on `b584480` (check run `35771113323`); this does not prove a speaker or that a paper was read. Pull request 217 is https://github.com/aryateja2106/lecoder-watch/pull/217 on `cursor/subscription-saved-ask-e469`, base `cursor/subscription-ask-draft-e469` (still `b584480daf55c67070aa96a202b4f8138f2018d5`), tip `fa36116ad9aad19b40e50e1afe503e517de980c1`; the only added file is `scripts/check-subscription-saved-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-saved-ask.sh` and `sh scripts/check-subscription-ask-draft.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a further ask `margin-saved-ask` of only the saved note does not run the command, and `margin-saved-true` runs it only when confirm is true; daemon CI and apps (Xcode) are both green on `fa36116` (check run `35771883445`); this does not prove a speaker or that a paper was read. Pull request 218 is https://github.com/aryateja2106/lecoder-watch/pull/218 on `cursor/subscription-secret-reply-e469`, base `cursor/subscription-saved-ask-e469` (still `fa36116ad9aad19b40e50e1afe503e517de980c1`), tip `e07856f2750bcdec4dde54bf3ab772361d6bd998`; the only added file is `scripts/check-subscription-secret-reply.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-secret-reply.sh` and `sh scripts/check-subscription-saved-ask.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a user-subscription reply that names a pairing code stays held when confirm is true, writes no file, saves no note, and does not run; daemon CI and apps (Xcode) are both green on `e07856f` (check run `35772919892`); this does not prove a speaker or that a paper was read. Pull request 219 is https://github.com/aryateja2106/lecoder-watch/pull/219 on `cursor/subscription-spoken-ask-e469`, base `cursor/subscription-secret-reply-e469` (still `e07856f2750bcdec4dde54bf3ab772361d6bd998`), tip `fc2a13c5e8ded0a976913b44c0e65f7d2ab6a6aa`; the only added file is `scripts/check-subscription-spoken-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-spoken-ask.sh` and `sh scripts/check-subscription-secret-reply.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a local spoken note is asked through `llm.example`, confirm omitted does not run the command, confirm true runs it once, and a pairing-code ask or transcript stays held; daemon CI and apps (Xcode) are both green on `fc2a13c` (check run `35775132183`); this does not prove a speaker or that a paper was read. Pull request 220 is https://github.com/aryateja2106/lecoder-watch/pull/220 on `cursor/subscription-spoken-secret-reply-e469`, base `cursor/subscription-spoken-ask-e469` (still `fc2a13c5e8ded0a976913b44c0e65f7d2ab6a6aa`), tip `56729000c7117d0430fa710fa9778bdc6da763aa`; the only added file is `scripts/check-subscription-spoken-secret-reply.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-spoken-secret-reply.sh` and `sh scripts/check-subscription-spoken-ask.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a spoken note asked through `llm.example` stays held when the model reply names a pairing code, even when confirm is true, and that reply is not saved; daemon CI and apps (Xcode) are both green on `5672900` (check run `35775998567`); this does not prove a speaker or that a paper was read. Pull request 221 is https://github.com/aryateja2106/lecoder-watch/pull/221 on `cursor/subscription-spoken-saved-ask-e469`, base `cursor/subscription-spoken-secret-reply-e469` (still `56729000c7117d0430fa710fa9778bdc6da763aa`), tip `9fea3cc93645072e61711e569313e6eadbb4a887`; the only added file is `scripts/check-subscription-spoken-saved-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-spoken-saved-ask.sh` and `sh scripts/check-subscription-spoken-secret-reply.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts`, `knowledge.ts`, and `server.ts` were not edited; after a held secret reply, asking only the note titled `spoken-cedar-hinge` through `llm.example` does not run the command when confirm is omitted and runs it once when confirm is true, and the knowledge list has no pairing-code title; daemon CI and apps (Xcode) are both green on `9fea3cc` (check run `35776596930`); this does not prove a speaker or that a paper was read. Pull request 222 is https://github.com/aryateja2106/lecoder-watch/pull/222 on `cursor/extracted-page-speak-e469`, base `cursor/subscription-spoken-saved-ask-e469` (still `9fea3cc93645072e61711e569313e6eadbb4a887`), tip `1f6def342d6fafbd5c15885523e680a494d3b689`; the only added file is `scripts/check-extracted-page-speak.sh`, which does not read `/proc` and on exit kills the daemon process group; `sh scripts/check-extracted-page-speak.sh` and `sh scripts/check-knowledge.sh` exited 0 on `127.0.0.1:8898` and after the new script nothing was listening on port 8898; `agent-note.ts`, `knowledge.ts`, and `server.ts` were not edited; `POST /knowledge` with a local PDF path and `speak: true` stores the extracted sentence `The oak margin names the extracted page.` under the title `Oak page` and a local `MESH_TTS` binary that exits 0 returns `spoken: true`; a remote `MESH_TTS` is not started and `spoken` is false; omitting `speak` leaves the binary idle; daemon CI and apps (Xcode) are both green on `1f6def3` (check run `35778325457`); this does not prove a speaker or that a paper was read. Pull request 223 is https://github.com/aryateja2106/lecoder-watch/pull/223 on `cursor/extracted-note-ask-e469`, base `cursor/extracted-page-speak-e469` (still `1f6def342d6fafbd5c15885523e680a494d3b689`), tip `3edd7de99a9eceeef4e5b18da6fc42b7ed8a21b5`; the only added file is `scripts/check-extracted-note-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the model stub; `sh scripts/check-extracted-note-ask.sh` and `sh scripts/check-extracted-page-speak.sh` exited 0 on `127.0.0.1:8898` and after the new script nothing was listening on port 8898; `agent-note.ts`, `knowledge.ts`, and `server.ts` were not edited; `POST /knowledge` with the oak page path and `speak: true` stores `The oak margin names the extracted page.` under the title `Oak page` and a local `MESH_TTS` that exits 0 returns `spoken: true`; asking `Oak page` with `build a reader` does not run when confirm is omitted and runs once when confirm is true; `modelClass` is `user-subscription`; the draft has no `sk-` and no `llm.example` userinfo; asking `Pairing page` with confirm true does not run, does not call the model, and writes no draft; daemon CI is green on `3edd7de` (check run `35781165080`); Apps (Xcode) is still running, so do not claim both jobs are green on `3edd7de`; this does not prove a speaker or that a paper was read. `sh scripts/check-note-omits-model-url.sh` exited 0 on `127.0.0.1:8898` at `890a704` and `lsof -nP -iTCP:8898 -sTCP:LISTEN` printed nothing afterward. That script no longer reads `/proc`. On exit it signals the daemon process group and the stub. `scripts/check-model-class.sh` was not edited on that commit, so the copy of that script on this branch is still the one that failed macOS CI. Pull request 207 tip `5f6d6b00b32421dcfe015becc378f2771d0eeff6` changes only `scripts/check-model-class.sh`. It no longer reads `/proc`. On exit it signals the daemon process group and the stub. `sh scripts/check-model-class.sh` exited 0, then `sh scripts/check-second-reply-draft.sh` exited 0 on `127.0.0.1:8898`. After each, `lsof -nP -iTCP:8898 -sTCP:LISTEN` printed nothing. A SIGTERM during the model-class check also left 8898 free. Daemon CI and apps (Xcode) are both green on `5f6d6b0` (check run `35759586722`). The failure on `48f1970` stays a failure. This later tip is the fix. Apps (Xcode) failed on `48f1970` (check run `35757430003`). Self-checks failed because `scripts/check-model-class.sh` read `/proc`, which macOS does not have, and port 8898 stayed in use. Daemon CI stayed green. Do not claim both jobs are green on `48f1970`. The fix is not on that tip. This does not prove a speaker or that a paper was read.

#### Scenario: The saved note is the reply only

- **WHEN** an allowed ask uses `http://user:sk-secret@127.0.0.1:<stub>/v1`
- **THEN** `modelClass` is `local`
- **AND** the draft is one relative file, mode 600, and is not executed
- **AND** the saved note title is the ask and the body is the model reply only
- **AND** no file under `MESHD_STATE` and no held draft contains `sk-secret`, `user:sk-secret`, or that raw model URL

#### Scenario: A pairing-code ask does not call the stub

- **WHEN** the ask is a pairing code and the model is `https://llm.example/v1`
- **THEN** `modelClass` is `user-subscription`, `held` is true, and `draft` is null
- **AND** the stub is not called
- **AND** no file under `MESHD_STATE` contains `llm.example` or `sk-secret`

#### Scenario: The list stays id and title

- **WHEN** the daemon lists notes after the note that omits the model URL
- **THEN** each note is `{ id, title }`

#### Scenario: Unclaimed CI on the note that omits the model URL is not either job

- **WHEN** `sh scripts/check-note-omits-model-url.sh` and `sh scripts/check-model-class.sh` pass on `127.0.0.1:8898` at `890a704`
- **THEN** the agent records that both checks exited 0 and records that Daemon CI is green on `890a704` (check run `35759364727`). Apps (Xcode) is still running on that run. Do not claim both jobs are green on `890a704`. Pull request 208 tip is now `0a1b0e2cd13348983ec20954a9590259df58347c`. It merges `5f6d6b0` into the note-URL branch. No conflicts. History was not rewritten. `sh scripts/check-note-omits-model-url.sh` and `sh scripts/check-model-class.sh` exited 0 on `127.0.0.1:8898`. After each, `lsof -nP -iTCP:8898 -sTCP:LISTEN` printed nothing. Daemon CI and apps (Xcode) are both green on `0a1b0e2` (check run `35759941279`). Pull request 209 tip is now `bbff8dae533cf0373523d28935e758b3101419b7`. It merges `0a1b0e2` into the subscription branch. No conflicts. History was not rewritten. `sh scripts/check-subscription-note.sh` and `sh scripts/check-model-class.sh` exited 0 on `127.0.0.1:8898`. After each, nothing was listening on port 8898. Daemon CI and apps (Xcode) are both green on `bbff8da` (check run `35760223545`). Pull request 210 is https://github.com/aryateja2106/lecoder-watch/pull/210 on `cursor/subscription-reply-draft-e469`, base `cursor/subscription-note-draft-e469` (still `bbff8dae533cf0373523d28935e758b3101419b7`), tip `10da6b70c980660da264e19126b5272eef0c3de3`; the only added file is `scripts/check-subscription-reply.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-reply.sh` and `sh scripts/check-subscription-note.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; daemon CI and apps (Xcode) are both green on `10da6b7` (check run `35761104930`); this does not prove a speaker or that a paper was read. Pull request 211 is https://github.com/aryateja2106/lecoder-watch/pull/211 on `cursor/subscription-reply-ask-e469`, base `cursor/subscription-reply-draft-e469` (still `10da6b70c980660da264e19126b5272eef0c3de3`), tip `785bb6f9c33df2f28d79339360b2a073599317fa`; the only added file is `scripts/check-subscription-reply-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-reply-ask.sh` and `sh scripts/check-subscription-reply.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; daemon CI and apps (Xcode) are both green on `785bb6f` (check run `35762574523`); this does not prove a speaker or that a paper was read. Pull request 212 is https://github.com/aryateja2106/lecoder-watch/pull/212 on `cursor/subscription-second-reply-e469`, base `cursor/subscription-reply-ask-e469` (still `785bb6f9c33df2f28d79339360b2a073599317fa`), tip `29d68882b05952f238206e68ff9fd1c5a858d3c7`; the only added file is `scripts/check-subscription-second-reply.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-second-reply.sh` and `sh scripts/check-subscription-reply-ask.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; daemon CI and apps (Xcode) are both green on `29d6888` (check run `35763737894`); this does not prove a speaker or that a paper was read. Pull request 213 is https://github.com/aryateja2106/lecoder-watch/pull/213 on `cursor/subscription-reply-confirm-e469`, base `cursor/subscription-second-reply-e469` (still `29d68882b05952f238206e68ff9fd1c5a858d3c7`), tip `e424ae27f6aa08a41ae09d0f32e3b69d788ee82e`; the only added file is `scripts/check-subscription-reply-confirm.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-reply-confirm.sh` and `sh scripts/check-subscription-second-reply.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; daemon CI and apps (Xcode) are both green on `e424ae27` (check run `35765862595`); this does not prove a speaker or that a paper was read. Pull request 214 is https://github.com/aryateja2106/lecoder-watch/pull/214 on `cursor/subscription-confirm-draft-e469`, base `cursor/subscription-reply-confirm-e469` (still `e424ae27f6aa08a41ae09d0f32e3b69d788ee82e`), tip `a6bbd0205682d33c40a5b5900ba8567bbe8f9e92` (parent `7dbdbcb942fac63183aba3cc4bb764e7bf325ef0`); the only added file versus the confirm tip is `scripts/check-subscription-confirm-draft.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-confirm-draft.sh` and `sh scripts/check-subscription-reply-confirm.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; the later query is `margin-token-only` and matches only that confirmed ask; daemon CI and apps (Xcode) are both green on `a6bbd02` (check run `35768647989`); this does not prove a speaker or that a paper was read. Pull request 215 is https://github.com/aryateja2106/lecoder-watch/pull/215 on `cursor/subscription-confirm-ask-e469`, base `cursor/subscription-confirm-draft-e469` (still `a6bbd0205682d33c40a5b5900ba8567bbe8f9e92`), tip `5f2e35fabf971041c385126251908c4a98f90794`; the only added file is `scripts/check-subscription-confirm-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-confirm-ask.sh` and `sh scripts/check-subscription-confirm-draft.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a later ask `margin-ask-only` of only the confirmed note does not run the command, and `margin-ask-true` runs it only when confirm is true; daemon CI and apps (Xcode) are both green on `5f2e35f` (check run `35770492947`); this does not prove a speaker or that a paper was read. Pull request 216 is https://github.com/aryateja2106/lecoder-watch/pull/216 on `cursor/subscription-ask-draft-e469`, base `cursor/subscription-confirm-ask-e469` (still `5f2e35fabf971041c385126251908c4a98f90794`), tip `b584480daf55c67070aa96a202b4f8138f2018d5`; the only added file is `scripts/check-subscription-ask-draft.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-ask-draft.sh` and `sh scripts/check-subscription-confirm-ask.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a later query of only the note titled `margin-ask-only` does not run the command, and confirm true creates `held-saved-ran`; daemon CI and apps (Xcode) are both green on `b584480` (check run `35771113323`); this does not prove a speaker or that a paper was read. Pull request 217 is https://github.com/aryateja2106/lecoder-watch/pull/217 on `cursor/subscription-saved-ask-e469`, base `cursor/subscription-ask-draft-e469` (still `b584480daf55c67070aa96a202b4f8138f2018d5`), tip `fa36116ad9aad19b40e50e1afe503e517de980c1`; the only added file is `scripts/check-subscription-saved-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-saved-ask.sh` and `sh scripts/check-subscription-ask-draft.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a further ask `margin-saved-ask` of only the saved note does not run the command, and `margin-saved-true` runs it only when confirm is true; daemon CI and apps (Xcode) are both green on `fa36116` (check run `35771883445`); this does not prove a speaker or that a paper was read. Pull request 218 is https://github.com/aryateja2106/lecoder-watch/pull/218 on `cursor/subscription-secret-reply-e469`, base `cursor/subscription-saved-ask-e469` (still `fa36116ad9aad19b40e50e1afe503e517de980c1`), tip `e07856f2750bcdec4dde54bf3ab772361d6bd998`; the only added file is `scripts/check-subscription-secret-reply.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-secret-reply.sh` and `sh scripts/check-subscription-saved-ask.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a user-subscription reply that names a pairing code stays held when confirm is true, writes no file, saves no note, and does not run; daemon CI and apps (Xcode) are both green on `e07856f` (check run `35772919892`); this does not prove a speaker or that a paper was read. Pull request 219 is https://github.com/aryateja2106/lecoder-watch/pull/219 on `cursor/subscription-spoken-ask-e469`, base `cursor/subscription-secret-reply-e469` (still `e07856f2750bcdec4dde54bf3ab772361d6bd998`), tip `fc2a13c5e8ded0a976913b44c0e65f7d2ab6a6aa`; the only added file is `scripts/check-subscription-spoken-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-spoken-ask.sh` and `sh scripts/check-subscription-secret-reply.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a local spoken note is asked through `llm.example`, confirm omitted does not run the command, confirm true runs it once, and a pairing-code ask or transcript stays held; daemon CI and apps (Xcode) are both green on `fc2a13c` (check run `35775132183`); this does not prove a speaker or that a paper was read. Pull request 220 is https://github.com/aryateja2106/lecoder-watch/pull/220 on `cursor/subscription-spoken-secret-reply-e469`, base `cursor/subscription-spoken-ask-e469` (still `fc2a13c5e8ded0a976913b44c0e65f7d2ab6a6aa`), tip `56729000c7117d0430fa710fa9778bdc6da763aa`; the only added file is `scripts/check-subscription-spoken-secret-reply.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-spoken-secret-reply.sh` and `sh scripts/check-subscription-spoken-ask.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts` and `knowledge.ts` were not edited; a spoken note asked through `llm.example` stays held when the model reply names a pairing code, even when confirm is true, and that reply is not saved; daemon CI and apps (Xcode) are both green on `5672900` (check run `35775998567`); this does not prove a speaker or that a paper was read. Pull request 221 is https://github.com/aryateja2106/lecoder-watch/pull/221 on `cursor/subscription-spoken-saved-ask-e469`, base `cursor/subscription-spoken-secret-reply-e469` (still `56729000c7117d0430fa710fa9778bdc6da763aa`), tip `9fea3cc93645072e61711e569313e6eadbb4a887`; the only added file is `scripts/check-subscription-spoken-saved-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the stub; `sh scripts/check-subscription-spoken-saved-ask.sh` and `sh scripts/check-subscription-spoken-secret-reply.sh` exited 0 on `127.0.0.1:8898` and after each nothing was listening on port 8898; `agent-note.ts`, `knowledge.ts`, and `server.ts` were not edited; after a held secret reply, asking only the note titled `spoken-cedar-hinge` through `llm.example` does not run the command when confirm is omitted and runs it once when confirm is true, and the knowledge list has no pairing-code title; daemon CI and apps (Xcode) are both green on `9fea3cc` (check run `35776596930`); this does not prove a speaker or that a paper was read. Pull request 222 is https://github.com/aryateja2106/lecoder-watch/pull/222 on `cursor/extracted-page-speak-e469`, base `cursor/subscription-spoken-saved-ask-e469` (still `9fea3cc93645072e61711e569313e6eadbb4a887`), tip `1f6def342d6fafbd5c15885523e680a494d3b689`; the only added file is `scripts/check-extracted-page-speak.sh`, which does not read `/proc` and on exit kills the daemon process group; `sh scripts/check-extracted-page-speak.sh` and `sh scripts/check-knowledge.sh` exited 0 on `127.0.0.1:8898` and after the new script nothing was listening on port 8898; `agent-note.ts`, `knowledge.ts`, and `server.ts` were not edited; `POST /knowledge` with a local PDF path and `speak: true` stores the extracted sentence `The oak margin names the extracted page.` under the title `Oak page` and a local `MESH_TTS` binary that exits 0 returns `spoken: true`; a remote `MESH_TTS` is not started and `spoken` is false; omitting `speak` leaves the binary idle; daemon CI and apps (Xcode) are both green on `1f6def3` (check run `35778325457`); this does not prove a speaker or that a paper was read. Pull request 223 is https://github.com/aryateja2106/lecoder-watch/pull/223 on `cursor/extracted-note-ask-e469`, base `cursor/extracted-page-speak-e469` (still `1f6def342d6fafbd5c15885523e680a494d3b689`), tip `3edd7de99a9eceeef4e5b18da6fc42b7ed8a21b5`; the only added file is `scripts/check-extracted-note-ask.sh`, which does not read `/proc` and on exit kills the daemon process group and the model stub; `sh scripts/check-extracted-note-ask.sh` and `sh scripts/check-extracted-page-speak.sh` exited 0 on `127.0.0.1:8898` and after the new script nothing was listening on port 8898; `agent-note.ts`, `knowledge.ts`, and `server.ts` were not edited; `POST /knowledge` with the oak page path and `speak: true` stores `The oak margin names the extracted page.` under the title `Oak page` and a local `MESH_TTS` that exits 0 returns `spoken: true`; asking `Oak page` with `build a reader` does not run when confirm is omitted and runs once when confirm is true; `modelClass` is `user-subscription`; the draft has no `sk-` and no `llm.example` userinfo; asking `Pairing page` with confirm true does not run, does not call the model, and writes no draft; daemon CI is green on `3edd7de` (check run `35781165080`); Apps (Xcode) is still running, so do not claim both jobs are green on `3edd7de`; this does not prove a speaker or that a paper was read. `sh scripts/check-note-omits-model-url.sh` exited 0 on `127.0.0.1:8898` at `890a704` and `lsof -nP -iTCP:8898 -sTCP:LISTEN` printed nothing afterward. That script no longer reads `/proc`. On exit it signals the daemon process group and the stub. `scripts/check-model-class.sh` was not edited on that commit, so the copy of that script on this branch is still the one that failed macOS CI. Pull request 207 tip `5f6d6b00b32421dcfe015becc378f2771d0eeff6` changes only `scripts/check-model-class.sh`. It no longer reads `/proc`. On exit it signals the daemon process group and the stub. `sh scripts/check-model-class.sh` exited 0, then `sh scripts/check-second-reply-draft.sh` exited 0 on `127.0.0.1:8898`. After each, `lsof -nP -iTCP:8898 -sTCP:LISTEN` printed nothing. A SIGTERM during the model-class check also left 8898 free. Daemon CI and apps (Xcode) are both green on `5f6d6b0` (check run `35759586722`). The failure on `48f1970` stays a failure. This later tip is the fix.
- **AND** the agent records that Apps (Xcode) failed on `48f1970` (check run `35757430003`). Self-checks failed because `scripts/check-model-class.sh` read `/proc`, which macOS does not have, and port 8898 stayed in use. Daemon CI stayed green. Do not claim both jobs are green on `48f1970`. The fix is not on that tip.
- **AND** the agent does not claim both jobs are green on `48f1970`
- **AND** the agent does not claim a speaker or that a paper was read

### Requirement: A subscription note can be drafted

Pull request 209 SHALL add only `scripts/check-subscription-note.sh`. That script MUST NOT read `/proc`. On exit it SHALL signal the daemon process group and the stub. An allowed ask to `http://llm.example:<stub>/v1` SHALL return `modelClass` `user-subscription`, the stub URL SHALL have no userinfo, and the note body SHALL be the model reply only. `agent-note.ts`, `knowledge.ts`, and `server.ts` were not edited. The coordinator re-ran `sh scripts/check-subscription-note.sh` and `sh scripts/check-note-omits-model-url.sh` on `127.0.0.1:8898` at `9c0f8cf` and both exited 0. After the subscription check, port 8898 was free. The gateway key was unset. An agent MUST NOT add a second `/knowledge` route and MUST NOT call the Vercel AI Gateway. An agent MUST NOT claim both jobs are green on `9c0f8cf`. Daemon CI is green on `9c0f8cf` (check run `35759702609`). Apps (Xcode) is still running on that run. Do not claim both jobs are green on `9c0f8cf`. This tip merges `0a1b0e2`, so it includes the model-class port fix at `5f6d6b0`. Do not claim that Xcode passes. This does not prove a speaker or that a paper was read.

#### Scenario: A subscription ask stores the reply only

- **WHEN** an allowed ask uses `http://llm.example:<stub>/v1`
- **THEN** `modelClass` is `user-subscription`
- **AND** the stub URL has no userinfo
- **AND** the note body is the model reply only

#### Scenario: The subscription check leaves port 8898 free

- **WHEN** `sh scripts/check-subscription-note.sh` exits 0 on `127.0.0.1:8898`
- **THEN** port 8898 is free

#### Scenario: Daemon-only CI on the subscription note is not both jobs green

- **WHEN** `sh scripts/check-subscription-note.sh` and `sh scripts/check-note-omits-model-url.sh` pass on `127.0.0.1:8898` at `9c0f8cf`
- **THEN** the agent records that both checks exited 0 and that daemon CI is green on `9c0f8cf` (check run `35759702609`) while apps (Xcode) is still running
- **AND** the agent does not claim both jobs are green on `9c0f8cf`
- **AND** the agent records that daemon CI and apps (Xcode) are both green on `bbff8da` (check run `35760223545`)
- **AND** the agent keeps the port proofs on `5f6d6b0` and `890a704`
- **AND** the agent does not claim a speaker or that a paper was read
