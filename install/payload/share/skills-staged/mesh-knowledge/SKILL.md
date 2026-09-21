---
name: mesh-knowledge
description: Search the shared mesh knowledge base or remember durable notes when the user asks to search, recall, save, or remember information.
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
