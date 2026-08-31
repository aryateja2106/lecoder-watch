## Context

The Terminal tab lists sessions from one multiplexer and opens them through another. See
`proposal.md` for the reproduction. One detail from that reproduction shapes every decision
below, so it is restated here:

**The runtime tag was already in the name. The consumer threw it away.**

`herdr:wA:p2` is not a malformed string. It is `herdr` + `wA:p2`, and `wA:p2` is exactly the
pane-id shape herdr itself uses — confirmed against a live host:

```
$ herdr api snapshot
{"result":{"snapshot":{"focused_pane_id":"w5:p1","focused_tab_id":"w5:t1",
 "focused_workspace_id":"w5","layouts":[{...,"panes":[{"pane_id":"w9:p2",...}]}]}}}
```

`rmux-bridge` received `herdr:wA:p2`, never split on the first colon, and passed the whole
string to `rmux has-session -t`, which read it as session `herdr`, window `wA`:

```
$ rmux has-session -t "herdr:wA:p2"
can't find session: herdr        exit=1     →   ws.close(1008, "no such session")
```

So this is not a missing-feature problem requiring new plumbing. It is a **discarded
discriminator**. The fix is to make the discriminator load-bearing and typed, so it cannot be
discarded again silently.

Constraints inherited from the project:

- Principle 1 is already "multiplexer-agnostic ... the code must not assume one". The shipped
  build violates it. This design is conformance work, not a new direction.
- The daemon has exactly one shipping copy, `install/payload/meshd/`. A second copy has cost
  real work before.
- Bun + TypeScript, no new dependencies. SwiftUI, no third-party dependencies.
- The fleet is not on one version — machines observed on meshd 0.5.1 and 0.5.4 — so the wire
  format must degrade rather than break.
- The watch reads output over `/agents/:n/output` and sends keys over `/agents/:n/send`.
  Those work today and must not regress.

## Goals / Non-Goals

**Goals:**

- Every session offered in the list can be opened, or says why not, before the tap.
- One seam — a runtime adapter — is the only place a multiplexer binary is named.
- A failed attach reaches the user as a sentence, not as red text inside a web view.
- cmux stops being a dependency.
- The Terminal tab's own screens stop clipping.
- `GET /doctor` can see this class of mismatch from the host.

**Non-Goals:**

- Replacing the embedded xterm web view. It renders correctly when it has a live socket.
- A general plugin system for multiplexers. Three implementations, one interface, no registry.
- Supporting zellij or mosh now. The adapter must make adding one contained; that is all.
- Changing `/agents/:n/output` or `/agents/:n/send`.
- Any screen outside the Terminal tab.

## Decisions

### D1: A typed `SessionRef`, not a delimited string

Sessions travel as `{ runtime, target }` rather than `"runtime:target"`.

*Why:* The delimited form already existed and already failed, because nothing forced any
consumer to parse it. A string is a suggestion; a two-field object is a contract the type
checker enforces at the seam. The display name stays a separate, purely cosmetic field.

*Alternatives:*
- *Keep the delimited string, split on first colon.* One line, fixes today's bug. Rejected:
  it leaves the next consumer free to ignore the prefix exactly as this one did, and targets
  containing colons (`wA:p2` does) make "split on first colon" a rule everyone must remember.
- *A URI (`herdr://wA:p2`).* Same information, more ceremony, and invites a URL parser where
  a struct will do.

### D2: The adapter lives in `meshd`, and the bridge asks `meshd`

The runtime adapter is a module inside `install/payload/meshd/`. The bridge does not
implement its own; it resolves a `SessionRef` by asking the daemon.

*Why:* The daemon already owns `MESH_MUX`, `/doctor`, and session enumeration. Two independent
implementations of "which multiplexer owns this session" is precisely the bug being fixed —
duplicating the adapter into the bridge would recreate it in a new place.

*Trade-off:* The bridge gains a dependency on the daemon being up. It already effectively has
one; making it explicit means the bridge can fail with "daemon is down" instead of "no such
session", which is the more useful sentence.

*Alternative rejected:* a shared library imported by both. Cheaper in principle, but the two
run as separate Bun processes with separate lifecycles, and the vendoring story is worse than
one HTTP call to something already running.

### D3: Adapter interface — six verbs, tmux vocabulary

```
list()                    -> SessionRef[]  with display metadata
has(ref)                  -> boolean
capture(ref, lines)       -> string
send(ref, keys)           -> void
split(ref, direction)     -> SessionRef
kill(ref)                 -> void
```

tmux's command vocabulary stays the lingua franca, as `specs/terminal-sessions/spec.md`
already requires. tmux and rmux implement it directly. **herdr does not, and cannot be made to
— this is the single most important finding of the coupling audit.**

