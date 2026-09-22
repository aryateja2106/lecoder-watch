## Why

A spoken knowledge base is a note the person can ask for later, not a second copy of the mesh. The owner's boundary for this slice is the same as the account slice: the PDF and the note stay on the machine, and a held app draft waits for confirm before any further command. The person this is for does not configure SSH keys, port forwarding, a VPN, or a speech cloud. An executing agent does not stand in for a physical microphone or speaker.

## What Changes

- Add a contract other agents can execute for the spoken knowledge base and the held app draft, without a second implementation of work that already exists on draft pull requests.
- State that notes live under `MESHD_STATE` (otherwise `~/.mesh`), in a mode-700 knowledge directory. Knowledge bodies never go to Supabase or to any other cloud store.
- State that speech-out uses a local `MESH_TTS` binary the user already has, and speech-in uses a local `MESH_STT` binary. A remote URL does not run. Do not start a second speech-in path.
- State that Jev chooses a route and does not write the reply. A live gateway call is out of this change. A draft file is not executed. A further command waits for confirm.
- Keep this change to spec files. Do not edit `Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `install/payload/meshd/pair.ts`, or `project.yml` in this pull request.

No product code lands here. The finished drafts stay the implementation.

## Capabilities

### New Capabilities

- `spoken-knowledge`: Local PDF notes under `MESHD_STATE`, optional local TTS and STT binaries, and the held app draft that stops for confirm. Knowledge bodies stay on the machine.
- `local-knowledge-gates`: The finished draft tips, the ban on rebuilding them, the `server.ts` registration rule, the ban on keys and gateway calls, and the rule that agents cannot prove a physical microphone or speaker.

### Modified Capabilities

- None. `terminal-sessions` stays as it is. `openspec/changes/local-brain-and-harness/` stays a spike. Do not merge a harness in this change.

## Non-goals

- Rebuilding local PDF notes (pull request 139), spoken-out via a local `MESH_TTS` binary (pull request 145), the note-to-held-file draft (pull request 154, tip `cba3ac7`), the route-gated draft (pull request 160, tip `4c8a73a`), or spoken-in via a local `MESH_STT` binary (pull request 162, tip `4e14cab`). Those drafts are the implementation. Re-check each pull request tip before touching the same files, and do not open a second copy.
- Editing `install/payload/meshd/server.ts` in this pull request. A later agent checks whether knowledge routes are already registered. If they are, that agent says so and forbids a second route. If they are not, one later task may register them only when no other agent holds `server.ts`.
- Calling the Vercel AI Gateway, including `POST https://ai-gateway.vercel.sh/v1/evaluate`. Jev chooses a route. It does not write the reply.
- Committing an API key, a JWT, or a database URL. Knowledge bodies never go to Supabase.
- Starting a second speech-in path beside pull request 162. A remote URL does not run.
- Merging the local-brain harness. That proposal stays a spike. Do not replace `meshd`.
- Editing `Shared/Models.swift`, `Shared/MeshClient.swift`, `project.yml`, or `pair.ts`.
- Physical proof that a microphone or speaker works. Agents cannot do that.

## Impact

- This change adds only `openspec/changes/local-knowledge/`.
- Finished drafts stay where they are: local PDF notes on pull request 139 (`cursor/local-knowledge-e469`, tip `9d2827b`), spoken-out on pull request 145 (`cursor/spoken-note-e469`, tip `ea86b77`), note to a held file on pull request 154 (`cursor/note-to-app-e469`, tip `cba3ac7`), route-gated draft on pull request 160 (`cursor/note-route-draft-e469`, tip `4c8a73a`), and spoken-in on pull request 162 (`cursor/spoken-note-in-e469`, tip `4e14cab`). Do not start another copy of any of them.
- On `origin/main` at the tip this change branched from, knowledge routes are not registered in `server.ts`. Pull request 139 already registers `/knowledge` on its tip. A later agent re-checks before any second registration.
- Account tables, the heartbeat project, and pairing stay untouched. The company does not host the coding model. Jev only picks a route.
