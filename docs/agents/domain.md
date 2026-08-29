# Domain Docs

How the engineering skills should consume this repo's domain documentation.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root (shape of MeshWatch).
- **`AGENTS.md`** — the single brief for every harness. Hard-won rules live here.
- **`MEMORY.md`** — settled decisions and dead ends. Do not relitigate them.
- **`openspec/config.yaml`** — the project context every spec is written against.
- **`docs/factory/CHARTER.md`** and **`docs/factory/CONTRACT.md`** before factory work.

`docs/adr/` does not exist yet. Do not create it empty. `/grill-with-docs` and
`/domain-modeling` may add an ADR there when a real decision lands.

If a listed file is missing, proceed silently.

## File structure

Single-context repo:

```
/
├── CONTEXT.md
├── MEMORY.md
├── AGENTS.md
├── openspec/
└── docs/factory/
```

## Use the glossary's vocabulary

When your output names a domain concept, use the term as defined in `CONTEXT.md`
and `openspec/config.yaml`. Canonical product name is **MeshWatch**, published by
**LeSearch AI**. The daemon and CLI stay `meshd` / `mesh`.

## Flag ADR / MEMORY conflicts

If your output contradicts `MEMORY.md` or an existing ADR, surface it explicitly
rather than silently overriding.
