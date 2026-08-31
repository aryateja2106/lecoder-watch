## ADDED Requirements

### Requirement: Every published artifact is generated from workspace source

Anything published outside the workspace — the public snapshot repository, the installer
payload, and each deployed site — SHALL be produced by a repeatable command run against the
workspace, and SHALL NOT be edited in its published location.

`LeSearch-AI/mesh` was cut by hand. It sits at 0.4 with a single commit while the source ships
0.5.x, and its `web/index.html` differs from source by roughly 8KB. Hand-cutting drifts on every
release, and nothing noticed for a week.

#### Scenario: Regenerating the public snapshot

- **WHEN** the publish command for the public snapshot is run
- **THEN** the snapshot SHALL be produced entirely from workspace source
- **AND** running it twice against an unchanged workspace SHALL produce an identical result

#### Scenario: An artifact edited in place

- **WHEN** a published artifact has been modified outside the workspace
- **THEN** the next publish SHALL either overwrite it or fail with the difference named
- **AND** the modification SHALL NOT be silently preserved

### Requirement: Drift between source and published artifacts is detectable

A published artifact that no longer matches workspace source SHALL be reported as stale by a
command, without republishing it.

The staleness that shipped was invisible: nothing compared the public snapshot to source, so
users installed 0.4 while 0.5.x existed. Detection must not require remembering to look.

#### Scenario: The published snapshot falls behind

- **WHEN** the workspace has changed since the snapshot was last published
- **THEN** a staleness check SHALL report it and name what differs
- **AND** SHALL exit non-zero

#### Scenario: Everything is current

- **WHEN** every published artifact matches workspace source
- **THEN** the staleness check SHALL exit zero

### Requirement: Public URLs survive consolidation

Every URL an existing user or installer depends on SHALL continue to resolve to equivalent
content throughout and after the migration.

The install command is pasted by non-technical users and is the product's entire onboarding.
The seven live domains are the product's only public presence. A consolidation the user notices
has failed.

#### Scenario: The install one-liner during the migration

- **WHEN** the documented install command is run at any point during the migration
- **THEN** it SHALL install a working daemon
- **AND** its URL SHALL be unchanged

#### Scenario: A live domain after its source moves

- **WHEN** a deployed site's build source is relocated into the workspace
- **THEN** the domain SHALL continue to serve
- **AND** the change SHALL be verified by requesting the live URL, not by a successful build

### Requirement: Every live deployment maps to a known source path

Each live domain SHALL have a recorded, verified mapping to the workspace path and build command
that produces it, and to the account that can deploy it.

The inventory could not determine which of two Next apps builds `lecoder.lesearch.ai` — both
`apps/web` and `apps/website` carry a `vercel.json`. `agentfirst.shop` deploys from a scope
outside the owner's only team, so no member of that team can redeploy it. A deployment nobody
can trace is one nobody can fix.

#### Scenario: Tracing a live domain

- **WHEN** any live domain is examined
- **THEN** the workspace path, build command and deploying account SHALL be recorded
- **AND** an unverified mapping SHALL be marked as unverified rather than assumed

#### Scenario: A deployment outside the owning account

- **WHEN** a live deployment is served from an account the maintainer's primary scope cannot reach
- **THEN** it SHALL be moved into that scope, or the exception SHALL be recorded with the reason
- **AND** it SHALL NOT be left undocumented
