Every task ends in a command you can run or a device action you can perform. A green build is
not evidence — the project's own hard-won rule. Tasks marked **[DEVICE]** need Arya's physical
iPhone or Watch; an agent cannot complete them.

## 0. Resolve the contradiction before writing code

Design Open Question 2 is unresolved and could change the size of this change.

- [ ] 0.1 **[DEVICE]** Capture `GET /agents` from the phone's own daemon while the failing rows
  are on screen. Run `curl -s -H "Authorization: Bearer $TOKEN" http://<mac>:8899/agents | jq`
  from any machine on the tailnet at that moment. **Done when:** the raw JSON for
  `quirky-cannon-a7cab9` and `mesh-brain` is saved to the change folder, showing which generator
  produced them and whether the name carries a `cmux:` prefix.
- [ ] 0.2 Reconcile against `iOS/TerminalView.swift:590` (`.disabled(session.isCmux)`). If the
  rows are not `cmux:`-prefixed, the 1008 path is reached by a route this design has not
  accounted for — stop and revise the design before proceeding. **Done when:** a one-paragraph
  finding is appended to `design.md` Open Question 2 marking it resolved.
- [ ] 0.3 Reproduce the second screenshot's failure separately: "isn't answering — nothing has
  loaded yet" with CPU/Mem/State `—`. **Done when:** you can state whether it is daemon-
  unreachable or the same 1008, with the `curl` output that proves it.

## 1. Make 1008 unreachable by construction (highest value, smallest diff)

- [ ] 1.1 Constrain `listAgents()` in `install/payload/meshd/server.ts:355` so every emitted
  session name is a bare `#{session_name}` containing no colon. **Done when:**
  `curl -s -H "Authorization: Bearer $TOKEN" localhost:8899/agents | jq -r '.[].name' | grep ':'`
  prints nothing and exits 1.
- [ ] 1.2 Add `scripts/check-session-names.sh` asserting the same invariant against a live
  daemon. **Done when:** the script exits 0 on a clean daemon, and exits non-zero when a session
  named `a:b` is created by hand.
- [ ] 1.3 **[DEVICE]** Confirm on the phone that no row now fails with `closed (1008)`.
  **Done when:** every row in the Terminal tab either opens a live terminal or is visibly marked
  unopenable.

## 2. Delete cmux

Ordering note from `design.md`: this moved to the front. cmux's socket is refused on the owner's
machine today, so nothing observable is lost.

- [ ] 2.1 Delete `install/payload/meshd/cmux-bridge.ts`, `install/payload/hooks/cmux-bridge.zsh`,
  `install/payload/bin/start-cmux-bridge`, `install/payload/bin/start-cmux-bridge-inner.zsh`.
  **Done when:** `grep -rn "cmux" install/payload/ | grep -v Binary` returns only `server.ts`
  hits still pending in 2.2.
- [ ] 2.2 Remove from `server.ts`: capability string `"cmux"` (`:27`), constants (`:31-33`),
  `isCmuxAgent`/`cmuxSurfaceRef`/`cmuxEnv`/`cmuxEnvPrefix` (`:211-232`), `cmuxJson` (`:235-253`),
  `cleanCmuxLine` (`:274-277`), `cmuxBridgeReady`/`ensureCmuxBridge` (`:279-300`, the latter is
  dead code that discards its result), `cmuxSessions` (`:302-352`), `cmuxPanes` (`:362-390`),
  `cmuxOutput` (`:392-413`), `CMUX_KEYS`/`cmuxSend` (`:415-444`), and dispatch at
  `:126-134,355-359,448,490-493,506,515,521,560`. **Done when:** `bun run install/payload/meshd/server.ts`
  starts clean and `curl -s localhost:8899/health | jq -r '.capabilities[]'` no longer lists `cmux`.
- [ ] 2.3 Remove installer coupling: `install/install.sh:511-517` (the `~/.zshrc` source line and
  hook copy), `:597,606,729,775-776`. **Done when:** a fresh `install.sh` run on a scratch user
  writes no line to `~/.zshrc` — verify with `git diff` on a copy of the file before/after.
- [ ] 2.4 Remove Swift coupling: `Shared/Models.swift:314` (`isCmux`), `iOS/ContentView.swift:361,1197,1299`,
  `iOS/TerminalView.swift:67,78,403,506,590,620,623,641-642,653`, `Watch/WatchViews.swift:482`,
  `Shared/AgentNotifications.swift:45`. The six `!session.isCmux` gates become unconditional —
  this is a net gain, the phone stops hiding New pane / Kill / page keys. **Done when:**
  `grep -rn "isCmux\|cmux" --include=*.swift . ` returns nothing.
