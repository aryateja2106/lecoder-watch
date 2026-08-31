## ADDED Requirements

### Requirement: A session declares the runtime that can attach it

Every session the daemon reports SHALL carry an explicit runtime tag and an explicit target,
and clients SHALL NOT infer either by parsing the session's display name.

The shipped defect is exactly this inference: `meshd` emitted `herdr:wA:p2`, and `rmux-bridge`
handed that string to `rmux has-session -t`, which read it as session `herdr`, window `wA` —
a session that has never existed. A colon-delimited name is not a contract. A tagged pair is.

#### Scenario: Sessions are reported with their runtime

- **WHEN** a client requests the session list from a daemon
- **THEN** each session SHALL include the runtime that owns it and the target string that
  runtime accepts
- **AND** no client SHALL need to split the display name on `:` to determine either

#### Scenario: A daemon too old to tag its sessions

- **WHEN** a session arrives with no runtime tag, from a daemon predating this change
- **THEN** the runtime SHALL be inferred from that machine's `MESH_MUX`
- **AND** `GET /doctor` SHALL state that the value was inferred rather than reported
- **AND** the session SHALL remain listed and attachable if the inference is correct

### Requirement: The attach path resolves through the session's own runtime

The component that opens an interactive terminal SHALL dispatch on the session's declared
runtime, and SHALL NOT name a multiplexer binary of its own.

`install/payload/rmux-bridge/src/server.ts:238` calls `rmux has-session` for every session
regardless of origin. That single hardcoded binary is why six of eight listed sessions on the
owner's machine cannot be opened.

#### Scenario: A herdr session opens through herdr

- **WHEN** a session whose runtime is `herdr` is opened
- **THEN** the attach SHALL be performed using herdr
- **AND** the session's live output SHALL appear

#### Scenario: An rmux session opens through rmux

- **WHEN** a session whose runtime is `rmux` is opened
- **THEN** the attach SHALL be performed using rmux
- **AND** the session's live output SHALL appear

#### Scenario: No multiplexer binary is named outside the adapter

- **WHEN** the source of the daemon and the bridge is searched for multiplexer binary names
- **THEN** every occurrence SHALL be inside the runtime adapter
- **AND** an automated check SHALL fail if a new one appears elsewhere

### Requirement: A session that cannot be attached is never offered as though it can

A session that the host cannot attach SHALL be visually distinguished in the list before it
is tapped, and SHALL state why.

Today every row looks identical and carries the same subtitle. The user learns which rows are
real only by tapping each one and waiting for a black screen. The owner, who built the system,
could not tell them apart either.

#### Scenario: An unattachable session is marked in the list

- **WHEN** the session list is shown and a session's runtime is not present on the host
- **THEN** that row SHALL be marked as not openable
- **AND** the row SHALL name the missing runtime
- **AND** tapping it SHALL explain the cause rather than opening a terminal that will die

#### Scenario: An attachable session is not marked

- **WHEN** a session's runtime is present and reports the session exists
- **THEN** the row SHALL carry no such marking

### Requirement: Every attach failure surfaces natively with its cause

A terminal that fails to attach SHALL present the client's own full-screen error state,
carrying the cause, and SHALL NOT leave the failure to be rendered by the embedded web view.

`iOS/TerminalView.swift` already has this error state — headline, message, URL, Retry — keyed
on `WebLoadPhase`. It never fires here, because the page loads and it is the WebSocket inside
that dies. The result is a black screen with 8-point red text. The comment above that code
says it exists to catch "the failure that looks like success"; this is that failure.

#### Scenario: The bridge rejects the session

- **WHEN** the terminal WebSocket closes with code `1008`
- **THEN** the client SHALL show its full-screen error state
- **AND** the message SHALL say the session could not be attached and name the runtime
- **AND** a Retry control SHALL be offered

#### Scenario: The bridge fails to capture or attach

- **WHEN** the terminal WebSocket closes with code `1011`
- **THEN** the client SHALL show its full-screen error state with the server's stated reason

#### Scenario: A closed socket is never silent

- **WHEN** the terminal WebSocket closes for any reason before the user leaves the screen
- **THEN** the client SHALL surface it
- **AND** a blank terminal body SHALL NOT be the only indication

### Requirement: Setup truth reports the runtime mismatch

`GET /doctor` SHALL report every multiplexer runtime present on the host and, for each,
whether the attach path can reach its sessions.

This class of defect was diagnosable in one command on the host and invisible from the phone.
`/doctor` is the project's stated source of setup truth; it did not cover the seam that broke.

#### Scenario: A runtime that lists sessions but cannot attach them

- **WHEN** a runtime is enumerating sessions and the attach path has no implementation for it
- **THEN** `GET /doctor` SHALL report that runtime as failing
- **AND** SHALL state how many listed sessions are affected

#### Scenario: A healthy host

- **WHEN** every runtime that lists sessions can also attach them
- **THEN** `GET /doctor` SHALL report the session-runtime check as passing

### Requirement: The Terminal tab's screens fit the viewport

No screen in the Terminal tab SHALL clip text or controls horizontally, and scrollable
content SHALL remain reachable underneath floating chrome.

The owner's screenshot shows `PU` where `CPU` belongs, `sessi` cut at the right edge,
`pane list yet.` missing its leading word, and the floating tab bar covering the row beneath
it. This is the "collapsing on my phone, the UI is breaking" report.

#### Scenario: Session detail on the narrowest supported phone

- **WHEN** the session detail screen is shown at the narrowest supported width
- **THEN** every label, stat card and body string SHALL be fully visible or wrapped
- **AND** no text SHALL be cut off at either edge

#### Scenario: Terminal output wraps rather than clips

- **WHEN** captured session output is wider than the viewport
- **THEN** it SHALL wrap or scroll within its own container
- **AND** the surrounding screen SHALL NOT scroll horizontally

#### Scenario: Content is reachable under the tab bar

- **WHEN** a scrollable Terminal-tab screen is scrolled to its end
- **THEN** its final row SHALL be fully visible above the floating tab bar
