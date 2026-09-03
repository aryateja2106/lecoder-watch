---
name: glaze-context-gather
description: Gather context from project memory, guides, and codebase before implementation. Use when starting new features, complex changes, or when you need to understand existing patterns. Triggers on "gather context", "check what exists", "explore the codebase", or any task that needs codebase understanding before coding.
context: fork
model: haiku
agent: Explore
---

Gather context for this task: $ARGUMENTS

## Sources (in priority order)

### 1. Project Memory

Read `.glaze_memory/PROJECT-CONTEXT.md` for previous decisions, corrections, and user preferences.

### 2. App Guide

Read the Glaze App Guide at the path provided. Use `Read` with `offset` and `limit` to read only relevant sections — never read the full guide.

**Guide section index (line numbers → use as offset):** | Section | Lines | When to read | | Critical Rules | 52-72 | Always | | Decision Trees | 73-105 | Always | | Overview / Architecture | 106-129 | Often | | Backend (handlers, services) | 130-479 | Backend tasks | | Window Management | 147-245 | Window tasks | | Adding Backend Handlers | 284-317 | New IPC handlers | | Global Shortcuts | 318-355 | Hotkey tasks | | System Notifications | 356-389 | Notification tasks | | System Tray | 390-479 | Menu bar tasks | | Frontend (components, routing) | 480-542 | UI tasks | | Configuration | 543-572 | Config tasks | | Bundling & Publishing | 573-720 | Native modules | | Static Assets | 721-823 | Images/fonts | | Quick Reference / Patterns | 1028-1142 | Always |

### 3. Existing Codebase

- Check existing implementations for patterns
- Look for related code that new features should integrate with

## Output Format

```
## Context for: [Task Description]

### From Project Memory
[Relevant entries, or "No relevant history"]

### From GLAZE-APP-GUIDE.md
- Section: [name] — [relevant info]

### From Existing Code
- [file path]: [what it contains/does]

### Notable Constraints
[NEVER/ALWAYS rules, forbidden patterns found]
```

## Rules

1. Report, don't decide — no architectural recommendations
2. Be concise — summarize, don't dump file contents
3. Prioritize project memory — previous corrections are most valuable
4. Only include relevant info — skip unrelated sections
5. Batch all independent reads in a single turn (e.g., read PROJECT-CONTEXT.md and guide sections in parallel)
6. File searches must stay within `.glaze-sources/` and the guide path ONLY. NEVER search home directories, iCloud, OneDrive, or any path outside the project.
7. Output must be under 400 words
8. Do not use live inspection tools during context gathering. They are for post-build runtime debugging only, after the app is built and already running.
