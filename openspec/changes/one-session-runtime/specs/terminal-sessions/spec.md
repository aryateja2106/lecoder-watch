## MODIFIED Requirements

### Requirement: The multiplexer is the user's choice

The daemon SHALL work with any tmux-compatible multiplexer selected by `MESH_MUX`, and SHALL NOT privilege one in code.

The daemon speaks the tmux command vocabulary, so tmux, rmux, herdr and zellij all qualify.

This SHALL hold for the interactive attach path as well as the daemon's read path. The two
diverged in the shipped build: `meshd` honoured `MESH_MUX` when listing sessions while
`rmux-bridge` hardcoded `rmux` when opening them, so sessions from any other runtime were
listed and then refused. A multiplexer named anywhere outside the runtime adapter is a defect.

#### Scenario: An unavailable multiplexer is reported, not hidden
- **WHEN** `MESH_MUX` names a binary that is not installed
- **THEN** `GET /doctor` SHALL report the multiplexer check as failing and name the binary
- **AND** the session list SHALL NOT silently appear empty as though the user had no work

#### Scenario: The read path and the attach path agree
- **WHEN** a session is listed by the daemon
- **THEN** the component that opens an interactive terminal SHALL use the same runtime that
  listed it
- **AND** SHALL NOT substitute a runtime of its own choosing

#### Scenario: No component hardcodes a multiplexer
- **WHEN** the daemon and the interactive-terminal component are searched for multiplexer
  binary names
- **THEN** every occurrence SHALL be inside the runtime adapter
- **AND** an automated check SHALL fail if one appears elsewhere

## ADDED Requirements

### Requirement: A listed session is attachable or is marked as not attachable

Every session presented to a client SHALL either be openable, or SHALL be presented as not
openable together with the reason.

On the owner's own machine, six of eight listed sessions could not be opened, and nothing in
the list distinguished them from the two that could. Offering an action that cannot succeed is
worse than not offering it: the user concludes the product is broken, which is the conclusion
the owner and his audience both reached.

#### Scenario: Every offered session opens

- **WHEN** the session list is shown and no row is marked as unopenable
- **THEN** opening any row SHALL produce a live terminal for that session

#### Scenario: A session whose runtime is absent

- **WHEN** a session's runtime is not installed on the host
- **THEN** the row SHALL be marked as not openable and SHALL name the missing runtime

## REMOVED Requirements

### Requirement: cmux workspaces are enumerated as sessions

**Reason**: cmux is a heavyweight workspace application being used only to enumerate panes,
and every session it contributed was unopenable — its refs were passed to a different
multiplexer, which rejected them. It is a large dependency carried for rows that never worked.

**Migration**: Sessions previously discovered through cmux disappear from the list. Work
running inside cmux remains untouched on the host and is unaffected; it is simply no longer
listed. A user who wants those sessions on the phone runs them under a runtime the adapter
supports (tmux, rmux or herdr). `GET /doctor` SHALL name cmux as unsupported if it is
detected on the host, so the disappearance is explained rather than silent.
