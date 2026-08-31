## Context

See `proposal.md` for the measured inventory. The facts that drive every decision here:

- `lecoder-watch` has **no root `package.json`** (`git show main:package.json` → does not exist).
  There is no workspace today, only a Swift project plus a Bun daemon under
  `install/payload/meshd/` with its own private manifest.
- **Bun 1.3.14 is already installed and is already the daemon's runtime.** It has native
  workspaces.
- Two live sites have **no git remote at all** and 36 + 24 unpushed commits respectively.
- The public snapshot `LeSearch-AI/mesh` is a hand-cut single-commit 0.4 against a 0.5.x source.
- One person maintains all of it, with no reviewer.

The last fact is the design constraint, not a footnote. Any mechanism whose correctness depends
on the maintainer remembering to do something has already failed here twice — the hand-cut
snapshot drifted, and production code went unpushed. Mechanisms must be checkable by a command.

## Goals / Non-Goals

**Goals:**

- Nothing is lost. The rescue precedes everything and is verifiable in one command.
- One repository builds and releases the product.
- Independently-worked parts are versioned packages with enforced boundaries.
- Published artifacts are generated, and their drift is detectable without republishing.
- Every live domain has a traced source path and a deploying account.
- Retired repositories are archived, reversibly.

**Non-Goals:**

- Fixing product bugs. `one-session-runtime` owns the terminal.
- A build-system migration. No new bundler, task runner or CI platform.
- Absorbing `nl2shell`, personal config, or client work.
- Changing any public URL.
- Deleting anything.

## Decisions

### D1: Bun workspaces, not Turborepo or Nx

*Why:* Bun is already the runtime and is already installed; a root `package.json` with a
`workspaces` array adds zero dependencies. The project's own convention is "no deps beyond what
is already vendored." Turborepo would be a new tool to learn and maintain for a workspace whose
task graph is currently one daemon and a handful of libraries.

*Alternatives:*
- *Turborepo* — used by `ATR-main-portfolio`, so there is precedent. Rejected here: its value is
  remote caching and task orchestration across many packages, and this workspace does not have
  that problem yet. Adoptable later without rework, since Bun workspaces are a subset.
- *Nx* — heavier still, and generator-oriented in a way that fights an existing layout.
- *No workspace tool, just directories* — rejected: the versioning requirement in
  `specs/workspace-layout` needs real package resolution, not relative imports.

### D2: The Swift apps stay where they are, outside the package graph

`Watch/`, `iOS/`, `Shared/`, `MeshDesktop/` and `project.yml` are not npm packages and gain
nothing from being modelled as such. They stay as directories at the workspace root, built by
XcodeGen as today.

*Why:* A monorepo does not require one dependency graph. Forcing Swift into a JS workspace would
add ceremony with no resolution benefit — Swift already has no cross-module version problem here
because everything is compiled together.

*Consequence:* "workspace" means one repository, not one package manager. The checks in
`specs/workspace-layout` are written against the repository, not against `bun install`.

### D3: Rescue is a separate, gated phase — it is not step one of the migration, it is a
prerequisite to it

A single script enumerates every in-scope repository and reports any with no remote or unpushed
commits, exiting non-zero while any remain. No move, archive or prune runs until it exits zero.

*Why:* The failure mode being designed against is concrete and imminent: the owner said he is
cleaning this machine while two live sites exist only on it. Ordering is the entire mitigation.
A migration plan that says "be careful" is not one.

*Alternative rejected:* pushing opportunistically as each repository is touched. That leaves the
untouched ones — the dead-looking ones, the ones most likely to be deleted during a cleanup —
unprotected for longest.

### D4: Move history with `git subtree`, not by copying files

Folding `lecoder`'s packages and the satellite libraries in preserves their commit history via
`git subtree add`.

*Why:* These are earlier generations of the current product. Their history is the record of
decisions already made and reversed — the proposal notes eleven dead re-founds. A file copy
turns years of context into one "import" commit, which is precisely the information a solo
maintainer with no reviewer cannot afford to lose.

*Trade-off:* Repository size grows, and the history is interleaved. Acceptable: `lecoder-watch`
is 10.4 MB and the folded repositories are small.

*Alternative considered:* `git filter-repo` per package for a cleaner graft. More correct, much
slower, and the cleanliness buys nothing a solo maintainer will use.

### D5: Published artifacts become build outputs with a `--check` mode

One command publishes; the same command with `--check` compares the published artifact against
source and exits non-zero on drift, without writing anything.

