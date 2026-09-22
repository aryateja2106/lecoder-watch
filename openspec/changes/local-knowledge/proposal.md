# Local knowledge

## Why

A spoken knowledge base is a note the person can ask for later, not a second copy of the mesh. The PDF already sits on the machine. The note has to sit there too, where a later agent can read it, and nowhere else.

## What changes

`meshd` grows one local job. It reads a PDF path on disk, writes one note under the daemon state directory (`MESHD_STATE`, otherwise `~/.mesh`), and lists that note's title. The note directory is mode 700. The module does not open a network connection.

Optionally, when the person asks and `MESH_TTS` names a binary they already have, the daemon hands that binary the note text on stdin. The note is written either way. No TTS program is downloaded.

## Non-goals

- An account, a login route, or any Supabase client in the daemon.
- Sending the PDF, the note body, or a summary to Jev or anywhere else.
- Merging the local-brain harness. That proposal stays a spike.
- Replacing the existing sqlite `/kb` memory. This note is a file a later agent can open.

## Impact

- `install/payload/meshd/knowledge.ts` owns the note files and the `/knowledge` handler.
- `install/payload/meshd/server.ts` registers that handler and nothing about accounts.
- `scripts/check-knowledge.sh` proves the spare daemon on port 8898.
