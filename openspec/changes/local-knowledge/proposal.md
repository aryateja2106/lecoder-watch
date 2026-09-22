## Why

A spoken knowledge base is a note the person can ask for later, not a second copy of the mesh. The owner's boundary for this slice is the same as the account slice: the PDF and the note stay on the machine, and a held app draft waits for confirm before any further command. The person this is for does not configure SSH keys, port forwarding, a VPN, or a speech cloud. An executing agent does not stand in for a physical microphone or speaker.

## What Changes

- Add a contract other agents can execute for the spoken knowledge base and the held app draft, without a second implementation of work that already exists on draft pull requests.
- Name the in-place note replace and the replaced-note draft as finished. `POST /knowledge/:id` replaces that note's body in the same file. After that replace, the agent-note path drafts the new body. Do not rebuild either slice.
- Name the replaced-note hold and the spoken note replace as finished. A replaced note that asks to send a pairing code or copy hosts.json stays on hold and the model is not called. "summarize this paper" still drafts the new body. `POST /knowledge/:id` accepts `{ audio }`, and a local `MESH_STT` transcript replaces that note body. Do not rebuild either slice. Do not add a second `/knowledge` route.
- Name the spoken-note draft as finished. Pull request 187 adds only `scripts/check-spoken-note-draft.sh`. A local `MESH_STT` transcript replaces one note and the agent-note path drafts that new body to `held-note.txt`, mode 600, unexecuted. A pairing-code transcript and a hosts.json transcript stay on hold and the loopback model is not called. "summarize this paper" drafts the new body. A missing id does not call the model. A remote audio path does not write. The check passed on `127.0.0.1:8898` with the gateway key unset. Daemon CI is green. Apps (Xcode) was still running. This does not prove a microphone. Do not rebuild that check. Do not add a second `/knowledge` route.
- State that notes live under `MESHD_STATE` (otherwise `~/.mesh`), in a mode-700 knowledge directory. Knowledge bodies never go to Supabase or to any other cloud store.
- State that speech-out uses a local `MESH_TTS` binary the user already has, and speech-in uses a local `MESH_STT` binary. A remote URL does not run. Do not start a second speech-in path.
- State that Jev chooses a route and does not write the reply. A live gateway call is out of this change. A draft file is not executed. A further command waits for confirm.
- Keep this change to spec files. Do not edit `Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `install/payload/meshd/pair.ts`, or `project.yml` in this pull request.

No product code lands here. The finished drafts stay the implementation.

## Capabilities

### New Capabilities

- `spoken-knowledge`: Local PDF notes under `MESHD_STATE`, an in-place body replace, optional local TTS and STT binaries, the held app draft that stops for confirm, the agent-note draft of a replaced body, the hold when that body asks to send a pairing code or copy hosts.json, the local-audio replace of an existing note, and the spoken-note draft that writes that new body to `held-note.txt`. Knowledge bodies stay on the machine. Nothing from the note is stored in Supabase.
- `local-knowledge-gates`: The finished draft tips, including the note update, the replaced-note draft, the replaced-note hold, the spoken note replace, and the spoken-note draft, the ban on rebuilding them, the `server.ts` registration rule, the ban on keys and gateway calls, and the rule that agents cannot prove a physical microphone or speaker.

### Modified Capabilities

- None. `terminal-sessions` stays as it is. `openspec/changes/local-brain-and-harness/` stays a spike. Do not merge a harness in this change.

## Non-goals

- Rebuilding local PDF notes (pull request 139), spoken-out via a local `MESH_TTS` binary (pull request 145), the note-to-held-file draft (pull request 154, tip `cba3ac7`), the route-gated draft (pull request 160, tip `4c8a73a`), spoken-in via a local `MESH_STT` binary (pull request 162, tip `4e14cab`), the in-place note replace (pull request 174, tip `426d66d7`), the replaced-note draft (pull request 176, tip `ff4d633c`), the replaced-note hold (pull request 182, tip `56d8ae7`), the spoken note replace (pull request 183, tip `52ce629`), or the spoken-note draft (pull request 187, tip `0baf377`). Those drafts are the implementation. Re-check each pull request tip before touching the same files, and do not open a second copy.
- Editing `install/payload/meshd/server.ts` in this pull request. On `origin/main`, `/knowledge` is unregistered. The knowledge branch already registers it once. A later agent checks the tree being edited. If `/knowledge` is already registered, that agent says so and does not add a second `/knowledge` route. If it is not, one later task may register the existing handler only when no other agent holds `server.ts`. Pull request 174 and pull request 176 did not edit `server.ts`. Pull request 182 and pull request 183 did not edit `server.ts`. On the spoken-replace tip, `server.ts` still calls `handleKnowledge` once. Pull request 187 did not edit `server.ts`. It adds only `scripts/check-spoken-note-draft.sh`.
- Calling the Vercel AI Gateway, including `POST https://ai-gateway.vercel.sh/v1/evaluate`. Jev chooses a route. It does not write the reply.
- Committing an API key, a JWT, or a database URL. Knowledge bodies never go to Supabase.
- Starting a second speech-in path beside pull request 162. A remote URL does not run.
- Merging the local-brain harness. That proposal stays a spike. Do not replace `meshd`.
- Editing `Shared/Models.swift`, `Shared/MeshClient.swift`, `project.yml`, or `pair.ts`.
- Physical proof that a microphone or speaker works. Agents cannot do that. A spoken note is a local binary transcript or a local TTS exit code.

## Impact

- This change adds only `openspec/changes/local-knowledge/`.
- Finished drafts stay where they are: local PDF notes on pull request 139 (`cursor/local-knowledge-e469`, tip `9d2827b`), spoken-out on pull request 145 (`cursor/spoken-note-e469`, tip `ea86b77`), note to a held file on pull request 154 (`cursor/note-to-app-e469`, tip `cba3ac7`), route-gated draft on pull request 160 (`cursor/note-route-draft-e469`, tip `4c8a73a`), spoken-in on pull request 162 (`cursor/spoken-note-in-e469`, tip `4e14cab`), the in-place note replace on pull request 174 (`cursor/knowledge-note-update-e469`, tip `426d66d7`), the replaced-note draft on pull request 176 (`cursor/updated-note-draft-e469`, tip `ff4d633c`), the replaced-note hold on pull request 182 (`cursor/updated-note-hold-e469`, tip `56d8ae7`), the spoken note replace on pull request 183 (`cursor/spoken-note-replace-e469`, tip `52ce629`), and the spoken-note draft on pull request 187 (`cursor/spoken-note-draft-e469`, tip `0baf377`). Do not start another copy of any of them.
- On `origin/main`, `/knowledge` is unregistered. The knowledge branch already registers it once. Do not add a second `/knowledge` route. Notes stay on the machine. Nothing from the note is stored in Supabase.
- Account tables, the heartbeat project, and pairing stay untouched. The company does not host the coding model. Jev only picks a route.
