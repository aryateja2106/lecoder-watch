# Tasks

No task in this change needs Arya's physical iPhone, Apple Watch, microphone, or speaker. Agents cannot prove a physical microphone or speaker.

## 1. Re-check the finished drafts

- [ ] 1.1 Re-check local PDF notes on pull request 139 before touching any knowledge module. Record the current `headRefOid`. Expected tip when this handoff was written: `9d2827bb0a216cc0f0df20da44da804788c3eba3`. Leave the notes where they are. Do not add another `knowledge.ts` from this change. *Verify by running:* `gh pr view 139 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`
- [ ] 1.2 Re-check spoken-out via a local `MESH_TTS` binary on pull request 145. Record the current `headRefOid`. Expected tip when this handoff was written: `ea86b77baf5e9902087a1aecc9f2bcf181d00bd7`. Do not start another spoken-out path. *Verify by running:* `gh pr view 145 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`
- [ ] 1.3 Re-check the note to a held file on pull request 154. Record the current `headRefOid`. Expected tip: `cba3ac7b70643b155807f789d42a0b525fcab8ae`. A missing note does not call the model. An unconfirmed command does not run. Do not start another held-file draft. *Verify by running:* `gh pr view 154 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`
- [ ] 1.4 Re-check the route-gated draft on pull request 160. Record the current `headRefOid`. Expected tip: `4c8a73a485cfb7acd6d4c83d577a2cf19f8ab29c`. Jev chooses a route. It does not write the reply. No live gateway call. Do not start another route-gated draft. *Verify by running:* `gh pr view 160 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`
- [ ] 1.5 Re-check spoken-in via a local `MESH_STT` binary on pull request 162. Record the current `headRefOid`. Expected tip: `4e14cab8c9a5edef4f509b7096fcf238f02ffc2d`. A remote URL does not run. Do not start a second speech-in path. *Verify by running:* `gh pr view 162 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`

## 2. Keep this change to spec files

- [ ] 2.1 Confirm the branch diff against `origin/main` contains only `openspec/changes/local-knowledge/`. Do not edit `Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `install/payload/meshd/pair.ts`, or `project.yml` in this pull request. *Verify by running:* `git diff --name-only origin/main`
- [ ] 2.2 Confirm the shared contracts and pairing code are absent from the diff. *Verify by running:* `git diff --name-only origin/main -- Shared/Models.swift Shared/MeshClient.swift install/payload/meshd/server.ts install/payload/meshd/pair.ts project.yml`
- [ ] 2.3 Confirm this change did not add a knowledge module, a TTS path, an STT path, a held-file check, a route-gated draft experiment, or a second speech-in path. *Verify by running:* `git diff --name-only origin/main -- install/payload/meshd scripts experiments`

## 3. server.ts registration rule for a later agent

Do not edit `server.ts` in this pull request. These tasks are for a later agent continuing the product work, not for this handoff.

- [ ] 3.1 On the tree being edited, check whether knowledge routes are already registered in `install/payload/meshd/server.ts`. On `origin/main` at this handoff's base they are not. On pull request 139's tip they are. If they are registered, say so and forbid a second route. *Verify by running:* `rg -n 'handleKnowledge|/knowledge' install/payload/meshd/server.ts || echo 'no knowledge route on this tree'`
- [ ] 3.2 If the routes are missing, register the existing handler only when no other agent holds `server.ts`. One registration. Do not invent a second knowledge route table. *Verify by running:* `rg -n 'handleKnowledge' install/payload/meshd/server.ts` and confirm a single call site after the edit.
- [ ] 3.3 Prove the spare daemon on a free port with `MESHD_STATE` pointed at a temp directory. Do not use a real home directory. Do not restart a live daemon on 8899. *Verify by running:* the knowledge check from pull request 139 (`sh scripts/check-knowledge.sh`) against that spare daemon.

## 4. Later pickup constraints (product work outside this PR)

These tasks are for a later agent. This handoff does not implement them.

- [ ] 4.1 Notes stay under `MESHD_STATE` (otherwise `~/.mesh`). Directory mode 700, file mode 600. No Supabase client. Knowledge bodies never go to the cloud. *Verify by running:* `sh scripts/check-knowledge.sh` (or the equivalent check on the finished draft tip) and confirm the temp state directory holds the note.
- [ ] 4.2 A draft file is not executed. A further command waits for confirm. Reuse pull request 154 and pull request 160. Do not rebuild them. *Verify by running:* `sh scripts/check-held-app-file.sh` and `sh scripts/check-note-route-draft.sh` on those tips.
- [ ] 4.3 Spoken-out stays on pull request 145 (`MESH_TTS`). Spoken-in stays on pull request 162 (`MESH_STT`). A remote URL does not run. Do not start a second speech-in path. *Verify by running:* `sh scripts/check-knowledge-speak.sh` and `sh scripts/check-spoken-note-in.sh` on those tips.
- [ ] 4.4 Do not call the AI Gateway. Do not commit an API key, a JWT, or a database URL. Jev chooses a route and does not write the reply. *Verify by running:* `if git grep -n -E 'eyJ[A-Za-z0-9_-]{8,}|postgresql://|AI_GATEWAY_API_KEY=' -- openspec/changes/local-knowledge; then exit 1; else echo 'no keys in the change'; fi`
- [ ] 4.5 Leave `openspec/changes/local-brain-and-harness/` as a spike. Any later harness adapter is time-boxed beside the daemon and points at existing session routes. If the upstream preview breaks, stop and write what broke into that proposal's `tasks.md`. Do not replace `meshd`. *Verify by running:* `test -f openspec/changes/local-brain-and-harness/proposal.md && echo 'harness remains a spike'`
- [ ] 4.6 Physical microphone or speaker proof is handed back to a human. Agents cannot prove it. Mark any such check as human-only. *Verify by running:* `rg -n 'physical microphone|physical speaker|Arya' openspec/changes/local-knowledge/tasks.md`

## 5. Validate the spec

- [ ] 5.1 Validate the change in strict mode. *Verify by running:* `openspec validate local-knowledge --type change --strict`
- [ ] 5.2 Show the change status and confirm `tasks` is done. *Verify by running:* `openspec status --change local-knowledge`
- [ ] 5.3 Confirm the diff against `origin/main` is only `openspec/changes/local-knowledge/`. *Verify by running:* `git diff --name-only origin/main`
