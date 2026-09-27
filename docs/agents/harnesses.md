# Agent harnesses: how each CLI talks to mesh

Date: 2026-09-22. Sources: the per-CLI probes (docs, binary strings, on-disk config, logs; no interactive session was started for fx, cursor-agent or pi) and the mesh contract in `install/payload` (`server.ts`, `chat.ts`, `handoff.ts`, `bin/mesh-hook`, `Shared/Models.swift`). Confidence per row: **measured** = observed on this Mac, **docs** = docs + strings only. Anything marked *unverified* has not been seen on a live pane.

## A. Adapter matrix

| CLI (installed where) | needs-input signal | done signal | prompt shapes | keys (accept / decline / mode / newline / interrupt) | what mesh does today | biggest gap |
|---|---|---|---|---|---|---|
| **claude** 2.1.274 (`~/.local/bin/claude` → `~/.local/share/claude/versions/2.1.274`; measured) | `Notification` hook, `notification_type` = `permission_prompt` \| `idle_prompt` \| `agent_needs_input`; `PermissionRequest` hook can answer structurally (`{tool_name,tool_input,tool_use_id}` in, `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"approve"}}}` out) | `Stop` hook (`stop_reason:"end_turn"`, `last_assistant_message`); headless: last stream-json line `{"type":"result"}` | numbered menu `❯ 1. Yes / 2. Yes, and don't ask again… / 3. No, and tell Claude what to do differently (esc)`; unnumbered trust list + `Enter to confirm · Esc to cancel`; plan approval menu | Enter / Esc / Shift+Tab (tmux `BTab`) / `\` then Enter (universal) or `M-Enter` / Esc (Ctrl+C twice exits) | `mesh hooks install` writes `Notification`+`Stop` (no matcher) → `mesh-hook --source claude`; chat reads `~/.claude/projects`; handoff resumes with `claude --resume <id>` | every notification type lands as "Claude needs attention"; Stop cards have no text; approvals go through send-keys, not `PermissionRequest` |
| **fx** 0.0.10 (`~/.local/bin/fx`; never signed in, no `~/.fx`; docs) | none from a plain pane. Herdr socket `pane.report_agent {state:"blocked"}` when `HERDR_SOCKET_PATH`/`HERDR_PANE_ID` are set; terminal bell on `attention_required`. Only in `ask` mode (default `auto` never prompts) | bell on `turn_end`; Herdr `state:"idle"`; `fx ask` = process exit (`--json` one object) | `Permission request` + `1. Yes, and tell fx what to do next / 2. Yes, and don't ask again… / 3. No, and tell fx what to do differently`; headless `Approve? [y/N]`; MCP trust `[1] approve [2] approve all [3] reject` | option 1 (Enter or digit, *unverified*) / option 3 or `n` / `/permissions ask\|auto\|full-access` / Shift+Enter, Alt+Enter, `\`+Enter / Esc (may need Esc again), Ctrl+C on empty draft | detection only (`AGENT_CLIS`); row label is bare "fx"; herdr lane maps blocked→waiting; chat = capture-pane fallback | no signal path at all; default mode hides prompts; not logged in |
| **cursor-agent** 2026.09.10 (`~/.local/bin/cursor-agent`, node wrapper; signed in as a non-Arya account; docs) | no dedicated event. `beforeShellExecution` / `beforeMCPExecution` / `preToolUse` fire before the prompt; hook stdout `{"permission":"ask"}` keeps the TUI prompt | `stop` hook `{status:"completed"\|"aborted"\|"error"}`; `afterAgentResponse`; headless last line `{"type":"result"}` | keyed rows, not numbered: `Run (once) (y) / Add Shell(...) to allowlist? (tab) / Run Everything (shift+tab) / Skip & tell the agent what to do instead (esc or n)`; trust dialog `[a] Trust / [w] … / [q] Quit` | `y` or Enter / `n` or Esc (`p` = reject & propose) / Shift+Tab Agent→Plan→Ask / Shift+Enter or Ctrl+J / Ctrl+C once | label "Cursor"; chat + handoff read `~/.cursor/projects/<slug>` (slug computed wrong); imports `~/.claude/settings.json` hooks so the mesh Stop hook fires as a mislabelled "Claude event" | transcript slug mismatch; no `~/.cursor/hooks.json` install; launched without `--trust` |
| **agy** 1.2.7 (`~/.local/bin/agy`; hooks in `~/.gemini/config/hooks.json`; measured) | no hook. Log line `Surfacing tool confirmation: "<Tool>" at step N` in `~/.gemini/antigravity-cli/cli.log`; `PreToolUse` fires before but does not say whether a prompt follows | `Stop` hook `{terminationReason:"model_stop", fullyIdle:true}` (stdout MUST be JSON, e.g. `{"decision":""}`); `PostInvocation` | unnumbered pickers: `Run this command?` → `Yes, run command / Yes, and always allow… / No, deny / No, and tell <agent> what to do next`; `Accept this file edit?` → `Yes, accept this change / No, reject this change`; trust `Yes, I trust this folder` | ↑/↓ + Enter / Esc / Shift+Tab request-review→accept-edits→plan / Shift+Enter or Ctrl+J / Esc (Ctrl+C twice exits) | in `AGENT_CLIS` and `HANDOFF_TARGETS` (launched bare, continue sentence typed after); no events, no chat, no resume | no hooks.json install; mesh-hook prints no JSON; default mode stalls on every file write |
| **pi** 0.85.1 (`/opt/homebrew/bin/pi`; config `~/.pi/agent`; docs) | core has no permission prompts. Extension events: `ui_prompt_start {kind, title}` around any dialog, `tool_call` gate can block/ask; RPC mode emits `extension_ui_request` | `agent_settled` (truly idle) / `agent_end`; `--mode json` last line `agent_end` then exit | framed select `Yes / No` with footer `enter select • esc cancel`; trust select `Trust / Trust parent folder / Trust (this session only) / Do not trust / …` | Enter (Yes is first) / ↓ Enter or Esc / none (Shift+Tab cycles thinking) / Ctrl+J (Shift+Enter needs tmux extended-keys) / Esc (Ctrl+C = clear, then exit) | `mesh-hook --source pi` title branch exists; nothing installs an extension; not a handoff target; no transcript reader; label raw "pi" or "Node" | no `~/.pi/agent/extensions/mesh.ts` |

