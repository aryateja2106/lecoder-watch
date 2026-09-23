---
name: mesh-knowledge
description: Search the shared mesh knowledge base, remember durable notes, or find and resume a past agent conversation on any machine, when the user asks to search, recall, save, remember, or pick up where an earlier chat left off.
---

# Mesh knowledge

Use the installed `mesh` CLI. If it is not on `PATH`, use `~/.mesh/bin/mesh`.

## `/search <query>`

Run:

```sh
mesh kb search "<query>" --json
```

Read `results`, then answer from the best matches. Cite each result as
`host scope/key`. If `mesh` is unavailable, retry with `~/.mesh/bin/mesh`.

Search reaches every configured machine that is currently online in the Tailscale mesh.
Use `--local` only when the user explicitly asks for this machine alone.

## `/remember <title> — <body>`

Set the scope to `project/<basename of cwd>`. Make the key from a lowercase hyphenated
slug of the title plus today's `YYYY-MM-DD` date. Set `--source` to the active CLI name:
`claude`, `codex`, or `cursor`.

Run:

```sh
mesh kb put "project/<cwd-basename>" "<title-slug>-<YYYY-MM-DD>" "<title>" "<body>" --kind note --source <cli-name>
```

If `mesh` is unavailable, retry with `~/.mesh/bin/mesh`. Report the stored scope/key.
The note is stored on this machine's daemon and searches from other online mesh machines
can find it.

## `/seek <what you remember about a past conversation>`

Every Claude Code and Codex conversation on every mesh machine is indexed (what the person
typed and what the agent answered, not tool output). Run:

```sh
mesh sessions search "<query>" --json
```

Read `results`, best first. Each row names its `host`, `runtime`, `shortId`, `title`,
`cwd`, `lastTs` and up to three `excerpts` with the matched words between « and ». Answer
with the best few: title, machine, how long ago, and the excerpt that matched. Machines in
`peers` with `ok: false` did not answer (asleep or older meshd), so say that when nothing is
found. `--all` also searches subagent and automation threads; `--local` searches only this
machine.

Resume only when the user asks to pick a conversation up:

```sh
mesh sessions resume <shortId> -H <host> --json
```

It starts the original CLI (`claude --resume` or `codex resume`) in a mesh session on the
machine that holds the conversation, restoring a Claude transcript the runtime already
deleted. Tell the user the session name and that they can watch it with
`mesh peek <name> -H <host>` or open it in the LeSearch AI app. If `mesh` is unavailable,
retry with `~/.mesh/bin/mesh`.
