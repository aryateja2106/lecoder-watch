## ADDED Requirements

### Requirement: Nothing is moved or removed before it is preserved

No repository, worktree or directory SHALL be moved, archived, pruned or deleted until its
contents exist on a remote that is not this laptop.

An inventory on 2026-08-29 found live production code with no remote at all:
`shop/1-projects/agentfirst-platform` (36 commits, serving a live Vercel deployment) and
`shop/agentfirst-platform-gift-redesign` (24 commits). The owner intends to clean this machine.
Consolidation that begins by tidying destroys work; consolidation that begins by pushing cannot.

#### Scenario: A working copy with no remote

- **WHEN** a repository in scope is found to have no configured remote
- **THEN** a remote SHALL be created and all branches pushed
- **AND** no consolidation step SHALL run against that repository until the push is confirmed

#### Scenario: A working copy with unpushed commits

- **WHEN** a repository has commits not present on its remote
- **THEN** those commits SHALL be pushed before the repository is moved or archived

#### Scenario: The rescue is verifiable in one command

- **WHEN** the rescue step is claimed complete
- **THEN** a single command SHALL enumerate every in-scope repository and report any that has
  no remote or has unpushed commits
- **AND** it SHALL exit non-zero while any remain

#### Scenario: A worktree holding uncommitted work

- **WHEN** worktrees are pruned
- **THEN** a worktree containing uncommitted changes SHALL NOT be removed
- **AND** it SHALL be reported for the maintainer to resolve by hand

### Requirement: One workspace root

The product's source SHALL live in a single repository, and that repository SHALL be the one
that ships.

`lecoder-watch` is at 0.5.x with 189 commits; `LeSearch-AI/mesh` has one commit at 0.4;
`mesh-install`'s payload carries 3 files where `lecoder-watch` has 20. Choosing a root that is
not the shipping one would mean migrating away from the only working copy.

#### Scenario: A new contributor finds the product

- **WHEN** someone looks for the source of the daemon, the iOS app, the watch app, the
  installer or the landing page
- **THEN** all of them SHALL be in the workspace root repository
- **AND** no other repository SHALL be required to build or release the product

#### Scenario: The daemon still has exactly one shipping copy

- **WHEN** the workspace is searched for the daemon's source
- **THEN** exactly one copy SHALL exist
- **AND** an automated check SHALL fail if a second appears

### Requirement: A big part is a versioned package

Code that is worked on independently SHALL be a package with its own version, and consumers
SHALL depend on a declared version rather than on a path into someone else's source tree.

This is the owner's stated requirement: "if we need to really work on any big parts we can build
packages of them, version them and start using them as necessary."

#### Scenario: A package changes without unpinning everything

- **WHEN** one package is modified and released
- **THEN** consumers SHALL be able to adopt the new version independently
- **AND** unrelated packages SHALL NOT require a version change

#### Scenario: Package boundaries are enforced

- **WHEN** a package imports from another package
- **THEN** it SHALL do so through that package's declared entry point
- **AND** an automated check SHALL fail on a reach-through into another package's internals

### Requirement: The workspace excludes what is not the product

Third-party clones, personal configuration and client work SHALL NOT be part of the workspace.

53 of the 106 repositories found on disk are third-party clones, including 17 nested inside
`gitrepo-kb`. They are re-cloneable and would dominate the workspace. Personal knowledge
(`SecondBrain`, `dotfiles`, `infra`) and client engagements are separately owned and separately
sensitive.

#### Scenario: A vendored reference repository

- **WHEN** a third-party repository is cloned for reference
- **THEN** it SHALL live outside the workspace
- **AND** an automated check SHALL fail if a nested `.git` directory appears inside the workspace

#### Scenario: Client work stays out

- **WHEN** client engagement code exists on the machine
- **THEN** it SHALL NOT be folded into the product workspace

### Requirement: Retired repositories are archived, never deleted

A repository removed from active use SHALL be archived with its history intact and readable.

Roughly 40 repositories are being retired, several of which are earlier generations of the
current product. Their history is the only record of decisions already made and reversed.

#### Scenario: Retiring a repository

- **WHEN** a repository is retired
- **THEN** it SHALL be marked archived rather than deleted
- **AND** its commit history SHALL remain readable

#### Scenario: A retired repository is still referenced

- **WHEN** a retired repository is referenced by a live deployment or another repository
- **THEN** it SHALL NOT be archived until that reference is moved
