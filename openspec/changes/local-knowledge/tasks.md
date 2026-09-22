# Tasks

One job: read a local PDF, write a note, leave it for a later agent, and optionally hand the note text to a TTS binary the user already has.

- [x] **Read a local PDF path and write one note.** The note file lives under `$MESHD_STATE/knowledge/` (or `~/.mesh/knowledge/`). The directory is mode 700 and the file is mode 600. *Verify with `sh scripts/check-knowledge.sh`.*
- [x] **List the title.** A second request to the same daemon returns that note's title. *Same check.*
- [x] **Leave the note on the machine.** The handler does not call Supabase and does not call Jev. The check fails if the spare daemon opens a non-loopback socket. *Same check.*
- [x] **Optional local speech.** `speak: true` plus `MESH_TTS` set to a binary the user already has sends the note text to that process. The note is still written when speech is not asked for.