Codex (reference only, from the contract): `notify = [mesh-codex-notify]` posts "Codex turn ended" (level info) with no `session`/`replyable`, so it clears nothing unless `MESHD_SESSION` is set.

## B. The repeatable workflow (onboard any CLI)

1. **Install the signal.** Register one hook, notify command or extension that runs `~/.mesh/bin/mesh-hook --source <cli>` on "needs input" (level `warning`/`needs-input`) and on "turn ended" (level `info`). The pane must be inside tmux/rmux so mesh-hook can resolve `#S` (`mesh-hook:64-89`); outside a mux it posts `replyable:false` and the phone shows no buttons. Where the CLI has no hook (fx today), a tmux `monitor-bell` hook or a wrapper (`mesh-agent-run <cli> …`) is the fallback. Registration lives in `bin/mesh` `mesh hooks install` (`:1385-1455`), one block per CLI.
2. **Verify the event fields.** Trigger one prompt and one finished turn, then `mesh events` (or `GET /events`). Check: `session` equals the name `/agents` lists; `level` is in `WAITING_LEVELS` (`server.ts:989`); `replyable` is not `false`; `sessionId` is either always present or never (`Models.swift:718-723` matches by it first); `pane` is `#S:#I.#P`; `body` ≤ 500 chars carries the question. The row must read `waiting`, then `working`/`idle` after the info event.
3. **Prove Approve from the phone.** With a real prompt open, tap Allow (sends `enter`) and Deny (sends `escape`) from the DecisionCard, then `tmux capture-pane` to confirm the option that was taken. If the CLI's prompt does not accept Enter/Esc as accept/decline, record the real keys here and in `KEY_SEND_KEYS` (`server.ts:631-650`). Green builds do not count; this step is the gate (AGENTS.md rule 1).
4. **Add the prompt regex.** Extend `AgentMenu.parse` (`Shared/Models.swift:1591-1685`) and `waitMarkers` (`:1557`) from a captured pane snapshot, and keep the snapshot as a fixture. Section D lists the shapes.
5. **Register the CLI.** `AGENT_CLIS` (`meshd/doctor.ts:47`), `agentLabel` / `mapAgent` (`server.ts:230-241`), `HANDOFF_TARGETS` + `launchCommand` + `RESUME_KIND` (`handoff.ts:29,51-68`), a `chat.ts` source if it writes a readable transcript, and `event_title` in `bin/mesh-hook:36-51`.
6. **Add a check.** New `scripts/check-<cli>-hook.sh` (never edit an existing `check-*`): feed the hook a canned stdin JSON, assert the posted event has `session`, a waiting `level` and `replyable:true`; plus a parser test that `AgentMenu.parse` recognises the fixture from step 4. Wire it into `check-all.sh` by adding the new script, not by changing others.

