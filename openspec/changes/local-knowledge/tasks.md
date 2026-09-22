# Tasks

No task in this change needs Arya's physical iPhone, Apple Watch, microphone, or speaker. Agents cannot prove a physical microphone or speaker.

## 1. Re-check the finished drafts

- [ ] 1.1 Re-check local PDF notes on pull request 139 before touching any knowledge module. Record the current `headRefOid`. Expected tip when this handoff was written: `9d2827bb0a216cc0f0df20da44da804788c3eba3`. Leave the notes where they are. Do not add another `knowledge.ts` from this change. *Verify by running:* `gh pr view 139 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`
- [ ] 1.2 Re-check spoken-out via a local `MESH_TTS` binary on pull request 145. Record the current `headRefOid`. Expected tip when this handoff was written: `ea86b77baf5e9902087a1aecc9f2bcf181d00bd7`. Do not start another spoken-out path. *Verify by running:* `gh pr view 145 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`
- [ ] 1.3 Re-check the note to a held file on pull request 154. Record the current `headRefOid`. Expected tip: `cba3ac7b70643b155807f789d42a0b525fcab8ae`. A missing note does not call the model. An unconfirmed command does not run. Do not start another held-file draft. *Verify by running:* `gh pr view 154 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`
- [ ] 1.4 Re-check the route-gated draft on pull request 160. Record the current `headRefOid`. Expected tip: `4c8a73a485cfb7acd6d4c83d577a2cf19f8ab29c`. Jev chooses a route. It does not write the reply. No live gateway call. Do not start another route-gated draft. *Verify by running:* `gh pr view 160 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`
- [ ] 1.5 Re-check spoken-in via a local `MESH_STT` binary on pull request 162. Record the current `headRefOid`. Expected tip: `4e14cab8c9a5edef4f509b7096fcf238f02ffc2d`. A remote URL does not run. Do not start a second speech-in path. *Verify by running:* `gh pr view 162 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`
- [ ] 1.6 Re-check the in-place note replace on pull request 174 before touching `knowledge.ts`. Record the current `headRefOid`. Expected tip when this handoff was written: `426d66d7ae016a67b66b809a7cb4a10aaa300460` on `cursor/knowledge-note-update-e469`. `POST /knowledge/:id` replaces that note's body in the same file. The list stays `{ id, title }`. A missing id creates nothing. A remote URL does not write. That pull request did not edit `server.ts`. Daemon CI and Xcode CI were green. Do not rebuild the replace. *Verify by running:* `gh pr view 174 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`
- [ ] 1.7 Re-check the replaced-note draft on pull request 176. Record the current `headRefOid`. Expected tip when this handoff was written: `ff4d633cf15c69776a314c79a4c243d39bf5cd31` on `cursor/updated-note-draft-e469`. After that replace, the agent-note path drafts the new body. The held file is mode 600 and is not executed. A missing id does not call the model. An unconfirmed command stays unrun. Daemon CI and Xcode CI were green. `sh scripts/check-updated-note-draft.sh` passed on `127.0.0.1:8898`. Do not rebuild that draft. *Verify by running:* `gh pr view 176 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`

## 2. Keep this change to spec files

