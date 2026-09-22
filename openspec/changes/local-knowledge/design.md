## Context

See proposal.md for why. The spoken knowledge base and the held app draft already have draft implementations on open pull requests. This design does not replace those drafts. It names them so the next agent continues without rebuilding finished work.

| Slice | Where it already lives | Tip verified with `gh` on 2026-09-22 |
|---|---|---|
| Local PDF notes under `MESHD_STATE`, `/knowledge` registered on that tip | PR 139, branch `cursor/local-knowledge-e469` | `9d2827b` (`9d2827bb0a216cc0f0df20da44da804788c3eba3`) |
| Spoken-out via a local `MESH_TTS` binary | PR 145, branch `cursor/spoken-note-e469` | `ea86b77` (`ea86b77baf5e9902087a1aecc9f2bcf181d00bd7`) |
| Note to a held file; missing note does not call the model; unconfirmed command does not run | PR 154, branch `cursor/note-to-app-e469` | `cba3ac7` (`cba3ac7b70643b155807f789d42a0b525fcab8ae`) |
| Route-gated draft: Jev chooses a route, does not write the reply, no live gateway call | PR 160, branch `cursor/note-route-draft-e469` | `4c8a73a` (`4c8a73a485cfb7acd6d4c83d577a2cf19f8ab29c`) |
| Spoken-in via a local `MESH_STT` binary; a remote URL does not run | PR 162, branch `cursor/spoken-note-in-e469` | `4e14cab` (`4e14cab8c9a5edef4f509b7096fcf238f02ffc2d`) |

On `origin/main` at `5579efd` (the base of this change), `install/payload/meshd/server.ts` has no knowledge route. Pull request 139 already registers the handler on its tip. A later agent re-checks before any second registration.

`openspec/changes/local-brain-and-harness/` stays a spike. `meshd` stays the session layer. The model is one the user configured. Jev only picks a route. The company does not host the coding model.

Stakeholders: the person who already has a PDF and (optionally) local speech binaries on the machine, and the agent who continues the slice. Arya's physical iPhone, Apple Watch, microphone, and speaker are out of reach for any agent.

## Goals / Non-Goals

**Goals:**

- Give the next agent one contract for notes on disk, local speech handoffs, and the held app draft.
- Keep knowledge bodies under `MESHD_STATE`. Keep them off Supabase and off any other cloud store.
- Keep finished drafts as the implementation. Re-check each tip before editing the same files.
- Make the `server.ts` rule obvious: this change does not edit it; a later agent registers only when the route is missing and no other agent holds that file.

**Non-Goals:**

- A second copy of pull requests 139, 145, 154, 160, or 162.
- Editing `server.ts`, `pair.ts`, `Shared/Models.swift`, `Shared/MeshClient.swift`, or `project.yml` in this change.
- A live AI Gateway call. Committing an API key, a JWT, or a database URL.
- Merging the local-brain harness. Replacing `meshd`.
- Physical proof of a microphone or speaker.

## Decisions

### 1. Finished drafts are the implementation

PR 139 is the local PDF note and the knowledge module that owns its own file. PR 145 is spoken-out through `MESH_TTS`. PR 154 is the note-to-held-file path. PR 160 is the route-gated draft. PR 162 is spoken-in through `MESH_STT`. An agent who needs one of those behaviors opens that pull request and re-checks the tip. Do not start another copy of any of them.

Alternative considered: re-implement each slice on `main` inside this change so the spec and the code land together. Rejected. A second copy of a finished draft is the failure mode this handoff exists to prevent.

### 2. Notes stay under `MESHD_STATE`, never in Supabase

The note directory is `$MESHD_STATE/knowledge/` when `MESHD_STATE` is set, otherwise `~/.mesh/knowledge/`. Directory mode 700. File mode 600. Knowledge bodies, PDF bytes, transcripts, and draft text stay on the machine. Account tables do not store prompts, PDFs, or generated apps.

Alternative considered: upload note titles to the account database for cross-device search. Rejected. That would make the knowledge base a second cloud copy of the person's papers. Task 7 in the Oct 1 plan sequences after sealed device sync for that reason.

### 3. Speech is a local binary the user already has

Spoken-out hands note text to `MESH_TTS` on stdin when the request asks for speech. Spoken-in reads a local audio file through `MESH_STT` and writes the transcript as the note body. A remote URL does not run. No speech program is downloaded. Do not start a second speech-in path beside PR 162.

Alternative considered: a company STT or TTS endpoint. Rejected. The person this is for already has a binary on the machine, or they do not use speech yet.

### 4. Jev chooses a route and does not write the reply

PR 160 posts a filtered note to a local model stub only when `route()` returns `allow-local-tool`. A secret-moving note, a graphical ask, a wait-for-human result, a high risk, or confidence below 0.6 does not connect and does not create the file. The check runs with the gateway key unset. A live gateway call waits on a card on the Vercel team and is outside this change.

Alternative considered: let Jev draft the file text. Rejected. Jev evaluates. The user's model writes. The draft file is not executed. A further command waits for confirm (the existing review-before-dispatch rule).

### 5. This change does not edit `server.ts`

On `origin/main`, knowledge routes are not registered. On PR 139's tip, they are. A later agent checks the tree it is editing. If the routes are already registered, that agent says so and forbids a second route. If they are not, one later task may register them only when no other agent holds `server.ts`. This pull request itself contains no `server.ts` edit.

Alternative considered: register the route in this change so the next agent has a green path on `main`. Rejected. Shared contracts are serialized. This change is the handoff, not the registration.

### 6. The harness stays a spike

Task 8 in the Oct 1 plan may later point `ctx.subprocess` / `ctx.fs` at existing session routes in a time-boxed adapter beside the daemon. If the upstream preview breaks, stop and write what broke into the proposal's `tasks.md`. Do not replace `meshd`. Do not merge `openspec/changes/local-brain-and-harness/` as the shipping loop.

## Risks / Trade-offs

- [An agent rebuilds PR 139, 145, 154, 160, or 162] → The tasks point at the existing pull request, record the current `headRefOid`, and stop. A new file for one of those slices is a failed task.
- [An agent registers `/knowledge` a second time because PR 139 is not merged] → The later agent first checks whether the route is already present. If it is, forbid a second route. If it is not, register only when no other agent holds `server.ts`.
- [Knowledge bodies land in Supabase, logs, or a gateway payload] → The specs treat that as a failed design. The checks on the finished drafts already refuse a Supabase client and a gateway call in the knowledge and draft paths.
- [A draft file is treated as an executed app] → The held-file and route-gated drafts stop for confirm. An unconfirmed command does not run.
- [An agent claims the microphone or speaker works] → No task requires Arya's physical devices. Agents cannot prove a physical microphone or speaker. Say so and hand that check back to a human.
- [A key, JWT, or database URL lands in the diff] → The proof command searches the change and must find none. Do not call the AI Gateway.
- [Someone merges the local-brain harness as the shipping loop] → Out of scope. The harness proposal stays a spike.

## Migration Plan

This change deploys nothing. Merging it adds the spec under `openspec/changes/local-knowledge/` and leaves the daemon, the account tables, and production as they are.

Rollback is reverting that commit. There is no schema migration, no env var, and no feature flag in this change.

A later agent continues from the finished draft tips above. That later work is not a reason to rebuild those drafts inside this change.

## Open Questions

None that block this handoff. Product decisions about Pro unlocking the spoken knowledge base stay with Ritik and do not change these requirements.