*Why:* The staleness requirement needs detection that is cheap enough to run in CI and safe
enough to run anywhere. Splitting publish and check into two implementations would let them
disagree — which is how the snapshot drifted in the first place.

*Applies to:* `LeSearch-AI/mesh` (public snapshot), `LeSearch-AI/mesh-install` (installer
payload). Both keep their existing URLs — they are load-bearing for users who paste the install
command.

### D6: Migrate deployments last, and verify by requesting the live URL

Each live domain is re-pointed at its monorepo path only after the rescue and the folding are
complete, and each is verified with `curl` against the public domain rather than a green build.

*Why:* This is the project's own hard-won rule — a green build is not evidence. Two features
have already shipped correct-but-dead in this codebase.

*Ordering within this step:* `mesh.lesearch.ai` first, because its source (`web/`) is already in
the root repository, so it is the cheapest test of the whole mechanism. `lecoder.lesearch.ai`
last, because the inventory could not determine whether it builds `apps/web` or `apps/website`.

### D7: Archive, with a stated exception check

Retirement is `gh repo archive`. Before archiving, a check confirms nothing live references the
repository.

*Why:* Archiving is reversible and preserves history; deletion satisfies no requirement here.
The reference check exists because `lecoder-mconnect` is on the retire list *and* currently
builds a live site — exactly the case that would otherwise take a domain down.

## Risks / Trade-offs

- **The cleanup happens before the rescue** → D3 gates it, and the check is one command. This is
  the highest-severity risk in the change and the reason the rescue is phase zero.
- **Archiving a repository that still serves a domain** → D7's reference check; `lecoder-mconnect`
  is the known instance and is explicitly held back.
- **`lecoder.lesearch.ai` source is ambiguous** (`apps/web` vs `apps/website`, both have
  `vercel.json`) → resolved by inspection before the move, not guessed. Marked UNVERIFIED in the
  inventory and must stay marked until confirmed.
- **`agentfirst.shop` is unreachable from the owner's Vercel team** → it cannot be migrated until
  the owning scope is identified. Blocks only that one domain; recorded as an exception if it
  cannot be resolved.
- **Pruning a worktree with uncommitted work** → the prune step refuses and reports instead. Note
  that this change is itself being written inside one of ~36 worktrees.
- **Subtree merges make history harder to read** → accepted (D4); the alternative loses it.
- **Scope creep into fixing bugs while moving code** → the Non-Goals list, and the rule that this
  change alters no runtime behaviour. A bug found during the move becomes an issue, not a commit.
- **Migration stalls half-done**, leaving two structures at once → every phase is independently
  valuable and independently revertible. The rescue alone is worth doing even if nothing else
  follows.

## Migration Plan

0. **Rescue.** Remote + push everything remote-less or unpushed. Gate: the check exits zero.
1. **Establish the workspace.** Root `package.json` with Bun workspaces; no code moves yet.
2. **Fold in** product packages and satellites via `git subtree`, one at a time, each verified
   buildable before the next.
3. **Generate published artifacts** from source; run `--check` against the current hand-cut
   snapshot to measure the existing drift before overwriting it.
4. **Migrate deployments**, `mesh.lesearch.ai` first, verified against the live URL.
5. **Prune** duplicate checkouts and stale worktrees.
6. **Archive** retired repositories, after the reference check.

**Rollback:** phases 1–3 add without removing; the old repositories still exist and still build.
Phase 4 is revertible per-domain by re-pointing. Phase 6 is reversible (`gh repo unarchive`).
Only phase 5 removes anything, and it removes only local duplicates of pushed remotes.

## Open Questions

1. **Which app builds `lecoder.lesearch.ai`** — `apps/web` or `apps/website`? Both carry
   `vercel.json`. Needs the Vercel dashboard or a `vercel project inspect` that reveals the git
   link; the inventory could not determine it without logging in.
2. **Which account serves `agentfirst.shop`?** Not in `aryateja2106-projects`. Until known, that
   domain cannot be migrated.
3. **Are `shlawgathon` (26 repos), `redxam`, `Tech4Aqua-Shrimp`, `Linkedin-cold-outreach` owned
   or membership-only?** Determines whether they can be archived or merely left.
4. **Do the 8 satellite libraries have external consumers?** If any is depended on outside the
   workspace, folding it in changes its install path. Assumed none; confirm before folding.
5. **Does `lesearch-factory` belong as a package or stay a separate tool?** It is live in the
   maintainer's daily workflow, which argues for folding it in, but it is process tooling rather
   than product code.
