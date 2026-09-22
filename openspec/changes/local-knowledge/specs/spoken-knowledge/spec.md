## Purpose

Local notes from a PDF or a local speech-in binary stay under `MESHD_STATE`, an existing note's body can be replaced in the same file, a local `MESH_STT` transcript can replace that body, a local `MESH_TTS` binary can speak that replaced note, optional local TTS speaks a note, a held app draft waits for confirm before any further command, a replaced note that asks to send a pairing code or copy hosts.json stays on hold, a spoken replace drafts that new body to `held-note.txt`, a spoken replace with `speak: true` drafts that new transcript to a held file, `GET /knowledge?q=` matches a title or a body and returns only `{ id, title }`, and a local `q` on `POST /agent-note` selects one note when `id` is absent. A spoken note is a local binary transcript or a local TTS exit code. Notes stay on the machine. Nothing from the note is stored in Supabase. Pull request 187, pull request 189, pull request 193, pull request 195, and pull request 197 do not prove a microphone or a speaker. Pull request 192 (tip `6faf3f3`) already named pull request 189. Pull request 194 (tip `cfe2b17`) already named pull request 193.

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

When `id` is absent, `POST /agent-note` SHALL accept a local `q` and SHALL select with `listNotes`. One match SHALL draft one relative file. That file SHALL be mode 600 and SHALL NOT be executed. Zero matches MUST answer 404. Several matches MUST answer 409. A remote or empty `q` MUST answer 400. Those results MUST NOT call the model. The hold SHALL match `textMovesSecret` for a pairing code, hosts.json, a mesh token, `.mesh/token`, and the upload/send sentence, and MUST NOT import `route.ts` or `filter.ts`. `id` without `q` SHALL still draft. `server.ts` was not edited. This behavior is pull request 197. The typecheck and `sh scripts/check-query-note-draft.sh` on `127.0.0.1:8898` at `e11483d` both exited 0 with the gateway key unset. Daemon CI is green on `e11483d`. Apps (Xcode) is still running on that tip (run `35739420177`). An agent MUST NOT claim both jobs are green on `e11483d`, MUST NOT rebuild this draft, MUST NOT add a second `/knowledge` route, and MUST NOT call the Vercel AI Gateway. This does not prove a microphone or a speaker. Pull request 195 stays the local note search at `1238daa`, with daemon CI and Xcode CI both green (check run `35736830546`).

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
- **THEN** the agent records that spare-daemon check, that daemon CI is green on `e11483d`, and that apps (Xcode) is still running on run `35739420177`
- **AND** the agent does not claim a microphone or a speaker was proven
- **AND** the agent does not claim both CI jobs are green on `e11483d`
