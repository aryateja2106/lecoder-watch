## Why

One product is spread across 8 local checkouts and at least 14 GitHub repositories in 3
namespaces. The owner's words:

> "Our current development setup is very confusing. We have multiple landing pages, multiple
> assets, multiple things which are built all over the place, but we don't have a single
> folder or single workspace which is consolidated... We have a web app which is deployed at
> [lecoder.lesearch.ai], we have a second app, they are in various github repo and it's just
> maintained by me. I want us either consolidate everything we have built into a single
> monorepo and if we need to really work on any big parts we can build packages of them,
> version them and start using them as necessary."

An inventory taken 2026-08-29 measured the scale:

- **106 real git repositories** on disk under `/Users/aryateja` (plus ~36 linked worktrees),
  53 of them in the owner's own namespaces.
- **~183 GitHub repositories** across 12 accounts and orgs; 149 in namespaces he controls.
- **7 live deployments**, all on Vercel.
- **5 duplicate clusters**. The largest is the agent-control product itself, existing as
  `lecoder-watch`, `lecoder`, `lecoder-mconnect`, `lecoder-desktop`, `lecode`,
  `lecoder-planning`, `lecoder-vscode`, `mconnect2`, `lesearch`, `lesearch-ai`,
  `lesearch-factory`, `lesearch-protocol`, `mesh`, `meshwatch`, `mesh-install`.

Three findings make this urgent rather than merely untidy.

**1. Live code exists in exactly one place: this laptop.** `shop/1-projects/agentfirst-platform`
has **36 commits and no git remote** while serving a live Vercel deployment.
`shop/agentfirst-platform-gift-redesign` has **24 unpushed commits** and exists nowhere else.
`hk-explore/*`, `Personal-Software-Factory/factory`, `Personal-skills`, `infra`, `dotfiles`,
`portfolio-voice-livekit` and `apify-research` are likewise remote-less. The owner stated he is
about to clean this machine. A disk failure or an `rm` today destroys shipped work.

**2. The public artifact has already drifted from source.** `LeSearch-AI/mesh` is a hand-cut
snapshot at 0.4 with a single commit, while `lecoder-watch` ships 0.5.x. Their `web/index.html`
differ by 8KB. Because the snapshot is cut by hand, it drifts every release and nothing detects
it. Users install from the stale one.

**3. Nobody can redeploy `agentfirst.shop`.** Its Vercel project is outside the owner's only
team (`aryateja2106-projects`), so it is unreachable from the account that owns every other site.

Why now: the owner has stated the audience will not recommend the product because it is
unstable and unmaintained. Instability is downstream of this. There is no single place to run
tests, no single release path, and 12 owned checkouts are parked on `backup/2026-07-02`
branches. Work cannot be reviewed, regression-tested or released consistently across 14 repos
maintained by one person.

## What Changes

- **`lecoder-watch` becomes the monorepo root.** It is the only repository currently shipping
  (0.5.x, 189 commits, last push 2026-08-27) and already contains the apps, the daemon, the
  installer payload and the live `mesh.lesearch.ai` site.
- **Rescue first, restructure second.** Every remote-less repository with unpushed commits gets
  a remote and a push **before any move, delete or cleanup happens**. This is the first task and
  it gates everything.
- **Product code folds in as versioned packages.** `lecoder`'s superset packages (`cli`,
  `cloud`, `mesh`, `model-gateway`, `server`, `shared`) and the satellite libraries (`lescout`,
  `lepet`, `lockshell`, `leguard`, `lememory`, `cmem`, `lescreen`, `lecoder-tunnel`) become
  packages in one workspace, each independently versioned, so a "big part" can be worked on and
  released without unpinning everything else.
- **BREAKING: ~40 repositories are archived.** Eleven dead re-founds of the same product
  (`lecode`, `lecoder-desktop`, `lecoder-vscode`, `lecoder-planning`, `mconnect2`, `lesearch-ai`,
  `LeSearch-AI/lesearch`, `lesearch-protocol`, `lesearch-platform`, `Old-product`,
  `MConnect-Specs`), the one-off experiments, the Shopify-era AgentFirst attempts, and the
  legacy hackathon namespaces. Archived, not deleted — history is preserved and read-only.