## C. Ranked gaps (file to touch)

**claude**
1. Notification types are not read: add `"matcher":"permission_prompt|idle_prompt|agent_needs_input"` at `bin/mesh:1431`, or branch on `notification_type` in `mesh-hook:106-107` (auth_success, elicitation_*, quota_* must not become "needs attention").
2. Stop cards are empty: read `last_assistant_message` in `mesh-hook:127`.
3. Structural approvals: add `PermissionRequest` to `HOOK_EVENTS` (`bin/mesh:1391`) and a mesh-hook branch that posts the event, waits (bounded by the hook `timeout`) for the phone's answer, and prints the `hookSpecificOutput` decision. This removes the dependence on pane focus and TUI layout.
4. Newline fallback: `KEY_SEND_KEYS` `shift-enter` → `M-Enter` (`server.ts:648`) is untested on plain Terminal.app; `\` then Enter is the documented universal path.
5. Trust and bypass dialogs fire before any hook: only capture-pane sees them (`Quick safety check`, `WARNING: Claude Code running in Bypass Permissions mode`); `skipDangerousModePermissionPrompt` (already set) covers the second only.

**fx**
1. Sign in (`fx login` / `fx setup` / `AI_GATEWAY_API_KEY`): human step, nothing works before it. This worktree's `.mcp.json` also triggers the project-MCP trust prompt at startup.
2. Prompts never reach a human in default `auto` mode: spawn with `FX_PERMISSION_MODE=ask` in the new-session path (`server.ts:1434-1475`) or via `mesh-agent-run`.
3. No signal path: cheapest is tmux `monitor-bell` + `set-hook -g alert-bell` → `POST /events` (needs `FX_SOUND=on`, default on macOS); cleaner is a meshd-owned Herdr-compatible socket (`HERDR_SOCKET_PATH`, wire format from strings, *unverified*); cleanest is spawning `fx acp` and answering its permission requests. Pick one in `server.ts`.
4. Labels: `agentLabel`/`mapAgent` (`server.ts:230-241`) and `herdrAgentType` (`herdr.ts:141-149`) show "fx"/"shell".
5. Chat and resume via `fx session --id <id> --json` / `fx ask --resume last`: `chat.ts`, `handoff.ts` (later).

**cursor-agent**
1. Slug mismatch (one line): `cursorProjectSlug` at `chat.ts:74` must do `path.replace(/[^a-zA-Z0-9]/g,"-").replace(/-+/g,"-").replace(/^-+|-+$/g,"")`; `handoff.ts:164` uses it. Every `.claude/worktrees/*` cwd currently finds no transcript.
2. Add `--trust` to the launch (`handoff.ts:58`, `server.ts:1434`): an untrusted cwd blocks on the a/w/q dialog before any hook runs.
3. Write `~/.cursor/hooks.json` from `mesh hooks install` (`bin/mesh:1385-1455`): `stop` → `mesh-hook --source cursor`, `beforeShellExecution` + `beforeMCPExecution` → mesh-hook that posts the event and prints `{"permission":"ask"}`. In `mesh-hook`: a `cursor` title branch, lowercase `hook_event_name`, `cwd` from `workspace_roots[0]`.
4. Mislabelled "Claude event" from the Claude-hook import: detect `cursor_version` in stdin (`mesh-hook:148-152`) and relabel.
5. The existing superset hook answers `{"continue":true}` (not the documented `permission` schema); test whether it pre-empts a mesh hook (`~/.cursor/hooks.json`, human-owned).
6. The IDE worker puts its API key on the `ps` command line; `cmdTable()` reads it. Add a `redact.ts` test case and rotate the key.

**agy**
1. `mesh hooks install` writes a `mesh` entry into `~/.gemini/config/hooks.json`: `Stop` (+ `PreToolUse` matcher `run_command`) → `mesh-hook --source agy`. mesh-hook must print a JSON object on stdout for agy (`{}` / `{"decision":""}`) and gain an `agy` title branch (`mesh-hook:36-51`).
2. Needs-permission has no hook: tail `~/.gemini/antigravity-cli/cli.log` for `Surfacing tool confirmation` in `server.ts`, or rely on the capture-pane regex (D.7). Log tail is measured; the pane marker is *unverified*.
3. Launch: `handoff.ts:63` should pass `--mode accept-edits -i "<prompt>"` instead of bare + typed sentence, or every file write stalls on `Accept this file edit?`.
4. Resume: add `agy` to `RESUME_KIND` (`handoff.ts:68`) using `-c` / `--conversation <id>`; id source `cache/last_conversations.json` (format *unverified*).
5. Chat: read the per-workspace `transcript.jsonl` the hook payload names (`transcriptPath`) in `chat.ts` (format *unverified*).
6. `agy --remote-control` is Google's own phone path; check it does not fight the mesh pane before shipping.

**pi**
1. Ship `~/.pi/agent/extensions/mesh.ts` from `mesh hooks install` (`bin/mesh:1385-1455`), copying `superset-hooks.ts`: `agent_settled` → `mesh-hook --source pi` with `{"hook_event_name":"Stop"}`, `ui_prompt_start` → `{"hook_event_name":"Notification","title":e.title}`; gate on `ctx.hasUI`.
2. Confirm the pane label with one live pane (`ps -o command=` first token; `agentFromTree` `server.ts:901-913`), then add `pi` to `agentLabel`/`mapAgent` (`:230-241`).
3. Handoff/resume: `HANDOFF_TARGETS` + `launchCommand` + `RESUME_KIND` (`handoff.ts:29,51-68`) with `pi -c` / `pi --session <id>`.
4. Chat: parser for `~/.pi/agent/sessions/--<cwd with / as ->--/<ts>_<uuid>.jsonl` (tree via `id`/`parentId`) in `chat.ts`.
5. A `tool_call` gate (from `examples/extensions/permission-gate.ts`) only if a watch Approve is wanted; core pi never asks.

## D. Prompt-detection spec

Shared rules (already in `AgentMenu.parse`, `Shared/Models.swift:1631-1685`): strip ANSI `\x1B\[[0-9;]*m` and trailing spaces, read only the last 25 lines, require ≥ 2 option rows, and treat a menu as open only while the session is `waiting` or the footer/question line is still in the tail. After sending keys, re-capture and require the menu to be gone before reporting success. Selecting option `k` when option `h` is highlighted: `Down×(k−h)` (Up when negative) then `Enter` (`keys(toPick:)`, `:1608-1613`); for typed prompts send the letter as text (`text(toPick:)`). Digit shortcuts are listed where the CLI documents or plausibly renders them; none is proven.

1. **Claude Code numbered menu** (measured)
   ```
    Do you want to proceed?
    ❯ 1. Yes
      2. Yes, and don't ask again for git commands in /Users/aryateja/x
      3. No, and tell Claude what to do differently (esc)
   ```
   Option line: `^\s*(❯|>)?\s*(\d{1,2})\.\s+(\S.*)$` (`:1623`); rows must be contiguous and count from 1; exactly one carries the marker; `h` = the `❯` row (Yes by default). Accept = Enter; decline = Esc (equals the `(esc)` row) or move to the `No…` row + Enter. Digit `k` picks option `k`: *plausible, unverified*. Tab on Yes/No opens a comment field: do not send Tab from the phone.
2. **Claude trust / unnumbered marked list** (marker measured, label text *unverified*)
   ```
      Yes, I trust this folder
    ❯ No, exit
    Enter to confirm · Esc to cancel
   ```
   Marker row `^\s*(❯|>)\s+(\S.*)$` (`:1625`); siblings sit at the same indent or indent+2; a footer line is required, matched by one of `Enter to confirm`, `Esc to cancel`, `Tab to amend`, `to cycle` (`:1627`). Enter = highlighted row; Esc = cancel/exit. The "Quick safety check" workspace-trust screen is skipped under `-p` and non-TTY; whether it renders a `❯` list is *unverified*, the footer is the anchor.
3. **y/N prompts** (regex measured; fx text from strings)
   Last non-empty line matches `\((y/n|Y/n|y/N)\)\s*:?\s*$|\[(y/n|Y/n|y/N)\]\s*:?\s*$` case-insensitive (`:1626`). Default = the capital letter; bare Enter takes it. fx headless: `Approve? [y/N] ` on stderr (trailing space, trim first) → `y` Enter accepts, `n` or Enter declines. Answer is typed text, never a cursor move.
4. **fx permission prompt** (strings + docs, *unverified* rendering)
   ```
    Permission request
    Reason: shell command requires approval
    1. Yes, and tell fx what to do next
    2. Yes, and don't ask again for this exact command
    3. No, and tell fx what to do differently
   ```
   Rows match the numbered regex, but the numbered branch requires one marked row; if fx prints no `❯`/`>` the parser returns nil and only `waitMarkers` (`"1. yes"`, `:1557-1560`) flips the status. Accept = option 1 (Enter on the default, or `1`; *unverified*); decline = option 3 (or `3`). MCP trust variant: `[1] approve  [2] approve all  [3] reject  [esc] dismiss` — digits are the documented keys here. Add fx to the marker class only after one captured pane.
5. **Codex approval prompt** (*unverified*: no Codex pane was captured in this pass)
   Expected from the Rust TUI: a boxed `Codex wants to run …` / `Would you like to run…?` block with rows like `1. Yes (y)` / `2. Yes, and don't ask again this session (a)` / `3. No, and tell Codex what to do differently (esc)`, marker possibly `›` (U+203A). `›` is not in the marker class `(❯|>)`; extend to `(❯|›|>)` once a capture confirms. Hotkeys `y` / `a` / Esc are plausible; Enter on the highlighted row is the safe default. Capture one pane before writing the regex.
6. **cursor-agent approval** (strings, *unverified* rendering)
   Rows are keyed, not numbered: `Run (once) (y)`, `Add Shell(<cmd>) to allowlist? (tab)`, `Run Everything (shift+tab)`, `Skip & tell the agent what to do instead (esc or n)`; MCP/Write variants add `(p)`. Detect with `\((y|n|p|q|tab|shift\+tab|esc or n)\)\s*$` on ≥ 2 trailing rows; select by typing the letter (`y` accept, `n`/Esc decline), Enter also submits the highlighted row. Trust dialog rows `[a] Trust this workspace` / `[w] …` / `[q] Quit`: `^\s*\[([awq])\]\s`.
7. **agy pickers** (labels verbatim from the binary, marker *unverified*)
   Anchors: `Run this command\?`, `Accept this file edit\?`, `Allow (creation of this file|access to this (file|URL)|calling this tool|sandbox bypass)\?`, `Approve this action\?`, `trust the contents of this project\?`. Rows are unnumbered (`Yes, run command`, `No, deny`, …); if agy prints a `❯`/`>` marker the unnumbered branch applies and its `(shift+tab to cycle)` footer already matches `to cycle`. Accept = Enter (first row), decline = Esc or the `No, deny` row + Enter. `y`/`n` (`confirm.yes`/`confirm.no`) and `1`/`2` exist as actions but their default keys are unproven; the log line `Surfacing tool confirmation` (D.7 measured) is the reliable "open" signal.
8. **pi select / confirm** (bundle-verified widget, frame text *unverified*)
   Rows `Yes` / `No` under `<title>\n<message>`, footer `enter select • esc cancel`. Add `esc cancel` to `footerWords` (`:1627`) so the unnumbered branch accepts it. Enter = Yes (first row), ↓ Enter or Esc = No. In RPC mode skip the screen entirely: answer `extension_ui_request` with `{"type":"extension_ui_response","id":…,"value":"Yes"}`.

Order of evaluation stays as coded: numbered list, then marked list with footer, then trailing y/N. Every new shape needs a captured-pane fixture before its regex ships.