- [ ] 2.5 Retire `scripts/check-bridge-kill-scope.sh` and drop `cmux` from
  `scripts/check-daemon-gaps.swift:16` and `scripts/check-daemon-050.sh:60`. **Done when:**
  `./scripts/check-all.sh` (or the repo's equivalent runner) passes with no skipped cmux checks.
- [ ] 2.6 Fix the latent bug found during the audit: `install/payload/bin/mesh:185` reads
  `a.isCmux`, a wire field meshd has never emitted. **Done when:** `mesh ls` output is verified
  correct against `curl .../agents`.

## 3. Give herdr a day-one path (no daemon change)

- [ ] 3.1 Verify the workaround by hand: `rmux new-session -d -s herdrui 'herdr'`, then
  `rmux capture-pane -p -t herdrui | head -40`. **Done when:** the capture shows herdr's live
  workspaces, confirming the client attached to the existing `default` server.
- [ ] 3.2 **[DEVICE]** Open that session from the phone's Terminal tab and drive it. **Done when:**
  you can move between herdr panes and type into one from the phone. Record which herdr prefix
  chords do not survive the nesting.
- [ ] 3.3 Document it in `README.md` and as a first-class action in the app's New-session flow
  (`POST /agents/new {cmd:"herdr"}`). **Done when:** the app offers it without the user typing a
  command string.

## 4. Runtime adapter and `SessionRef`

- [ ] 4.1 Add the adapter module in `install/payload/meshd/` with the six verbs from `design.md`
  D3, and tmux + rmux implementations. **Done when:** `MESH_MUX=tmux` and `MESH_MUX=rmux` both
  list, capture and send against live sessions — prove with a `cd /etc` then `pwd` round trip
  returning `/etc` on each.
- [ ] 4.2 Introduce `SessionRef { runtime, target }` on the wire, additively. **Done when:**
  `curl .../agents | jq '.[0]'` shows both fields and an old client (previous app build) still
  lists sessions unchanged.
- [ ] 4.3 Add the untagged-session inference path for daemons predating this change, reported as
  inferred. **Done when:** pointing the app at a meshd 0.5.1 host still lists and opens sessions,
  and `curl .../doctor | jq` states the runtime was inferred.
- [ ] 4.4 Assert no multiplexer binary is named outside the adapter. **Done when:**
  `scripts/check-mux-isolation.sh` exits 0, and exits non-zero if `rmux` is reintroduced into
  `rmux-bridge/src/server.ts`.

## 5. Point the bridge at the adapter

- [ ] 5.1 Replace `runRmux` in `install/payload/rmux-bridge/src/server.ts:58-73` with adapter
  dispatch resolved from the session's declared runtime. **Done when:** attaching an rmux session
  and a tmux session both stream live output through the same bridge build.
- [ ] 5.2 Cache the last successful resolution so a daemon restart does not kill a live terminal.
  **Done when:** restarting meshd mid-session leaves an open terminal streaming — verify by
  typing after the restart.
- [ ] 5.3 Rename `rmux-bridge` to a runtime-neutral name across the payload, installer and Swift
  `resolvedBridge`. **Done when:** a fresh install pairs and opens a terminal end to end.

## 6. Surface every failure natively

- [ ] 6.1 Post WebSocket close codes from the bridge page to native via `WKScriptMessageHandler`.
  **Done when:** `console` in the web view is no longer the only place the code appears.
- [ ] 6.2 Map `1008` and `1011` onto `WebLoadPhase.failed` in `iOS/TerminalView.swift` with a
  human sentence naming the runtime. **Done when:** forcing a close (attach a session then kill
  it from the host with `rmux kill-session -t <name>`) shows the full-screen error with Retry,
  not a black rectangle.
- [ ] 6.3 Add the attachability guard `ManualBridgeScreen` (`iOS/TerminalView.swift:183`) is
  missing. **Done when:** typing a colon-bearing session name there produces the error state
  rather than a blank terminal.
- [ ] 6.4 Mark unattachable rows in the list with the reason, before the tap. **Done when:** a
  host with herdr panes shows them listed and marked read-only, and `factory` shows unmarked.

## 7. Stop the Terminal tab from clipping

- [ ] 7.1 Fix the session detail header: stat cards (`CPU` rendering as `PU`) and the `sessi`
  cut-off. **Done when:** **[DEVICE]** a screenshot at the narrowest supported width shows every
  label whole. Compare against the owner's 2026-08-29 screenshot as the before.
- [ ] 7.2 Wrap "Latest output" instead of clipping both edges. **Done when:** a long line renders
  wrapped or scrolls in its own container, and the page does not scroll horizontally.
- [ ] 7.3 Add `.safeAreaInset(edge: .bottom)` so scroll views clear the floating tab bar.
  **Done when:** the last row of the session list is fully visible when scrolled to the end.
- [ ] 7.4 Fix the detached swipe-to-delete trash button that renders over the row above.
  **Done when:** **[DEVICE]** swiping a session row shows the control aligned to that row.

## 8. Make it visible from the host

- [ ] 8.1 Extend `GET /doctor` to report every runtime present, whether the attach path can reach
  it, and how many listed sessions are affected. **Done when:** `curl .../doctor | jq` on the
  owner's Mac names rmux (attachable), herdr (read-only), tmux (no server), and cmux
  (unsupported), explaining the disappeared rows.
- [ ] 8.2 **Acceptance.** **[DEVICE]** Open the session from the owner's 2026-08-29 screenshot —
  `quirky-cannon-a7cab9` — from the phone and type into it. **Done when:** a command typed on the
  phone executes and its output appears. This, not a passing build, closes the change.

## 9. herdr read/send adapter (durable fix, after the above ships)

- [ ] 9.1 Implement the herdr adapter over `herdr pane list`, `herdr pane read --lines N --source
  recent-unwrapped`, `herdr pane send-text`. **Done when:** `curl .../agents` lists the six live
  herdr panes with their `cwd` and `agent_status`.
- [ ] 9.2 Pin against `herdr api schema` and fail loudly on mismatch rather than listing nothing.
  **Done when:** corrupting the expected schema makes `/doctor` report herdr as failing, and the
  session list does not silently shrink.
- [ ] 9.3 **[DEVICE]** Read a herdr agent pane from the watch. **Done when:** the agent's output
  is legible on the wrist and a reply can be sent to it.
