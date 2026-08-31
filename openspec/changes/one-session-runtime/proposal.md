## Why

The Terminal tab lists eight sessions and six of them cannot be opened. Not "sometimes
fail" — cannot, ever, by construction. This is the owner's report, in his own words:

> "It's giving me an option to open the terminal session, but when I do open it, this is
> the screenshot I'm getting... it's almost looking like the application is not built in a
> good responsive way as it's not able to — as it's like collapsing on my phone, the UI is
> breaking"

and, from the screen recording the day before:

> "I'm not able to open my terminal, enter into my terminal like I wanted to."

The cause is reproduced, not inferred:

```
$ rmux ls
factory: 1 windows (created Fri Aug 28 22:42:38 2026)
test-session-1: 1 windows (created Fri Aug 28 11:55:25 2026)

$ rmux has-session -t "herdr:wA:p2"
can't find session: herdr
exit=1
```

`meshd` enumerates sessions from **cmux and herdr** workspaces (`install/payload/meshd/server.ts`,
`cmuxSessions()`), producing names shaped `cmux:<ref>` / `herdr:wA:p2`. The terminal is then
opened through `rmux-bridge`, which hardcodes a **different** multiplexer:

```ts
// install/payload/rmux-bridge/src/server.ts:238
const exists = await runRmux(["has-session", "-t", session]);
if (exists.code !== 0) { ws.close(1008, "no such session"); }
```

`rmux` parses `herdr:wA:p2` as session `herdr`, window `wA` — a session it has never heard
of. Every herdr-hosted session in the list is therefore guaranteed to close with `1008`.
`factory` and `test-session-1` are the only two rows that can work, because they are the only
two that are genuinely rmux sessions.

**This already violates two shipped requirements** in `specs/terminal-sessions/spec.md`:
"The multiplexer is the user's choice ... SHALL NOT privilege one in code", and "An
unavailable multiplexer is reported, not hidden ... the session list SHALL NOT silently
appear empty as though the user had no work."

Four multiplexers are installed on the owner's own machine (`tmux`, `rmux`, `cmux`, `herdr`)
and `tmux` is not even running. The daemon speaks one, the bridge speaks another, and the
one the owner actually lives in all day — herdr — is reachable by neither.

Two failures compound it, and they are why this went unnoticed for weeks:

1. **The failure is invisible.** `iOS/TerminalView.swift` has a correct full-screen error
   ("Can't reach the terminal bridge" + URL + Retry), but it is keyed on `WebLoadPhase` —
   whether the *WKWebView page* loaded. The page loads perfectly; the *WebSocket inside it*
   dies. So a total failure renders as 8-point red text from the bridge's own HTML on an
   otherwise black screen. The comment above that code says it exists precisely to stop
   "the failure that looks like success". It does not catch this one.

2. **The screen it fails on is unreadable anyway.** The session detail view clips text off
   both edges (`PU` for CPU, `sessi` for session, `pane list yet.`), the stat cards run past
   the viewport, and the floating tab bar sits on top of the last two rows of content.

Why now: this is the product's namesake capability, the owner cannot use it on his own
machine, and audience feedback already cites instability as the reason they will not
recommend it.

## What Changes

- **BREAKING: `cmux` is removed as a session source.** cmux is a heavy dependency
  (an Electron-class workspace app) being used only to enumerate panes. Its rows are among
  the ones that cannot be opened. Sessions discovered through cmux disappear from the list.
- **A session-runtime adapter becomes the single seam.** `meshd` gains one adapter interface
  covering `list / has / capture / send / split / kill`, with implementations for tmux, rmux
  and herdr. The tmux command vocabulary stays the lingua franca, as the existing spec
  requires. Nothing outside the adapter may name a multiplexer binary.
- **`rmux-bridge` stops hardcoding rmux.** It resolves the runtime from the session's own
  identity via the adapter, so a herdr pane attaches through herdr and an rmux session
  through rmux.
