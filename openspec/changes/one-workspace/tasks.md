Every task ends in something runnable. **[ARYA]** marks tasks needing account access an agent
does not have (Vercel dashboard, GitHub org admin). Phase 0 gates everything — no task from any
later phase runs until 0.4 exits zero.

## 0. Rescue — nothing moves until this passes

- [ ] 0.1 Create a remote and push `shop/1-projects/agentfirst-platform` (36 commits, no remote,
  serving a live Vercel deployment). **Done when:** `git -C shop/1-projects/agentfirst-platform
  log origin/HEAD -1` resolves and matches local HEAD.
- [ ] 0.2 Same for `shop/agentfirst-platform-gift-redesign` (24 commits, branch
  `feat/gift-first-redesign`). **Done when:** the branch is visible on GitHub.
- [ ] 0.3 Same for the remaining remote-less repositories: `hk-explore/main`, `hk-explore/mcp-ui`,
  `Personal-Software-Factory/factory`, `Personal-skills`, `infra`, `dotfiles`,
  `portfolio-voice-livekit`, `gitrepo-kb`, `apify-research`. Push `dotfiles` and `infra` to
  **private** repositories — they may contain host details. **Done when:** each has an origin.
- [ ] 0.4 **The gate.** Write `scripts/check-unpushed.sh` that walks every in-scope repository and
  exits non-zero if any has no remote or unpushed commits, naming each. **Done when:**
  `./scripts/check-unpushed.sh` exits 0. Until then, no later task starts.
- [ ] 0.5 Push the 12 owned checkouts parked on `backup/2026-07-02` branches so the branch exists
  on origin. **Done when:** 0.4 still exits 0 and each branch resolves remotely.

## 1. Establish the workspace (no code moves)

- [ ] 1.1 Add a root `package.json` with Bun workspaces. There is none today —
  `git show main:package.json` fails. **Done when:** `bun install` completes at the root and
  `bun pm ls` lists `install/payload/meshd`.
- [ ] 1.2 Confirm the Swift build is untouched by the new root manifest. **Done when:**
  `xcodegen generate && xcodebuild -scheme MeshWatch -destination generic/platform=iOS build`
  succeeds — the same command that worked before 1.1.
- [ ] 1.3 Add `scripts/check-no-nested-repos.sh` asserting no `.git` directory exists inside the
  workspace other than the root. **Done when:** it exits 0, and exits non-zero after
  `git init /tmp/x && cp -r /tmp/x ./probe`.
- [ ] 1.4 Add `scripts/check-single-daemon.sh` asserting exactly one copy of the daemon source.
  The project has lost a feature to a second copy before. **Done when:** it exits 0 and fails
  when `install/payload/meshd` is duplicated.

## 2. Fold in product packages (one at a time, history preserved)

Use `git subtree add`, not file copies — these are earlier generations of the same product and
their history is the record of decisions already reversed.

- [ ] 2.1 Confirm none of the 8 satellite libraries has an external consumer (design Open
  Question 4). **Done when:** `gh search code` for each package name across your namespaces
  returns no dependent manifest, or the dependents are listed.
- [ ] 2.2 Fold `aryateja2106/lecoder` packages — `cli`, `cloud`, `mesh`, `model-gateway`,
  `server`, `shared`. It is the superset (93 files in `packages/cli/src` vs 80 in
  `lecoder-mconnect`). **Done when:** `bun install` resolves and each package's own test or start
  script runs from the workspace root.
- [ ] 2.3 Fold the satellites: `lescout`, `lepet`, `lockshell`, `leguard`, `lememory`, `cmem`,
  `lescreen`, `lecoder-tunnel`. **Done when:** `bun pm ls` lists all 8 and `git log --follow` on
  a file in each reaches its original history.
- [ ] 2.4 Decide and act on `lesearch-factory` (design Open Question 5 — package or separate
  tool). **Done when:** the decision is recorded in `design.md` and executed.
- [ ] 2.5 Enforce package boundaries. **Done when:** `scripts/check-package-boundaries.sh` exits
  0, and exits non-zero on a deep import into another package's internals.

## 3. Generate published artifacts

- [ ] 3.1 Write the publish command for the public snapshot `LeSearch-AI/mesh`, generating it
  wholly from workspace source. **Done when:** running it twice on an unchanged workspace
  produces byte-identical output.
- [ ] 3.2 Add `--check` to the same command. **Done when:** run against today's hand-cut snapshot
  it exits non-zero and names the drift — expected to report 0.4-vs-0.5.x and the ~8KB
  `web/index.html` difference. **Record that output**; it is the measurement of how bad the
  hand-cutting got.
- [ ] 3.3 Same publish + `--check` for `LeSearch-AI/mesh-install`. Its payload has 3 files where
  source has 20. **Done when:** `--check` reports the gap, then publish closes it.
- [ ] 3.4 **The install command must not break.** Run the documented curl one-liner against a
  scratch user or VM after 3.3. **Done when:** a working daemon is installed and
  `curl -s localhost:8899/health` returns 200. Not a green build — an installed daemon.
