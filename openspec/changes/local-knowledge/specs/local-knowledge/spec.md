# Local knowledge

One job: read a local PDF, write a note, leave it for a later agent, and optionally hand the note text to a TTS binary the user already has.

## ADDED Requirements

### Requirement: A local PDF becomes one note on disk

The daemon SHALL accept a filesystem path to a PDF, read that file on the machine, and write exactly one note under the daemon state directory. The note directory SHALL be mode 700. The note file SHALL be unreadable by other users.

The state directory is `MESHD_STATE` when that variable is set, and `~/.mesh` otherwise. Notes live in a `knowledge` directory inside it.

#### Scenario: Spare daemon ingests a PDF

- **WHEN** a client posts a local PDF path to the knowledge route
- **THEN** a note file exists under the state directory's `knowledge` directory
- **AND** that directory is mode 700
- **AND** the note records the PDF's title

#### Scenario: The path is not a local file

- **WHEN** the path is an `http` or `https` URL, or names something that is not a PDF file
- **THEN** the daemon SHALL reject the request
- **AND** it SHALL NOT write a note

### Requirement: A later request can list the title

A second request SHALL list the note's title so a later agent can find what was stored. The list is titles (and ids). The PDF bytes are not returned.

#### Scenario: Listing after a write

- **WHEN** a note has been written and a client requests the knowledge list
- **THEN** the response includes that note's title

### Requirement: The note stays on the machine

Writing or listing a note SHALL NOT send the PDF, the note body, the title, or a summary off the machine. This route has no Supabase client and does not call Jev.

#### Scenario: Ingest on a spare daemon

- **WHEN** the spare daemon accepts a PDF and lists the note
- **THEN** the daemon process has no connection to Supabase

### Requirement: Speech is an optional local handoff

The daemon MAY hand the note text to a TTS binary the user already has, and only when the request asks for speech and `MESH_TTS` names that binary. The daemon SHALL NOT download a speech program. The note SHALL still be written when speech is not asked for or the binary is absent.

#### Scenario: Speech was not requested

- **WHEN** a client posts a PDF path without asking for speech
- **THEN** the note is written
- **AND** no TTS process is started
