# INDEX — start here

The file map is generated from the tree and checked against it; nothing here is typed by
hand any more (the last hand-written version of this file still called 0.3.0 current).

| Read | For | Cost |
|---|---|---|
| [docs/agents/CODEMAP.md](docs/agents/CODEMAP.md) | **Which file?** Every code file, its purpose, size bucket, and the self-checks that name it | ~4k tokens |
| [docs/agents/CONTRACTS.md](docs/agents/CONTRACTS.md) | **What talks to what?** Daemon routes with auth tier, capability strings and where each is gated, the watch → phone relay commands | ~1.7k |
| [docs/agents/CHECKS.md](docs/agents/CHECKS.md) | **What does check-x prove?** One line per `scripts/` file | ~2.5k |
| [docs/agents/SYMBOLS.md](docs/agents/SYMBOLS.md) | **Where is symbol X?** Grep it: `grep -n '^| X ' docs/agents/SYMBOLS.md`. Never read whole | grep only |
| [CONTEXT.md](CONTEXT.md) | The shape: two loops, the daemon, the relay, where things live | ~2k |
| [MEMORY.md](MEMORY.md) | Why it is shaped that way: settled decisions and dead ends | ~4.6k |
| [docs/README.md](docs/README.md) | Which docs are current and which are archaeology | ~2k |

Deeper than the map: `codegraph explore <symbol>` (source + callers + blast radius over
MCP) and `graphify query "<question>"` (code + docs graph). Both local; see
[docs/agents/codebase-map.md](docs/agents/codebase-map.md) for how each harness is wired.

Refresh everything: `sh scripts/codemap.sh`. The map alone: `python3 scripts/codemap-index.py`.
Stale map = red `scripts/check-codemap.sh` = red `gates.sh full`.

## The rule that saves the most tokens

Read CODEMAP, pick ONE file, open only that. If the question is "who calls this" or "what
breaks if I change it", ask codegraph before opening anything. Grep the tree last.

## Build and check

```sh
./.claude/scripts/gates.sh fast   # types + lint, ~40s, while working
./.claude/scripts/gates.sh full   # + every check-* + three simulator builds, before a PR
```

Quote the final `FACTORY_GATES:` line verbatim. A green build proves very little on its
own; run the change against a real daemon before believing it (AGENTS.md rule 1).