| verb | tmux / rmux | herdr |
|---|---|---|
| `list` | `list-sessions -F …` | `herdr pane list` (JSON: `pane_id`, `cwd`, `label`, `agent_status`) |
| `has` | `has-session -t` | pane id present in `herdr api snapshot` |
| `capture` | `capture-pane -p -e -t` | `herdr pane read --lines N --source recent-unwrapped` |
| `send` | `send-keys -H -t` | `herdr pane send-text` / `send-keys` |
| **live stream** | `pipe-pane -O -t` → unix socket | **no equivalent exists** |

**herdr has no `pipe-pane`.** The bridge's entire live-terminal mechanism is a unix socket fed
by `pipe-pane -O` (`rmux-bridge/src/server.ts:175-197`). herdr's CLI offers no counterpart, so
**a herdr pane cannot be driven by the existing xterm bridge at all.** Nor can a herdr ref be
translated into a tmux target: a herdr "session" is a named *server instance* (`default`), not
a workspace, and the working units are panes addressed `w9:p2`. There is no tmux object to map
onto.

This kills the assumption this design was first written on. The consequence:

- **herdr is a read + send runtime, not an attach runtime.** Its rows are listed, readable and
  typeable — which is what the watch already does through `/agents/:n/output` — and are marked
  *not bridge-attachable*. That marking is exactly what the `session-attach` spec requires, so
  herdr becomes the primary case that requirement exists to serve, not an exception to it.
- **Day one, herdr is reachable without any daemon change**: `rmux new-session -d -s herdr 'herdr'`.
  herdr is client/server, so that client attaches to the running `default` server and every live
  pane renders through the existing bridge, unchanged. `POST /agents/new` already accepts `cmd`,
  and the watch already offers it (`Watch/WatchViews.swift:723`). The honest caveat is nested-TUI
  key handling — herdr's own prefix chords inside rmux — and it is already written down at
  `Watch/WatchViews.swift:1229`.

*Why herdr is supported at all rather than ignored:* it is where the owner's actual work lives —
six live panes across `w5 w7 w9 wA`, two of them agent worktrees under `~/.herdr/worktrees/lecoder/`.
Today those panes are invisible to `/agents` on both phone and watch. A fix that made only
`factory` and `test-session-1` openable would be correct and useless.

### D3a: Ban colons in session names

`listAgents()` emits bare `#{session_name}` only. tmux/rmux `-t` targets use
`session:window.pane` grammar, so **any colon-bearing name is structurally unattachable** —
`-t "herdr:wA:p2"` looks for a session named `herdr`. This is a grammar collision, not a lookup
miss, and no amount of runtime tagging fixes it if a colon survives into the target.

With colons banned at the producer, `ws.close(1008, "no such session")` becomes unreachable by
construction rather than merely unlikely.

### D4: Remove cmux entirely rather than adapting it

*Why:* Every cmux row was unopenable. Adapting it means writing and maintaining a third
translation layer to rescue rows the owner has explicitly said he does not want the dependency
for — his words: cmux "is a very heavy one", tmux "is a very lightweight dependency". Deleting
`cmuxSessions()` is a smaller diff than fixing it, and removes an Electron-class dependency.

*Mitigation for the silent disappearance:* `/doctor` names cmux as detected-but-unsupported, so
rows vanishing is explained rather than mysterious.

*Alternative considered:* keep cmux behind a flag, default off. Rejected as the worst of both —
the dependency stays, the code stays, and almost nobody exercises the path.

### D5: Close codes cross the WKWebView boundary via `WKScriptMessageHandler`

The bridge page already knows its socket closed — it prints `closed (1008)`. It posts that to
the native side through a script message handler; `BridgeTerminalScreen` maps it onto the
existing `WebLoadPhase.failed` and renders the error state it already has.

*Why:* The error UI, the Retry, and the URL display all already exist and are well written.
Only the trigger is wrong. This adds a message channel, not a screen.

*Alternative rejected:* poll the daemon to check the session is still alive. Indirect, racy,
and would still not know *why* the socket closed.

### D6: Fix layout by constraining, not redesigning

The clipping is horizontal overflow: `HStack`s and fixed-width stat cards wider than the
viewport, which SwiftUI centres and clips. The fix is `.labelStyle(.iconOnly)` where a text
label overflows, wrapping where text is cut, `ScrollView(.horizontal)` for genuinely wide
content, and `.safeAreaInset(edge: .bottom)` so scroll views clear the floating tab bar.

*Why not a redesign:* the owner asked for a broad redesign, and that is a real and separate
piece of work. Mixing "make the terminal open" with "restyle every screen" would make both
slower and neither verifiable. This change makes the Terminal tab legible; the redesign
change makes the app consistent.

## Risks / Trade-offs

