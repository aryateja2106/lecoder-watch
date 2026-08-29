# Terminal Sessions Specification

## Purpose

Let someone drive a real, persistent shell on a machine they own, from an Apple Watch or an
iPhone, well enough to start an AI coding agent in a project and keep working with it.

This is the capability the product is named for, and the one that was reported as "clean but
unusable". The daemon side was never the problem; the clients were not wired to it. These
requirements exist so that gap cannot silently reopen.

## Requirements

### Requirement: A session outlives the app

A session SHALL be a detached multiplexer session on the host, and SHALL continue running when every client disconnects.

Closing the app, locking the watch, or losing the network does not end the work.

#### Scenario: State persists between calls
- **WHEN** a client sends `cd /etc` to a session, and later sends `pwd`
- **THEN** the output SHALL show `/etc`

#### Scenario: A session survives the client
- **WHEN** a session is created and the app is force-quit
- **THEN** the session SHALL still appear in `GET /agents` and its output SHALL be readable

### Requirement: The multiplexer is the user's choice

The daemon SHALL work with any tmux-compatible multiplexer selected by `MESH_MUX`, and SHALL NOT privilege one in code.

The daemon speaks the tmux command vocabulary, so tmux, rmux, herdr and zellij all qualify.

#### Scenario: An unavailable multiplexer is reported, not hidden
- **WHEN** `MESH_MUX` names a binary that is not installed
- **THEN** `GET /doctor` SHALL report the multiplexer check as failing and name the binary
- **AND** the session list SHALL NOT silently appear empty as though the user had no work

### Requirement: Any program on the host is launchable from any client

A client SHALL be able to start a session running an arbitrary command, in an arbitrary working directory.

Not a fixed menu of blessed programs. `herdr`, `tmux`, `python3`, a script, anything.

#### Scenario: Launching an arbitrary command from the watch
- **WHEN** the user opens New › Command… on the watch and enters `herdr --help`
- **THEN** a session SHALL start running that command
- **AND** its output SHALL be readable without further navigation

#### Scenario: Starting inside a workspace
- **WHEN** the user selects a working directory before starting a session
- **THEN** the session SHALL start in that directory
- **AND** this SHALL hold whether the client reached the daemon directly or relayed the
  request through the paired iPhone

### Requirement: Every key the daemon accepts is reachable from every client

Every key in the daemon's accepted-key map SHALL be sendable from the watch and the phone, and the agreement SHALL be enforced by an automated check.

`KEY_SEND_KEYS` is the contract. A key the daemon accepts but no client can send is a
defect, not a missing nicety — it is what made an interactive TUI undrivable from the wrist.

#### Scenario: Driving a full-screen program
- **WHEN** a full-screen program is running in a session
- **THEN** the client SHALL be able to send arrow keys, tab, escape, page up, page down,
  home, end, backspace, ctrl-c and ctrl-d

#### Scenario: The contract is enforced mechanically
- **WHEN** a key is added to the daemon's map and no client sends it
- **THEN** `scripts/check-watch-terminal-wiring.sh` SHALL fail

### Requirement: Output is read as text, not as pixels

Session output SHALL be delivered and rendered as text rather than as a screen capture.

`capture-pane` text is legible at any size; a screenshot of a terminal is not. Text is also
orders of magnitude cheaper over a phone relay.

#### Scenario: Reading a session on a watch
- **WHEN** a session is opened on the watch
- **THEN** its output SHALL be rendered as selectable monospaced text at an adjustable size
- **AND** the view SHALL follow new output without the user scrolling

### Requirement: The user is told what each control does

Every screen SHALL offer a help affordance reachable in one tap that explains its controls in plain language.

A wrist UI with no help is unusable however correct it is.

#### Scenario: Discovering the interface
- **WHEN** the user is on a machine's screen
- **THEN** a help affordance SHALL be reachable in one tap
- **AND** it SHALL explain sessions, launching a command, the key bar and dictation in
  plain language, without jargon

## Known gaps

These are true today and deliberately recorded rather than hidden.

- **Line wrapping.** A detached session's pty defaults to 80 columns, so `capture-pane`
  returns text hard-wrapped at column 80, breaking mid-word on a watch. Narrowing the pty
  would help the watch and cramp every TUI and the phone. Unresolved: needs an owner
  decision, not a patch.
- **Relay-path output latency.** When the watch cannot reach a daemon directly, watched
  output refreshes on the phone's ~6s general poll rather than its own faster loop.
- **`delete` (forward delete)** is accepted by the daemon and has no watch affordance, by
  choice — there is no sensible wrist gesture for it.