- **A session's identity carries its runtime.** The wire format becomes explicit
  (`runtime` + `target`) instead of a colon-delimited string that each end parses by
  guesswork. This is what made `herdr:wA:p2` look like a valid rmux target.
- **A row that cannot be opened is never offered as though it can.** The list marks
  unattachable sessions before the tap, with the reason.
- **WebSocket close codes surface as native errors.** `1008` and `1011` from the bridge
  reach `WebLoadPhase` and render the existing full-screen error with a human sentence and
  a Retry, instead of 8-point red text inside the web view.
- **The Terminal tab's screens stop clipping.** Content wraps or scrolls within the
  viewport; no text is cut off horizontally; scroll views inset for the floating tab bar.

## Capabilities

### New Capabilities

- `session-attach`: What it means for a listed session to be openable — the runtime-tagged
  identity contract between daemon, bridge and client; resolution of a session to an
  attachable target; and the requirement that every failure to attach is surfaced natively
  with a cause, never swallowed by the embedded web view.

### Modified Capabilities

- `terminal-sessions`: Two requirement changes. (1) "The multiplexer is the user's choice"
  is extended to bind the *attach* path, not only the daemon's read path — today the daemon
  honours `MESH_MUX` and the bridge ignores it. (2) A new requirement that a session which
  is listed is attachable, or is visibly marked as not attachable with a reason; today the
  list makes no distinction and six of eight rows are dead.

## Impact

**Code**
- `install/payload/meshd/server.ts` — `cmuxSessions()` deleted; session enumeration moves
  behind the adapter; session objects gain an explicit runtime tag.
- `install/payload/meshd/` — new adapter module (tmux / rmux / herdr implementations).
- `install/payload/rmux-bridge/src/server.ts` — `runRmux` replaced by adapter dispatch;
  `handleOpen`'s `has-session` check resolves through the runtime the session declares.
  The component name `rmux-bridge` becomes a misnomer and is renamed.
- `Shared/Models.swift`, `Shared/MeshClient.swift` — session model carries the runtime tag.
- `iOS/TerminalView.swift` — close-code plumbing into `WebLoadPhase`; unattachable-row
  marking; layout fixes on the session list and session detail screens.
- `install/payload/meshd/doctor.ts` — reports every runtime present and which sessions each
  can attach, so this class of mismatch is visible from `/doctor` rather than from a phone.

**Dependencies**
- cmux removed. tmux, rmux and herdr remain optional and detected, none required.

**Compatibility**
- Older daemons that emit untagged session names must keep working: an absent runtime tag
  is inferred from `MESH_MUX`, with the inference stated in `/doctor`. The fleet is not all
  on one version (machines observed on meshd 0.5.1 and 0.5.4).

**Not affected**
- The daemon's HTTP surface for reading output (`/agents/:n/output`) and sending keys
  (`/agents/:n/send`) is unchanged. Those already work; the watch depends on them.

## Non-goals

- **Redesigning the whole app.** Only the Terminal tab's own screens are in scope. Remote /
  Machines / Monitor / Settings keep their current layout, however bad, and get their own
  change.
- **Consolidating repositories.** The monorepo question is real and separate.
- **Remote access over NAT.** Owned by the existing `reach-my-mac-from-anywhere` change.
- **Local models or an agent harness.** Owned by the existing `local-brain-and-harness` change.
- **Adding a multiplexer.** No zellij or mosh implementation ships here; the adapter must
  merely make adding one a contained change.
- **Rewriting the terminal renderer.** The embedded xterm web view stays. Its failures just
  stop being invisible.

## Target user

Unchanged from the project context, and it is the reason the fix cannot be "document the
right session to pick": non-technical people who want to use AI agents daily and who do not
configure SSH, ports or VPNs. Such a user cannot be expected to know that `herdr:wA:p2` is a
different kind of object from `factory`, or that one of the four multiplexers on the machine
is the one the bridge happens to speak. A row that is offered must work, or must say why it
does not.

Note that the owner — an expert, on his own hardware, who wrote this system — could not
diagnose this from the app. That is the strongest evidence the current surfacing is
inadequate for anyone.
