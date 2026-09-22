## Purpose

Local notes from a PDF or a local speech-in binary stay under `MESHD_STATE`, an existing note's body can be replaced in the same file, a local `MESH_STT` transcript can replace that body, optional local TTS speaks a note, a held app draft waits for confirm before any further command, and a replaced note that asks to send a pairing code or copy hosts.json stays on hold. A spoken note is a local binary transcript or a local TTS exit code. Notes stay on the machine. Nothing from the note is stored in Supabase.

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

When a note already exists, `POST /knowledge/:id` SHALL replace that note's body in the same file under the knowledge directory. The list SHALL stay `{ id, title }` for each note. A missing id SHALL create nothing. A remote URL SHALL NOT write. Notes stay on the machine. Nothing from the note is stored in Supabase. This behavior is pull request 174. An agent MUST NOT add a second replace path, and MUST NOT add a second `/knowledge` route. On `origin/main`, `/knowledge` is unregistered. The knowledge branch already registers it once.

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
