---
run_id: 2026-09-23T070000Z-session-snapshots
stage: implement
started_at: 2026-09-23T06:40:00Z
finished_at: null
status: in-progress
issue: none (Arya's choice in-session, 2026-09-23: agent-git → "Build it into mesh")
pull_request: https://github.com/aryateja2106/lecoder-watch/pull/133
gate_level: fast
gate_status: GREEN (FACTORY_GATES: level=fast status=GREEN passed=2 failed=0 failing=none skipped=none misconfigured=none)
verifier: running (oh-my-claudecode:verifier, fresh context, incl. a throwaway side-port daemon)
human_required: false
---

# Session snapshots, slice A — no agent conversation is lost

## Why

Claude Code rewrites a transcript when it compacts and deletes it after 30 days
(`cleanupPeriodDays`), so the conversation that cracked a bug is gone. Arya looked at
agent-git (github.com/Einsia/agent-git) on 2026-09-23. It versions sessions, but only
through its hosted hub, the hub is not open source, and the usage statistics it sends
cannot be turned off there. He chose to build it into mesh: local only, no account,
no telemetry.

## What landed

- `install/payload/meshd/sessions.ts`: every Claude Code and Codex transcript is kept
  under `~/.mesh/sessions/<runtime>/<id>/` (0700, files 0600). A version is a full base,
  or, when the file only grew, a gzip of just the new bytes. Every version is checked
  against its sha256 before it is served. Snapshots are taken on every hook event that
  carries a cwd and by a sweep every ten minutes. Snapshots of one file queue behind
  each other.
- Routes: `GET /sessions`, `GET /sessions/:runtime/:id[/raw?v=N]`, and
  `POST /sessions/claude/:id/restore?v=N`, which writes that version beside the
  original under a new id. Capability `sessions`.
- `mesh sessions [ls | log <id> | restore <id> --at N] [-H host]`.
- `scripts/check-session-snapshots.sh`.

## Proof, by running

| What | Result |
|---|---|
| `check-session-snapshots.sh` (throwaway HOME: base, append, unchanged, compaction, byte-exact rebuild of every version, 0700/0600, subagent skip, idempotent sweep, restore rewrite, Codex refusal, tamper refusal, concurrent writers) | OK, 5 of 5 runs |
| Mutations it must catch: append forced to base, hash check removed, restore rewrite broken, 0644 files, per-file lock removed | first four: always caught. Lock removed: caught 3 of 5 runs (a race, so catching it is probabilistic) |
| Real transcript (145 KB, this repo's project) snapshotted, restored, then `claude -p --resume <new id>` | Claude resumed the restored id and answered with the original first request ("You said the updated voice input on the phone wasn't consistent…"). The original file was untouched, and the old id appears nowhere in the copy |
| 139 MB transcript (this session), base then appends | base 1.6 s; append 65 ms and about +50 MB RSS in a fresh process (it was 593 MB RSS before the streaming fix) |
| `gates.sh fast` | `FACTORY_GATES: level=fast status=GREEN passed=2 failed=0 failing=none skipped=none misconfigured=none` |
| `check-all.sh` | every check green except check-codemap, which went stale when the new file was committed mid-run; regenerated, and check-codemap is now OK |

## Found on the way

- On bun 1.3.14, `Bun.file(p).slice(0, n).stream()` never ends when `n` stops mid-file
  past its first chunk (reproduced: 200 KB of a 400 KB file). The prefix hash uses
  `node:fs` `createReadStream` instead. No other payload code streams a slice.
- Without the per-file lock, the Stop-event trigger and the sweep could both write
  `v<N>` and leave every later version unreadable.

## Not yet

- Deploy to the fleet and a live `mesh sessions -H jetson`. Held: a peer session asked
  for a code freeze on the branch while it gates.
- Slice B: redacted replication of every machine's sessions to the Jetson (always on).
- A base still reads the whole file (about 2.5x its size in RSS, once per session and
  once per compaction). It is marked `ponytail:` in the code.
- Restore covers Claude Code only. Codex resumes by rollout path, not by id; add
  restore for Codex when someone asks for it.