- **herdr's CLI is not a stable API** → `herdr api schema` exists and is bundled; pin against
  it and fail the adapter loudly on a schema mismatch rather than silently listing nothing.
  A runtime whose snapshot cannot be parsed reports as failing in `/doctor`.
- **Bridge now depends on the daemon** (D2) → explicit, and produces a better error than the
  status quo. Bridge caches the last successful resolution so a daemon restart mid-session
  does not kill a live terminal.
- **Users lose cmux rows with no warning** → `/doctor` explains it; the release note states it;
  the work itself is untouched on the host.
- **Old daemons emit untagged names** → inference from `MESH_MUX`, reported as inferred. The
  risk is a wrong inference on a host running two multiplexers; the mitigation is that the row
  then fails with a *named* cause instead of `1008`, which is still strictly better than today.
- **herdr panes can never have a live xterm** (no `pipe-pane`) → they are read + send only,
  explicitly marked. Users who want a live terminal on herdr work run herdr inside rmux (D3).
  This is a permanent product limitation, not a temporary gap, and must be stated as one.
- **Nested-TUI key handling** when herdr runs inside rmux → herdr's prefix chords must pass
  through the bridge's key bar. Known friction, already documented at `WatchViews.swift:1229`.
- **Scope creep into the full redesign** → the Non-Goals list is the guard; layout work is
  limited to the Terminal tab's own screens.

## Migration Plan

1. **Ban colons at the producer** and delete cmux. These are the same step: cmux is the only
   generator that emitted colon-bearing names, and its socket is refused on the owner's machine
   today, so nothing observable changes. This alone makes `1008` unreachable.
2. **Document the day-one herdr path** (`POST /agents/new {cmd:"herdr"}`) so the owner's real
   workspaces are reachable this week, before any adapter exists.
3. Land the adapter and `SessionRef` in `meshd` behind the existing endpoints; the wire gains
   the runtime tag additively, so old clients keep working.
4. Point the bridge at the adapter. Rename `rmux-bridge` — the name is now actively misleading.
5. Ship the client changes: runtime tag, close-code plumbing, row marking, layout.
6. Add the herdr read/send adapter (`pane list` / `pane read` / `pane send-text`), emitting rows
   marked not-bridge-attachable.
7. Extend `/doctor`.

**Ordering note:** cmux deletion moved from last to first. The original plan held it back until
herdr rows were "demonstrably openable" — but herdr rows will never be bridge-openable (D3), so
that gate would have blocked the cheapest win indefinitely.

**Free win from step 1:** `install.sh:511-517` writes the `~/.zshrc` line that historically
SIGKILLed meshd from every new shell — the hazard `scripts/check-bridge-kill-scope.sh` exists
solely to police. Deleting cmux retires that whole class.

**Rollback:** each step is independently revertible. Steps 1–3 change no client behaviour on
their own; a client that ignores the runtime tag behaves exactly as today.

**Verification, per the project's hard-won rule that a green build is not evidence:** the
acceptance test is opening `quirky-cannon-a7cab9` — the session in the owner's screenshot —
from the phone and typing into it. Not a passing build. Not a unit test. That session.

## Open Questions

1. ~~Can a bridged PTY drive `herdr session attach` cleanly?~~ **Answered: no.** herdr has no
   `pipe-pane` equivalent, and a herdr "session" is a server instance, not a workspace. herdr is
   read + send only. See D3.
2. **Which generator produced the failing rows in the owner's screenshots?** The video's title
   bar read `herdr:wA:p2` and `rmux has-session -t "herdr:wA:p2"` reproduces `can't find session:
   herdr`. But `cmuxSessions()` prefixes `cmux:`, and `TerminalView.swift:590` already greys
   "Open terminal" for `cmux:`-prefixed rows — yet the button was blue and tappable in both
   captures. Either the row reached the list by another path (`ManualBridgeScreen` at
   `TerminalView.swift:183` has no attachability guard), or the `isCmux` prefix check misses this
   shape. **The second screenshot is also a different failure** — "isn't answering — nothing has
   loaded yet" with CPU/Mem/State all `—` is a daemon-unreachable state, not `1008`. Resolve by
   capturing `GET /agents` from the owner's phone before writing code; the fix may be smaller or
   larger than this design assumes.
3. Should `MESH_MUX` remain a single value, or become an ordered preference list now that a
   host demonstrably runs four multiplexers at once? Leaning single-value plus per-session
   tags, since the tag makes the global setting matter only for old-daemon inference.
3. Does anything outside the Terminal tab consume the delimited session-name format? To be
   confirmed by grep before the format changes — noting the project's own warning that grep
   silently skips binary-classified files.
4. Does the watch need the runtime tag, or is it purely a phone concern? The watch reads text
   output and never attaches a PTY, so probably not — confirm before adding it to the watch model.