- [ ] 3.5 Wire `--check` for both artifacts into CI. **Done when:** a deliberate source change
  without a republish turns CI red.

## 4. Migrate deployments (verify against the live URL, never the build)

- [ ] 4.1 **[ARYA]** Resolve Open Question 1: does `lecoder.lesearch.ai` build `apps/web` or
  `apps/website`? Both carry `vercel.json`. **Done when:** the answer is recorded in `design.md`.
- [ ] 4.2 **[ARYA]** Resolve Open Question 2: which Vercel account serves `agentfirst.shop`? It
  is not in `aryateja2106-projects`, so nobody on that team can redeploy it. **Done when:** the
  scope is identified, or the exception is recorded with its reason.
- [ ] 4.3 Re-point `mesh.lesearch.ai` at the workspace path first — its source (`web/`) is
  already in the root repo, making it the cheapest test of the mechanism. **Done when:**
  `curl -sI https://mesh.lesearch.ai` returns 200 and the page reflects a change you just made.
- [ ] 4.4 Re-point the remaining domains one at a time, `lecoder.lesearch.ai` last. **Done when:**
  each returns 200 from its public URL after the move.
- [ ] 4.5 Record the mapping table — domain → workspace path → build command → deploying account
  — with anything unconfirmed marked UNVERIFIED. **Done when:** all 7 live domains have a row and
  no row is silently guessed.

## 5. Prune local duplicates

- [ ] 5.1 Prune stale worktrees, refusing any with uncommitted work. **Note:** this change was
  authored inside one of ~36 worktrees. **Done when:** `git worktree list` shows only live ones
  and the refusal path is proven by leaving a dirty worktree in place.
- [ ] 5.2 Remove duplicate checkouts of repositories already pushed: `work/lesearch/mconnect`,
  `Projects/codex-vnc-rewrite`, `Projects/mesh-install` (2 months behind its own remote),
  `Desktop/Work/personal-website` (11 commits behind), the 4 `ATR-main-portfolio/.worktrees/release-*`,
  and the duplicated research clones. **Done when:** 0.4 still exits 0 afterwards.
- [ ] 5.3 Re-run the inventory. **Done when:** the local repository count has dropped and every
  remaining one is either the workspace, a kept-separate repo, or a re-cloneable third party.

## 6. Archive retired repositories

- [ ] 6.1 Reference check before any archive. **Done when:** `scripts/check-archive-safe.sh`
  reports no live deployment or workspace dependency for each candidate — and correctly **holds
  back `lecoder-mconnect`**, which is on the retire list but still builds a live site.
- [ ] 6.2 Archive the 11 dead product re-founds: `lecode`, `lecoder-desktop`, `lecoder-vscode`,
  `lecoder-planning`, `mconnect2`, `lesearch-ai`, `LeSearch-AI/lesearch`, `lesearch-protocol`,
  `lesearch-platform`, `Old-product`, `MConnect-Specs`. **Done when:** each shows archived on
  GitHub and its history is still readable.
- [ ] 6.3 Archive `meshwatch` / `meshwatch-publish` (unrelated clean-slate history, dead since
  2026-06-17) and the one-off experiments: `Lecoder-Claude-code-statusline`, `Lecoder-PAI`,
  `LeCoder-cgpu-CLI`, `karna`, `claude-agent-monitor`, `agenthub`. **Done when:** archived.
- [ ] 6.4 Archive the CloudAGI duplicates (`cloudagi`, `synthesis-cloudagi`,
  `CloudAGI-AI/cloudagi-terminal`, `CloudAGI-AI/swarm-marketplace`) — keeping `cloudagi-website`,
  which serves the live revenue site. **Done when:** `curl -sI https://cloudagi.ai` still returns
  200 after archiving the other four.
- [ ] 6.5 Archive the Shopify-era AgentFirst attempts and the already-self-archived
  `shop/4-archive/*`. **Done when:** `curl -sI https://agentfirst.shop` still returns 200.
- [ ] 6.6 **[ARYA]** Resolve Open Question 3 — are `shlawgathon` (26 repos), `redxam`,
  `Tech4Aqua-Shrimp`, `Linkedin-cold-outreach` yours to archive? **Done when:** answered, then
  archived or left with the reason recorded.
- [ ] 6.7 Archive `lecoder-mconnect` **only after** 4.4 moves `lecoder.lesearch.ai` off it.
  **Done when:** the domain serves from the workspace and the repo is archived.

## 7. Close out

- [ ] 7.1 Update `README.md` and `AGENTS.md` to describe one workspace. **Done when:** a reader
  following them can build the apps and the daemon without visiting another repository.
- [ ] 7.2 Final verification. **Done when:** all 7 domains return 200, the install one-liner
  produces a working daemon, `check-unpushed.sh` exits 0, and both artifact `--check` commands
  exit 0.