- [ ] 2.1 Confirm the branch diff against `origin/main` contains only `openspec/changes/local-knowledge/`. Do not edit `Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `install/payload/meshd/pair.ts`, or `project.yml` in this pull request. *Verify by running:* `git diff --name-only origin/main`
- [ ] 2.2 Confirm the shared contracts and pairing code are absent from the diff. *Verify by running:* `git diff --name-only origin/main -- Shared/Models.swift Shared/MeshClient.swift install/payload/meshd/server.ts install/payload/meshd/pair.ts project.yml`
- [ ] 2.3 Confirm this change did not add a knowledge module, a note-update path, a replaced-note draft, a TTS path, an STT path, a held-file check, a route-gated draft experiment, or a second speech-in path. *Verify by running:* `git diff --name-only origin/main -- install/payload/meshd scripts experiments`

## 3. server.ts registration rule for a later agent

Do not edit `server.ts` in this pull request. These tasks are for a later agent continuing the product work, not for this handoff. On `origin/main`, `/knowledge` is unregistered. The knowledge branch already registers it once. Do not add a second `/knowledge` route. Pull request 174 and pull request 176 did not edit `server.ts`.

- [ ] 3.1 On the tree being edited, check whether knowledge routes are already registered in `install/payload/meshd/server.ts`. On `origin/main` at this handoff's base, `/knowledge` is unregistered. The knowledge branch already registers it once. If it is registered, say so and do not add a second `/knowledge` route. *Verify by running:* `rg -n 'handleKnowledge|/knowledge' install/payload/meshd/server.ts || echo 'no knowledge route on this tree'`
- [ ] 3.2 If the routes are missing, register the existing handler only when no other agent holds `server.ts`. One registration. Do not invent a second knowledge route table, and do not add a second `/knowledge` route on a tree that already has one. *Verify by running:* `rg -n 'handleKnowledge' install/payload/meshd/server.ts` and confirm a single call site after the edit.
- [ ] 3.3 Prove the spare daemon on a free port with `MESHD_STATE` pointed at a temp directory. Do not use a real home directory. Do not restart a live daemon on 8899. *Verify by running:* the knowledge check from pull request 139 (`sh scripts/check-knowledge.sh`) against that spare daemon.

## 4. Later pickup constraints (product work outside this PR)

These tasks are for a later agent. This handoff does not implement them.

- [ ] 4.1 Notes stay under `MESHD_STATE` (otherwise `~/.mesh`). Directory mode 700, file mode 600. No Supabase client. Knowledge bodies never go to the cloud. *Verify by running:* `sh scripts/check-knowledge.sh` (or the equivalent check on the finished draft tip) and confirm the temp state directory holds the note.
- [ ] 4.2 A draft file is not executed. A further command waits for confirm. Reuse pull request 154, pull request 160, and the replaced-note draft on pull request 176. Do not rebuild them. *Verify by running:* `sh scripts/check-held-app-file.sh`, `sh scripts/check-note-route-draft.sh`, and `sh scripts/check-updated-note-draft.sh` on those tips.
- [ ] 4.3 Spoken-out stays on pull request 145 (`MESH_TTS`). Spoken-in stays on pull request 162 (`MESH_STT`). A remote URL does not run. Do not start a second speech-in path. *Verify by running:* `sh scripts/check-knowledge-speak.sh` and `sh scripts/check-spoken-note-in.sh` on those tips.
- [ ] 4.4 Do not call the AI Gateway. Do not commit an API key, a JWT, or a database URL. Jev chooses a route and does not write the reply. *Verify by running:* `if git grep -n -E 'eyJ[A-Za-z0-9_-]{8,}|postgresql://|AI_GATEWAY_API_KEY=' -- openspec/changes/local-knowledge; then exit 1; else echo 'no keys in the change'; fi`
- [ ] 4.5 Leave `openspec/changes/local-brain-and-harness/` as a spike. Any later harness adapter is time-boxed beside the daemon and points at existing session routes. If the upstream preview breaks, stop and write what broke into that proposal's `tasks.md`. Do not replace `meshd`. *Verify by running:* `test -f openspec/changes/local-brain-and-harness/proposal.md && echo 'harness remains a spike'`
- [ ] 4.6 Physical microphone or speaker proof is handed back to a human. Agents cannot prove it. A spoken note is a local binary transcript or a local TTS exit code. Mark any such check as human-only. *Verify by running:* `rg -n 'physical microphone|local binary transcript' openspec/changes/local-knowledge/tasks.md`
- [ ] 4.7 Leave the in-place note replace on pull request 174. `POST /knowledge/:id` replaces that note's body in the same file. The list stays `{ id, title }`. A missing id creates nothing. A remote URL does not write. Notes stay on the machine. Nothing from the note is stored in Supabase. Do not rebuild it, and do not add a second `/knowledge` route. *Verify by running:* `sh scripts/check-knowledge-update.sh` on that tip.

## 5. Validate the spec

- [ ] 5.1 Validate the change in strict mode. *Verify by running:* `openspec validate local-knowledge --type change --strict`
- [ ] 5.2 Show the change status and confirm `tasks` is done. *Verify by running:* `openspec status --change local-knowledge`
- [ ] 5.3 Confirm the diff against `origin/main` is only `openspec/changes/local-knowledge/`. *Verify by running:* `git diff --name-only origin/main`