- **Published artifacts are generated, never hand-edited.** `LeSearch-AI/mesh` (the public
  snapshot) and `LeSearch-AI/mesh-install` (the curl one-liner payload) become build outputs of
  the monorepo. Their URLs are load-bearing and do not change.
- **Deployments are mapped and consolidated into one Vercel scope**, with each live domain
  traced to a known path in the monorepo.
- **Third-party clones never enter the monorepo.** 53 vendored/reference clones
  (`gitrepo-kb`'s 17 nested repos, `reference-projects`, `tools/*`, `lab/*`) stay out and are
  re-cloneable.
- **Personal and client work stays separate.** `Desktop/Personal-Agent-Set-up`, `dotfiles`,
  `infra`, `SecondBrain`, and `clients/*` are the wrong shape for a product monorepo and are
  explicitly excluded.

## Capabilities

### New Capabilities

- `workspace-layout`: What the single workspace contains and what it excludes — the root, where
  apps live, where packages live, what qualifies as a package, how packages are versioned and
  depended upon, and the rule that no third-party clone or personal-config repo enters it.
- `published-artifacts`: The contract for anything published outside the monorepo — the public
  snapshot repo, the installer payload, and the deployed sites. Each SHALL be generated from
  monorepo source by a repeatable command, SHALL be detectably stale when it drifts, and SHALL
  keep its existing public URL.

### Modified Capabilities

None. This change relocates code and establishes release mechanics; it does not alter the
behaviour of the daemon, the apps, or the terminal-sessions capability.

## Impact

**Repositories**
- Root: `aryateja2106/lecoder-watch`.
- Folded in: `lecoder` (packages), `lecoder-mconnect` (`apps/web` only, until
  `lecoder.lesearch.ai` is re-pointed), `lesearch-factory`, 8 satellite libraries, and the two
  unpushed AgentFirst working copies.
- Kept as generated outputs: `LeSearch-AI/mesh`, `LeSearch-AI/mesh-install`.
- Kept separate: `nl2shell` org (distinct product, own live site), `cloudagi-website` (revenue
  business front door), `ATR-main-portfolio` (already its own turbo monorepo), client work.
- Archived: ~40 repositories listed above.

**Deployments** — 7 live domains, currently: `lecoder.lesearch.ai`, `mesh.lesearch.ai`,
`lesearch.ai`, `cloudagi.ai`, `aryateja.com`, `agentfirst.shop`, `nl2shell.com`. Each must keep
serving throughout; the build source changes, the domain does not.

**Local working copies** — ~36 linked worktrees and roughly a dozen duplicate checkouts are
pruned. One of them is the worktree this change was written in; the pruning task must not delete
a worktree with uncommitted work.

**Risk concentrated in one place** — this change moves a large amount of code. Every step is
ordered so that nothing is deleted before it is provably preserved somewhere else.

**Not affected** — no runtime behaviour. The daemon's HTTP surface, the apps' features, and the
install command a user pastes all stay identical.

## Non-goals

- **Fixing any product bug.** The broken terminal is `one-session-runtime`; the screen redesign
  and remote-access work are their own changes. This change must not become the place where
  features get repaired in passing.
- **A build-system rewrite.** Adopt the smallest workspace tooling that manages the packages;
  do not migrate to a new bundler, task runner or CI platform as part of this.
- **Merging the personal knowledge base, dotfiles, infra or client work.**
- **Absorbing `nl2shell`.** A separate product with its own live domain keeps its own org.
- **Renaming the product or its public URLs.** `mesh.lesearch.ai` and the installer URL are
  load-bearing for existing users.
- **Deleting anything.** Archive, which is reversible. Deletion is never required by this change.

## Target user

Two distinct users, and conflating them is how this sprawl happened.

**The maintainer is a solo builder**, so every ongoing cost must survive one person with no
reviewer. That is the argument for consolidation over discipline: 14 repositories require
14 places to remember to run tests, and a hand-cut public snapshot requires remembering to cut
it. Both have already failed. The workspace must make the correct action the default one, not
one that depends on the maintainer's memory.

**The end user is non-technical** and never sees this repository. Their only contact with it is
the pasted install command and the app they download. Therefore: no public URL may change, and
the installer must keep working identically throughout every step of the migration. If a user
notices this change happened, it went wrong.
