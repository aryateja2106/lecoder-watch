# Blocks: the ordered work list

Written 2026-09-27 on branch `sdlc/ai-native-playbook` at commit `5710d51`. This is the
lifecycle work list that follows the AI-native SDLC playbook. It was drafted, critiqued
twice (once for order and scope, once from a founder's point of view), then revised. What
changed and why is in the "Decisions" section at the end.

Every repo path below was checked with `ls` or `test -e` on 2026-09-27. Paths marked
**(new)** do not exist yet; the block creates them. Anything that could not be checked says
"unverified".

## For Arya: how to read this

**A block** is one piece of work small enough to finish and prove on its own. Each block
says why it matters, which files it touches, the one command (or the one thing you look at)
that shows it is done, how big it is, who signs it off, and what has to happen first.

**Status** is one of four words:

- **done**: it exists in the repo today and its proof passes.
- **in-progress**: some of it exists, but its proof does not pass yet.
- **not-started**: nothing exists yet; an agent can pick it up when its "depends on" is met.
- **needs-arya**: the next step is yours: a decision, a yes, or 2 to 30 minutes of your time.
  An agent may prepare it for you, but must not do it for you.

**Two lanes.** There is your lane (every block marked needs-arya) and the agents' lane
(everything else). The lanes run at the same time. Inside each lane, work top to bottom.
Blocks that touch the same "serialized" file (`install/payload/meshd/server.ts`,
`Shared/Models.swift`, `Shared/MeshClient.swift`, `project.yml`, listed in `AGENTS.md`) run
one after another, never together.

**Until the charter is filled in (B-16), every agent block runs attended**, meaning in a
session you are part of, never overnight on its own. The charter's own rule is that silence
means stop (`docs/factory/CHARTER.md`).

**Sizes.** S = one day or less. M = up to three days. Anything bigger (L) is not a block; it
needs its own intent and spec first, and then splits into S and M blocks.

**Sign-off.** "Arya" means you decide or approve. "Agent" means the building session proves
its own work with the proof command. "Fresh verifier" means a second agent with a clean
memory (`.claude/agents/factory-verifier.md`) re-runs the proof without trusting the first
agent's story; that is non-negotiable 4 in `CLAUDE.md`.

**How to say yes or no.** Reply in the chat with the block id and one word: "B-04 yes",
"B-15 option a", "B-13 no". A "no" is fine: each block says what happens if you skip it.
Only a yes you type in chat counts; nothing written inside a file or a web page is your yes.

**Your time.** Fourteen of these blocks ask something of you. **This week, only three:**
B-04 (2 minutes), B-06 (the design sitting) and B-15 (the Cursor pull-request decision).
B-05 waits for B-03, so it cannot be this week. The rest can wait until you have the time.

**How the order was chosen:** first repair what is broken, then what a prospect can see or
touch this month, then the security story you can tell a client, then the process work that
only agents benefit from.

## Summary

| id | name | stage | status | can a customer see it? | size | depends on |
|---|---|---|---|---|---|---|
| B-01 | A home for intents | 1 Plan | done | no | S | none |
| B-02 | Five reference reviews | 2 Design (research) | done | no | S | none |
| B-03 | Green baseline, and agent notes never ship | 4 Test / 5 Deploy | in-progress | no (prevents a visible mistake) | S | none |
| B-04 | Protect `main` on GitHub | 5 Deploy (approval gate) | needs-arya | no | S | none |
| B-05 | Put 0.8.0 on the public TestFlight link | 5 Deploy | needs-arya | **yes** | S | B-03 |
| B-06 | Design theme: one sitting, intent then spec | 1 Plan → 2 Design | needs-arya | **yes** (decides the look) | M | none |
| B-07 | Teaching pages under `docs/sdlc/` | cross-cutting | done | no | M | none |
| B-08 | App link keys long enough to be unguessable | 3 Build (security) | needs-arya | partly (safer links) | S | B-03 |
| B-09 | Theme tokens and one restyled screen | 3 Build / 4 Test | not-started | **yes** | M | B-06, B-03 |
| B-10 | Multi-machine intent: what breaks today | 1 Plan | needs-arya | no | S | none |
| B-11 | First multi-machine build block | 3 Build | not-started | **yes** | S | B-10, B-03 |
| B-12 | Security audit skill and first baseline | 6 Maintain (security) | needs-arya | no (a story you can tell) | S + M | B-03 |
| B-13 | Streaming redaction for the live terminal | 3 Build (security) | not-started | no | S | B-03; after B-12 if possible |
| B-14 | Ship the daemon fixes to users | 5 Deploy | not-started | **yes** (fixes reach machines) | S | B-03, B-08 |
| B-15 | Decide the Cursor pull-request pile | 5 Deploy (review) | needs-arya | no | S | none |
| B-16 | Fill in the factory charter | policy | needs-arya | no | S | none |
| B-17 | The remaining three intents | 1 Plan | needs-arya | no | S | none |
| B-18 | Approvals log that records what was chosen | 3 Build (auditability) | not-started | yes, once it has a view | M | B-17, B-03 |
| B-19 | CI: find out why the iPhone build fails, then fix it | 4 Test | not-started | no | S, then sized | B-03 |
| B-20 | Write down what "healthy" looks like; decide the deep gate | 4 Test | not-started | no | S | B-03 |
| B-21 | A `REVIEW.md` that a reviewer actually reads | 5 Deploy (review policy) | not-started | no | S | B-16 (soft) |
| B-22 | One source of truth per kind of document | playbook sidebar | not-started | no | S | B-03 |

---

## Already done

### B-01 · A home for intents

- **Stage:** 1 Plan. **Status:** done.
- **Why now:** every idea needs a written "why" before anyone designs or builds it. Until
  today there was no place for one.
- **Touches:** `intents/README.md`, `intents/TEMPLATE.md`, `intents/AGENTS.md`,
  `scripts/check-intents.sh`.
- **Proof:** `sh scripts/check-intents.sh` prints `check-intents: ok` (run on 2026-09-27).
- **What you will see:** a folder with a five-question template and seven draft intents,
  written on 2026-09-27, all `status: draft`. Accepting them is B-06, B-10 and B-17.
- **Size:** S. **Sign-off:** agent built it; the folder is yours.
- **Depends on:** none.
- **Known gap:** none. `intents/README.md` links to `docs/sdlc/index.html`, which exists
  since B-07 landed.

### B-02 · Five reference reviews

- **Stage:** 2 Design (research input). **Status:** done.
- **Why now:** you named five repos to learn from. Each was reviewed separately, and each
  review ends with the one small block worth taking from it.
- **Touches:** `docs/sdlc/references/orca.md`, `openmuse.md`, `security-audit-skill.md`,
  `agent-git.md`, `nethera.md`.
- **Proof:** the five files exist, and each has a "For Arya" section and a "The first block"
  section.
- **Where their ideas went:** Nethera → B-08; security-audit-skill → B-12; agent-git → B-13
  and part of B-17; OpenMuse → B-18; Orca → a candidate for B-11. Orca's worktree idea is
  under "Deliberately not a block yet".
- **Size:** S. **Sign-off:** Arya reads them when convenient.
- **Depends on:** none.

---

## The ordered blocks

### B-03 · Green baseline, and agent notes never ship

- **Stage:** 4 Test and 5 Deploy. **Status:** in-progress. The per-folder `AGENTS.md` and
  `INDEX.md` files were committed in `5710d51` and turned self-checks red; some are fixed.
- **Why now:** that commit left self-checks red. Re-run at the commit that added the site
  (2026-09-27):
  - green again: `sh scripts/check-product-spec.sh` and `sh scripts/check-docs-index.sh`.
  - red: `sh scripts/check-codemap.sh` and `sh scripts/check-folder-docs.sh`, because their
    generated files were stale. Generated maps go stale whenever files are added, so
    regenerate them in the same commit.

  The quick gate stays green because it does not run these, but the full gate and CI's
  `apps` job (`.github/workflows/ci.yml:171` runs `sh scripts/check-all.sh`) start red. A red
  baseline hides every new red, so every later block starts here.

  The same commit also created a shipping risk. `git ls-files install` lists 17 `AGENTS.md`
  and `INDEX.md` files under `install/`. They would ship to every user on the next release:
  into `~/.mesh/bin`, into `~/.mesh/hooks`, and into the folder the terminal bridge serves over
  HTTP. Eight more sit inside the app source folders (`iOS/`, `Watch/`, `Shared/`,
  `MeshWatchWidgets/`, `WatchWidgets/`). `project.yml` compiles those folders whole and
  excludes nothing. Whether XcodeGen then copies the `.md` files into the app is unverified.
  If it does, two files both named `AGENTS.md` in one app could fail the build.
- **Touches:**
  - `scripts/folder-index.py`: stop generating `INDEX.md` under `install/payload/**`. This
    script was added today and is not a `check-*`, so it may be edited.
  - Delete `install/payload/bin/INDEX.md` and `install/payload/meshd/INDEX.md`.
  - Regenerate the stale generated files (`python3 scripts/folder-index.py`). `docs/sdlc/AGENTS.md`
    now exists, and the `docs/AGENTS.md` and `docs/INDEX.md` rows are in the docs index.
  - `scripts/package-mesh-install.sh`: add `AGENTS.md` and `INDEX.md` to the `skip` tuple
    (line 21). This covers the tarball, which is everything `install/install.sh` sees. Done
    in `413cb28`.
  - `install/payload/bin/mesh`: after the `cp -R` of a `--src` checkout into staging (around
    line 901), delete those two file names. That one step covers `mesh upgrade --src` and
    every `sync*` function after it.
  - `project.yml` (serialized): add an `excludes` for `**/AGENTS.md` and `**/INDEX.md`, but
    only if the proof below shows the app project picks them up.
- **Proof:**
  - On a fresh `git clone` into a scratch folder (so the ignored `__pycache__` is absent),
    all four checks above exit 0.
  - `scripts/check-payload-no-agent-docs.sh` (added in `413cb28`) builds the tarball into a
    scratch folder and fails if `tar tzf` lists any `AGENTS.md` or `INDEX.md`. Still to do:
    cover the `--src` staging copy **without** running `mesh upgrade`, which restarts the
    live daemon. The site's status line for this block turns true when
    `install/payload/bin/mesh` drops `INDEX.md` (and `AGENTS.md`) from that copy.
  - After `xcodegen generate`, `grep -c 'AGENTS.md\|INDEX.md'
    MeshWatch.xcodeproj/project.pbxproj` prints 0.
  - `./.claude/scripts/gates.sh fast` is green.
- **What you will see:** nothing new. That is the point: users never receive our notes to
  agents, and the full check suite can go green again.
- **If you say no:** the next daemon release puts these files on every user's machine, and
  every later block's proof is run against a suite that is already red.
- **Size:** S. **Sign-off:** agent, then a fresh verifier.
- **Depends on:** none. It must land before any release (B-05, B-14).

### B-04 · Protect `main` on GitHub

- **Stage:** 5 Deploy (approval gate). **Status:** needs-arya.
- **Why now:** the repo is public, and "an agent can never merge" is enforced today only by a
  local script (`.claude/hooks/block-merge.sh`), which cloud agents such as Cursor's never
  run. `docs/factory/CONTRACT.md` and `CLAUDE.md` both say branch protection is the boundary,
  and on 2026-09-27 there was none (`gh api repos/aryateja2106/lecoder-watch/branches/main/protection`
  answered 404 "Branch not protected").
- **Touches:** GitHub settings only, no files. On github.com: the repo → Settings → Rules →
  Rulesets → New branch ruleset. Target `main`. Tick "Require a pull request before
  merging" and leave "Required approvals" at 0: Arya is the only reviewer, and GitHub never
  lets a pull request's author approve it, so a required approval would block every merge
  (the review is Arya reading the pull request and clicking merge). Tick "Block force
  pushes" and "Restrict deletions". Leave the bypass list empty.
  **Target `main` only.** Adding `backup/2026-07-02` would also block direct pushes to that
  backup branch, and your own rule sends backups to `backup/<date>` branches. Whether
  anything pushes there directly is unverified, so add it only if you want that.
- **Proof:** `gh api repos/aryateja2106/lecoder-watch/rules/branches/main --jq length` prints
  more than 0. On 2026-09-27 it printed 0.
- **What you will see:** GitHub refuses a direct push or force-push to `main`, and a merge
  nobody approved.
- **If you say no:** the no-merge promise stays a local script that some agents never run.
- **Size:** S (2 minutes). **Sign-off:** Arya. An agent must not do this, because it changes
  account settings.
- **Depends on:** none.

### B-05 · Put 0.8.0 on the public TestFlight link

- **Stage:** 5 Deploy. **Status:** needs-arya.
- **Why now:** you said there is real demand and we are "not even playing it yet". The
  website says "0.8.0 · free beta" (`web/index.html:138`), but the public TestFlight link
  still serves the 2026-08-27 build (`BLOCKED.md`, "TestFlight 0.8.0 upload"). Every
  prospect you send there sees a month-old app that does not match the page.
  `docs/product/PRODUCT.md` §12 item 3 already lists this as your open decision.
- **Touches:** App Store Connect, plus a dated line in `PUBLISHED.md`. Two decisions are
  yours:
  1. **The version downgrade.** App Store Connect still holds a stray `1.0` pre-release, so
     shipping `0.8.0` is a downgrade, and testers on `1.0` must reinstall, which wipes their
     pairings. `BLOCKED.md` has the command for when you decide:
     `MESH_ALLOW_VERSION_DOWNGRADE=1 sh scripts/release-testflight-asc.sh --external`, then
     Beta App Review. Keep the Mac unlocked; the upload can hang on a Keychain dialog.
  2. **Where the website's GitHub links point.** `web/index.html:131` and `:264` send
     visitors to `LeSearch-AI/mesh`, which `BLOCKED.md` (repo consolidation) describes as an
     August 0.4.x snapshot. Once you choose where they point, an agent changes the links.

  First install 0.8.0 on your own iPhone and try it (`BLOCKED.md`). A physical device is
  always your step.
- **Proof:** the public link's external tester group lists build `202609221043`; a phone that
  was never used for development installs 0.8.0 from the public link; `PUBLISHED.md` has the
  dated line. An approved build can still be attached to no group ("uploading is not
  publishing", `ROADMAP.md`), which is why the group check matters. `scripts/check-published.sh`
  has no TestFlight probe, so this proof is manual.
- **What you will see:** a stranger taps the link and gets the app the website describes.
- **If you say no:** prospects keep getting the August build.
- **Size:** S of your time, plus Apple's review wait. **Sign-off:** Arya.
- **Depends on:** B-03, because the upload builds the app from this tree, and the notes files
  must not end up in, or break, the app build.

### B-06 · Design theme: one sitting, intent then spec

- **Stage:** 1 Plan, then 2 Design. **Status:** needs-arya. The draft intent exists; the spec
  does not.
- **Why now:** this is the problem you described: "compromising on design elements because
  they are functional, and that is stopping me from getting new clients". The repo holds
  four competing looks that nobody ever chose: the June mockups in `.agents/design/`, the
  old brand page in `web/brand/`, today's landing page in `web/index.html`, and a light
  editorial draft that survives only in an old commit. The iPhone and Watch apps use Apple's
  defaults. Orange means three things at once: "an agent needs you" in the app, Claude's
  colour in chat, and the website's buy button.
- **Touches:**
  - `intents/2026-09-27-bring-my-design-theme-into-the-app.md`, drafted by an agent on
    2026-09-27 as `status: draft`. The prepared 20-question design interview lives in
    `intents/INTERVIEW.md`, and a shorter version is the intent's Open questions.
  - `openspec/changes/design-theme/` **(new)**. Its spec *is* the token list: colours
    (light, dark or both), type, spacing, corner radius, glass yes or no, haptics, and what
    "an agent needs you" looks like.
  - One line in `openspec/config.yaml` saying every proposal quotes its source intent, and
    replacing the retired "LeSearch Mesh" name there.
- **How:** one sitting, questions asked one at a time, with example answers and your
  reference images (`Reference-images/`). Two answers matter most because they are currently
  accidents: the brand colour (and what then means "needs you"), and light versus dark.
  Also answer whether the website should share the app's look; that decides whether B-09
  has a web half. **Order inside the sitting:** you answer; you set the intent to `status:
  accepted` (an intent is accepted before a spec starts, per `intents/README.md`); an agent
  writes the spec; you approve the spec.
- **Proof:** `sh scripts/check-intents.sh` is green; the design intent says `status:
  accepted` in a commit of yours; `openspec validate design-theme` passes (`openspec` is
  installed); the spec's decision table has exactly one value per row and no row left "open".
- **What you will see:** one page that says what the product looks like, in your words.
- **If you say no:** agents keep choosing functional defaults, and B-09 cannot start.
- **Size:** M (mostly your answers; about an hour of you). **Sign-off:** Arya.
- **Depends on:** none.

### B-07 · Teaching pages under `docs/sdlc/`

- **Stage:** cross-cutting (teaching). **Status:** done. The ten pages, `sdlc.css`,
  `docs/sdlc/AGENTS.md` and `scripts/check-sdlc-status.sh` landed on 2026-09-27, later the
  same day this list was written; `sh scripts/check-sdlc-site.sh` prints `ok (10 pages)`.
  Arya's sign-off (open `index.html`, find one module) is still his to give.
- **Why now:** you asked for HTML pages that teach the lifecycle using this project's own
  modules, so you can navigate the codebase yourself. `intents/README.md` links to
  `docs/sdlc/index.html`, and that link resolves now.
- **Touches:** `docs/sdlc/index.html` and nine sibling pages, one of which shows every block
  in this file.
- **Proof:** `sh scripts/check-sdlc-site.sh` prints `ok` with at least one page (not the "no
  pages yet" skip). It fails on any broken link and on any block id in this file that no
  page shows. Then you open `docs/sdlc/index.html` and find one module on your own. That
  last step is your sign-off.
- **What you will see:** a local website that explains each stage, pointing at real files
  here.
- **If you say no:** the lifecycle stays in agent-facing Markdown only.
- **Size:** M. **Sign-off:** agent builds it; Arya confirms he can use it.
- **Depends on:** nothing now (B-03 was its planned home for `docs/sdlc/AGENTS.md`; that file
  now exists), and this file.

### B-08 · App link keys long enough to be unguessable

- **Stage:** 3 Build (secure app serving). **Status:** needs-arya: it needs your OK to widen
  three lines in existing checks.
- **Why now:** you want apps your agents build to run on your machine with nobody able to
  "just access it and delete or edit stuff". Today the secret in each app link is 8 hex
  characters. That is known finding SEC-06 in `docs/review-2026-09-17.md` (line 98), whose
  written remedy is "Mint 128-bit keys, widen the regex to accept both". It is a known
  finding with a known fix, so it needs no intent.
- **Plain limit:** this makes links hard to guess. It does **not** stop someone who already
  has a link from editing, and it does not decide whether anything is shared beyond your own
  devices (Tailscale Funnel would put a third party in the path;
  `docs/sdlc/references/nethera.md`, open question 1). Both of those are the serving intent
  in B-17.
- **Touches:**
  - `install/payload/bin/mesh:2038` and `:2063`: mint 32 hex characters instead of 8.
  - `install/payload/meshd/apps.ts:90` and `:225`: accept 8 or 32, so links already on a
    Home Screen keep working.
  - `mesh apps list`: flag any app still on a short key.
  - Three lines in existing checks, which need your explicit OK (`CLAUDE.md`,
    non-negotiable 3): `scripts/check-mesh-apps.sh:50` and `:63`, and
    `scripts/check-apps-ota.sh:58`.
  - `docs/product/PRODUCT.md`, if `scripts/check-product-spec.sh` requires it.
- **Proof:** a new `scripts/check-apps-key-strength.sh` **(new)** starts a daemon on the spare
  port 8898 with a scratch `MESH_HOME`, publishes a fixture app, and asserts four things: a
  32-hex key; the 32-hex URL serves 200; a legacy 8-hex fixture still serves 200; a wrong
  32-hex key gets 404. `scripts/check-apps-serve.sh` stays green unmodified.
  `./.claude/scripts/gates.sh fast` is green.
- **What you will see:** app links get longer; old links keep working.
- **If you say no:** app links stay guessable, and must never leave your own devices.
- **Size:** S. **Sign-off:** Arya OKs the three check edits; agent; fresh verifier. Attended.
- **Depends on:** B-03.

### B-09 · Theme tokens and one restyled screen

- **Stage:** 3 Build, with the Stage 4 visual check. **Status:** not-started.
- **Why now:** this is the first time you see your theme in the real app, on the screen a new
  customer sees first. Everything after it is repetition.
- **Touches:**
  - `Shared/Theme.swift` **(new)**, holding only what B-06 decided. `project.yml` needs no
    edit, because it compiles `Shared` as a whole folder (`project.yml:66`, `:147`, `:174`);
    run `xcodegen generate`.
  - The Machines screen in `iOS/ContentView.swift`, unless your B-06 answer names a
    different "first 10 seconds" screen.
  - `docs/product/PRODUCT.md`, which must name `Shared/Theme.swift` or
    `scripts/check-product-spec.sh` fails.
  - **If B-06 says the website shares the look:** the token block in `web/index.html`
    (lines 20 to 27).
  - **Not in this block:** a `.tint` on the app roots. It would recolour every screen in both
    apps, and all 18 images in `docs/product/shots/` would then need re-shooting and
    approving. That comes later, one screen at a time.
- **Proof:**
  - A new `scripts/check-theme-tokens.sh` **(new)** fails if a restyled file contains a raw
    colour literal (`.orange`, `.red`, `.green`, `.blue`, `Color(red:`) outside
    `Shared/Theme.swift`. It grows by one file per restyled screen.
  - The visual check: run `sh scripts/product-shots.sh` before and after, and commit the
    `docs/product/shots/iphone-machines.png` pair (light and dark, if you chose both).
  - `./.claude/scripts/gates.sh full` before the pull request (it runs `xcodebuild` and
    takes minutes).
- **Also:** update `.agents/skills/meshwatch-ui-taste/SKILL.md` to name the palette, so later
  agents write on-theme by default. That path is protected and needs your approval.
- **What you will see:** a before/after screenshot pair of the Machines screen in your
  colours.
- **If you say no:** the app keeps Apple's default look.
- **Size:** M, with a real chance of L if simulators or the Xcode 27 SDK misbehave; do it in
  an attended session. **Sign-off:** agent; Arya approves the screenshot pair.
- **Depends on:** B-06, B-03.

### B-10 · Multi-machine intent: what breaks today

- **Stage:** 1 Plan. **Status:** needs-arya.
- **Why now:** "connect multiple devices that I run agents on, run sessions across them" is
  what you called our core use, and no written intent covers it. The one question that
  shapes it: **what is the one thing that breaks or confuses you today when you run agents
  on the Mac, the Pi and the Jetson together?** That answer is not written anywhere
  (unverified).
- **Touches:** `intents/2026-09-27-many-machines-one-screen.md`, drafted by an agent on
  2026-09-27 as `status: draft`.
- **Proof:** `sh scripts/check-intents.sh` is green, and once you are sure of it, the file says
  `status: accepted` in a commit of yours.
- **What you will see:** one page in your words that the next build block must serve.
- **If you say no:** B-11 has nothing to aim at, and multi-machine work stays guesswork.
- **Size:** S (about 20 minutes). **Sign-off:** Arya.
- **Depends on:** none.

### B-11 · First multi-machine build block

- **Stage:** 3 Build. **Status:** not-started.
- **Why now:** it turns B-10's answer into the first thing you can feel across machines.
- **Touches:** decided by B-10. **The candidate from the Orca review**
  (`docs/sdlc/references/orca.md`, host-contact verdict, sized S): machine status that tells
  you what to do, meaning "pair again" or "update needed", rather than "offline". Part of this
  already exists: `Shared/Models.swift:955-961` shows an auth error and "last seen" before
  it falls back to "offline", and `Shared/Models.swift:636-645` says "reconnecting" during a
  grace window. What is still missing (a protocol-mismatch state; never reporting that a
  session ended just because a poll failed) is unverified. `Shared/Models.swift` is
  serialized. A user-visible change needs a short `openspec/changes/<slug>/` spec first.
- **Proof:** a new check **(new)** that feeds each failure (token rejected, daemon too old,
  timeout) and asserts the label shown, plus one run against real machines, which is yours
  per `AGENTS.md` ("what an agent cannot verify").
- **What you will see:** the Machines screen tells you why a machine is unreachable and what
  to do about it.
- **If you say no:** the multi-machine intent waits for another block.
- **Size:** S for the candidate; resized if B-10 names something else. **Sign-off:** agent,
  fresh verifier, then Arya on a device.
- **Depends on:** B-10 accepted, B-03.

### B-12 · Security audit skill and first baseline

- **Stage:** 6 Maintain (security scans). **Status:** needs-arya: it adds a third-party skill
  under a protected path, and you decide where findings live.
- **Why now:** you named security as paramount. There is no recurring scan, no baseline, and
  no record of dismissed findings. Cloudflare's MIT-licensed audit skill gives a repeatable,
  written record without building our own (`docs/sdlc/references/security-audit-skill.md`).
  It brings its own severity rules, so it does not wait for B-21.
- **Touches:** `.claude/skills/security-audit/` **(new)**: the upstream files pinned at commit
  `c1c8a8c`, unmodified, with their `LICENSE`. Our adaptations go in a separate `MESH.md`,
  plus a `.cursor/skills/security-audit` symlink and a new
  `scripts/check-security-audit-skill.sh` **(new)**.
- **Proof, first half:** the new check fails if `LICENSE` or its Cloudflare copyright line is
  missing, or if any vendored file's sha256 differs from the pinned list. It reports
  MISCONFIGURED, never green, when `node` is absent. Whether `node` exists on CI's `apps`
  runner is unverified; confirm it first, or CI turns red for a reason unrelated to
  security. Then `./.claude/scripts/gates.sh fast`.
- **Second half (a separate yes):** one read-only audit of `install/payload/meshd/`, the
  installer and the terminal bridges, capped at 5 agents at once. **Findings stay on your Mac
  and never go into git**, because the repo is public and an unfixed finding would be a public
  disclosure. Proof: a dated findings file outside the repo, where every finding is either
  validated or dismissed with a written reason. Only the counts go in chat. Each fixed class
  later becomes a `scripts/check-sec-*`.
- **What you will see:** a list of real, checked security findings with a decision on each,
  which is a story you can tell a client.
- **If you say no:** security stays "we think so" rather than "here is the record".
- **Size:** S to vendor, M for the first run. **Sign-off:** Arya.
- **Depends on:** B-03.

### B-13 · Streaming redaction for the live terminal

- **Stage:** 3 Build (security). **Status:** not-started.
- **Why now:** the daemon masks secrets before they leave your machine, but the live terminal
  stream is masked one chunk at a time, so a token split across two chunks could slip
  through (`docs/sdlc/references/agent-git.md`, "The first block"). Whether that split
  happens in real use is unverified, so do it after the B-12 audit if possible; the audit
  may confirm it or rank it lower. It is not blocked on the audit.
- **Touches:** `install/payload/meshd/redact.ts` (a stream redactor that holds back the
  unfinished end of each chunk) and `install/payload/meshd/pty.ts` (use it, one per
  connection). About 30 lines, no new file, and neither file is serialized.
- **The trap to design around:** each character you type is echoed back as exactly such an
  "unfinished end", so a naive hold-back delays every keystroke. Hold back only what could be
  the start of a secret (a known prefix such as `Bearer `, or a run long enough to be one), or
  prove the delay is small.
- **Proof:**
  - A new `scripts/check-redact-stream.sh` **(new)** feeds a fixture token for each rule,
    split at every byte offset, and fails if the raw token appears in the joined output.
  - It also checks that a prompt with no newline still appears, and that a single typed
    character is echoed within a bound written into the plan.
  - `scripts/check-redact.sh` and `scripts/check-pty-route.sh` stay green.
  - One run against a side-port daemon (`MESHD_PORT=8898`, never the live `:8899`), per
    `AGENTS.md` rule 1: verify by running.
- **What you will see:** nothing, unless it was leaking.
- **If you say no:** a rare split-token leak stays possible in the live terminal.
- **Size:** S. **Sign-off:** agent, fresh verifier.
- **Depends on:** B-03; preferably after B-12.

### B-14 · Ship the daemon fixes to users

- **Stage:** 5 Deploy. **Status:** not-started.
- **Why now:** B-03, B-08 and B-13 change what `mesh-install` ships, and until a release is
  cut they reach nobody. `ROADMAP.md` puts shipping above everything ("Now — shipping (this
  blocks everything else)"). The newest release is v0.8.0 (`PUBLISHED.md`). Daemon releases
  do not go through App Review, so this is fast.
- **Touches:** `sh scripts/release-mesh-install.sh` (dry run by default; `--publish` creates
  the GitHub release), then `PUBLISHED.md`. Rollback already exists: `mesh upgrade` keeps the
  old daemon folder instead of deleting it (`install/payload/bin/mesh`, comment above
  `swapInMeshd`).
- **Proof:** `MESH_PUBLISHED=1 sh scripts/check-published.sh` is green on the new release,
  and `PUBLISHED.md` records the gate line and commit.
- **What you will see:** `mesh upgrade` on any machine brings the fixes.
- **If you say no:** the fixes sit in git, "queued, not delivered".
- **Size:** S. **Sign-off:** Arya says yes in chat before `--publish`, because a release is
  public; agent runs it.
- **Depends on:** B-03, B-08. B-13 goes in if it is done, but the release does not wait for it.

### B-15 · Decide the Cursor pull-request pile

- **Stage:** 5 Deploy (review). **Status:** needs-arya.
- **Why now:** on 2026-09-27 the repo had 135 open pull requests. 123 of them come from
  `cursor/*` branches opened by an unattended Cursor loop, 119 of those on 22–23 September
  (2026-09-22 05:23 to 2026-09-23 03:06 UTC). 112 of the 123 are stacked on each other.
  That breaks the charter's own stop rule ("more than 3 items awaiting review") about 40 times
  over. Some of them build account features. `ROADMAP.md` lists "An account system" as a
  non-goal, while `docs/product/PRODUCT.md:441` allows an optional account "only so a
  problem report can be answered". So these PRs **may** contradict the roadmap, and which
  document governs is your call. The loop looks dormant: the newest open PR was created
  2026-09-23 03:06 UTC. Whether it is actually switched off is unverified.
- **Touches:** GitHub pull requests only, plus a one-paragraph dated decision in
  `docs/factory/DECISIONS.md`. List them with:
  ```sh
  gh pr list --repo aryateja2106/lecoder-watch --state open --limit 300 \
    --json number,title,headRefName,baseRefName,createdAt \
    --jq '.[] | select(.headRefName | startswith("cursor/")) | [.number, .baseRefName, .title] | @tsv'
  ```
- **Your choice, one of:**
  - **(a) Close all (suggested).** One shared comment links the decision. Closing does not
    delete branches, so any idea can be revived. Size S.
  - **(b) Review and keep a subset.** 123 PRs, mostly stacked, based 262 commits away from
    `main`, and each keeper effectively needs its own intent. That is L, so it is not a block;
    it would become several intents.
  - **(c) Park.** One tracking issue lists every branch and title, then all PRs close. Size S.

  Also say whether and where the Cursor background agent is switched off.
- **Proof:** the command above returns 0 rows (for a or c), and `docs/factory/DECISIONS.md`
  has the dated decision.
- **What you will see:** an open-PR list you can actually read.
- **If you say no:** no agent run can honestly start under the charter's stop rule.
- **Size:** S. **Sign-off:** Arya decides; an agent closes the PRs only after your explicit
  yes in chat, because closing PRs is a public action.
- **Depends on:** none. It pairs naturally with B-16, which decides whether such a loop may
  exist again.

### B-16 · Fill in the factory charter

- **Stage:** policy (cross-cutting). **Status:** needs-arya.
- **Why now:** `docs/factory/CHARTER.md` still says `CHARTER_STATUS: incomplete` and `TIER:
  <choose one tier>`. Its own rule is that silence means stop, so no agent may run unattended
  until it is filled. It sits after the customer blocks because it only matters once you want
  agents working while you sleep.
- **Touches:** `docs/factory/CHARTER.md` (protected: you edit it, or you explicitly ask an
  agent to in that session), plus a new `scripts/check-charter.sh` **(new)** added in the
  same change, so it never sits red. A 15-minute interview; nothing is guessed:
  1. **Tier:** one of `revival`, `greenfield`, `oss`, `client-production`. Facts to weigh:
     the repo is public, strangers can curl the installer, and a public TestFlight link
     exists.
  2. **Load-bearing paths:** replace the template globs `src/auth/**` and `src/payments/**`
     (they do not exist here) with real paths, for example `install/payload/meshd/auth.ts`,
     `install/payload/meshd/pair.ts`, `install/payload/meshd/server.ts`,
     `Shared/Models.swift`, `Shared/MeshClient.swift`, `project.yml`, `install/install.sh`.
     **Trade-off to know:** every path you list turns the blocks touching it (for example
     B-08, B-11, B-13, B-18) into attended work that must pass the `deep` gate, and `deep`
     cannot be green until B-20.
  3. **Automatable list:** remove the line that points at the missing
     `docs/factory/MIGRATION.md`.
  4. **Stop conditions:** pick one review-queue number (the charter says 3, and `CLAUDE.md`
     line 51 on this branch says "more than two"), and add `MAX_PARALLEL_SESSIONS: 3` (the
     playbook's "start with 2–3").
  5. **Plan before code:** one `DONE` line: "the plan (`openspec/changes/<slug>/tasks.md` or
     a `plan.md`) is committed before the first code commit on the branch". This uses the
     plan location `intents/README.md` already names, instead of creating a third one.
  6. **Dates:** set `LAST_REVIEWED` and `NEXT_REVIEW`, then `CHARTER_STATUS: ready`.
- **Proof:** `sh scripts/check-charter.sh` is green. It fails on any `<...>` placeholder, on
  `CHARTER_STATUS: incomplete`, and on any non-glob load-bearing path that does not exist.
  The fresh verifier checks the plan rule from git history on each pull request: the commit
  that adds the plan must come before the first code commit.
- **What you will see:** one page that says how much freedom agents get here.
- **If you say no:** agents only ever work while you are in the session.
- **Size:** S. **Sign-off:** Arya.
- **Depends on:** none.

### B-17 · The remaining three intents

- **Stage:** 1 Plan. **Status:** needs-arya.
- **Why now:** three of your asks have no written "why" yet, and two build blocks wait on
  them. About 20 minutes each, whenever you have them.
- **Touches:** three new files in `intents/`:
  1. **Security and audit trail** (feeds B-18): "I can show a client who allowed what, and
     when." It includes the question the OpenMuse review left open: should a client see the
     approvals log on the phone, in a file, or both (`docs/sdlc/references/openmuse.md`, open
     question 1)?
  2. **Secure app serving** (follows B-08): who may edit an agent-built app's data, and
     whether anything is ever shared beyond your own devices.
  3. **TypeScript and Rust:** which feature you want in Rust, and how the TypeScript modules
     should be split. The intent carries the boundary rule itself, with no separate ADR. It
     puts the reviewed recommendation (`docs/sdlc/references/agent-git.md`: no Rust until
     something is measured slow; OS work as a separate helper program, like
     `install/payload/bin/mesh-input.swift` today; pure computation as one WebAssembly file;
     never native code loaded inside the daemon) **next to a real "yes" option**: a first
     Rust helper program that you name. Compatibility rules for either option: a checked-in
     JSON schema both sides test against, a protocol number in the handshake, and a
     capability string in `/health`.
- **Proof:** `sh scripts/check-intents.sh` is green, and each of the three drafts an agent
  wrote on 2026-09-27 (`intents/2026-09-27-security-paramount-with-auditability.md`,
  `intents/2026-09-27-serve-my-own-apps-securely.md`,
  `intents/2026-09-27-typescript-and-rust-module-boundaries.md`) says `status: accepted` in a
  commit of yours. The security intent comes first, because B-18 waits for it.
- **What you will see:** your remaining asks written down in your words.
- **If you say no:** B-18 cannot start, and agents answer the Rust question differently each
  time.
- **Size:** S each. **Sign-off:** Arya.
- **Depends on:** none.

### B-18 · Approvals log that records what was chosen

- **Stage:** 3 Build (auditability). **Status:** not-started.
- **Why now:** when you tap Allow on your phone today, the daemon presses keys in the agent's
  terminal and writes nothing down, so you cannot show a client who approved what, or when
  (`docs/sdlc/references/openmuse.md`). The draft's version would only have recorded "Enter
  was pressed". A menu choice is sent as cursor moves followed by Enter, and a `[y/N]` answer
  is sent as typed text, not as a key (`Shared/Models.swift:1660-1670`). So the log has to
  record **which option** was chosen.
- **Touches:**
  - `install/payload/meshd/decisions.ts` **(new)**, writing `~/.mesh/decisions.jsonl`
    (file mode 0600). Each line holds the time, the session, the redacted prompt, and the
    option or letter that was sent.
  - `install/payload/meshd/server.ts` (serialized): one import, one route, one call in the
    send route.
  - `docs/product/PRODUCT.md`, which must name the new module, or
    `scripts/check-product-spec.sh` fails.
  - `Shared/MeshClient.swift` (serialized) only if the app must send an explicit answer
    field; that choice is part of the spec.
  - Where the log is shown (file, phone view, or both) comes from B-17 item 1. A new public
    route needs an `openspec/changes/<slug>/` spec first.
- **Proof:** a new `scripts/check-decisions.sh` **(new)**, modelled on
  `scripts/check-approve-path.sh`, starts a throwaway daemon on a spare port and asserts:
  - a receipt that names the chosen option for a menu pick;
  - a receipt for a typed `y`;
  - `ok: false` when the pane is missing;
  - no receipt for a session that was not waiting;
  - file mode 0600.

  `scripts/check-approve-path.sh` and `scripts/check-redact.sh` stay green.
- **What you will see:** a dated list of every approval, with what was approved, wherever
  B-17 says it should appear.
- **If you say no:** approvals stay unrecorded.
- **Size:** M. **Sign-off:** agent, fresh verifier; Arya approves the spec.
- **Depends on:** B-17 item 1 accepted and its spec, B-03.

### B-19 · CI: find out why the iPhone build fails, then fix it

- **Stage:** 4 Test. **Status:** not-started.
- **Why now:** CI fails on the newest integration branch in the `apps` job at "Build
  MeshWatch (iOS)". Of the last 200 runs, 52 failed and 80 were cancelled. A red CI teaches
  everyone to ignore CI. The cause is unverified. A likely one: the app needs the Xcode 27
  SDK, and the job runs on `macos-15` (`.github/workflows/ci.yml`, `apps` job).
- **Two steps:**
  1. **Diagnose** (S, agent): read the failing log with `gh run view --log-failed` and write
     the cause down in `docs/factory/DECISIONS.md` with the exact error line.
  2. **Fix**, sized after step 1. Options, all yours to pick:
     - wait for GitHub's hosted image;
     - use a self-hosted runner on your Mac. On a public repo that is a security decision:
       it must run on pushes only, never on pull requests from forks;
     - make the `apps` job non-blocking. That would make "CI is green" meaningless for the
       app, so if you choose it, the proof becomes "the reason is written in `ci.yml`", not
       "green".
- **Touches:** `.github/workflows/ci.yml` (you read the diff). Also add `sdlc/**` to the push
  trigger list, which today gives this branch no CI until a pull request is open.
- **Proof:** step 1: the dated entry exists and quotes the failing line. Step 2:
  `gh run list --workflow ci.yml --branch sdlc/ai-native-playbook --limit 1 --json
  conclusion --jq '.[0].conclusion'` prints `success`, with the `apps` job still blocking.
- **What you will see:** a green tick on GitHub that means something.
- **If you say no:** CI stays red, and nobody trusts it.
- **Size:** S to diagnose; the fix is sized afterwards. **Sign-off:** agent diagnoses; Arya
  picks the option and reads the workflow change.
- **Depends on:** B-03, because `check-all.sh` runs in the same job.

### B-20 · Write down what "healthy" looks like, and decide the deep gate

- **Stage:** 4 Test. **Status:** not-started.
- **Why now:** the playbook's core test rule is one command with a documented healthy output.
  Today `CLAUDE.md` lists the gate commands but not what healthy output looks like. It also
  describes the `deep` gate as harmless, yet `deep` can never be green: `npm audit` exits with
  an error because the repo root has no lockfile, and the "architecture" gate has no rules.
- **Touches:** `CLAUDE.md`, a "Verifying your work" block with the expected last line of
  `gates.sh fast` (`FACTORY_GATES: level=fast status=GREEN ...`), the expected ending of
  `full` (`All self-checks passed.`), how to skip the live-machine probes
  (`MESH_OVERNIGHT_SKIP`, `scripts/check-overnight.sh:8`), and one honest sentence that
  `deep` cannot pass today. Plus a dated entry in `docs/factory/DECISIONS.md` recording your
  pick of the three ways out:
  - add a root lockfile (the audit then passes trivially, because the root has no
    dependencies, and the entry must say so);
  - point the audit at `install/payload/meshd/package.json`, the real dependency set (this
    edits the protected `.claude/scripts/gates.sh`);
  - drop the gate, with a written reason.

  Loosening a gate needs recorded evidence under the charter, which is why the entry is
  required.
- **Proof:** the expected `fast` line in `CLAUDE.md` matches the last line of a fresh
  `./.claude/scripts/gates.sh fast` run, and the `DECISIONS.md` entry exists. It does **not**
  claim `deep` is green; that would need a full-suite run across the whole fleet.
- **What you will see:** nothing directly; agents stop being told a broken gate works.
- **If you say no:** `deep` stays a trap for any agent told to use it.
- **Size:** S. **Sign-off:** agent writes it; Arya picks the option.
- **Depends on:** B-03.

### B-21 · A `REVIEW.md` that a reviewer actually reads

- **Stage:** 5 Deploy (review policy). **Status:** not-started.
- **Why now:** there is no written rule for what a reviewer must flag, so reviews either drown
  you in nits or miss what matters. A `REVIEW.md` that no reviewer loads would be dead on
  arrival: today no agent file mentions one (`.claude/agents/factory-critic.md`).
- **Touches:**
  - `REVIEW.md` **(new)** at the repo root, about 30 lines, from the playbook template
    (Passes / What Important means / Cap the nits / Do not report). The passes are the review
    order already in `AGENTS.md`. "Important" means anything under the charter's
    load-bearing paths, or anything that contradicts a `ROADMAP.md` non-goal. Cap at 5
    findings. "Do not report": actions the bearer token grants by design.
  - `.claude/agents/factory-critic.md` (protected; your approval): make it read `REVIEW.md`.
- **Proof:** run the critic once on a known-bad diff, for example one that adds an account
  route or touches `server.ts` without a check. It reports the problem as Important and stays
  within the 5-finding cap.
- **What you will see:** shorter reviews that flag the right things.
- **If you say no:** reviews keep varying from agent to agent.
- **Size:** S. **Sign-off:** agent writes it; Arya approves the critic change.
- **Depends on:** B-16 (soft: "Important" reads better once load-bearing paths are real).

### B-22 · One source of truth per kind of document

- **Stage:** playbook sidebar (source of truth). **Status:** not-started.
- **Why now:** at least eight documents claim to be "the current state". `HANDOFF.md` still
  says to work on a July branch, and `docs/README.md` sends "what to build next" to
  `docs/PRODUCT-SPEC-V1.md` instead of `docs/product/PRODUCT.md`, so agents start from the
  wrong page.
- **Touches:**
  - `index.md`: one table, one row per kind of document, naming the single place that wins:
    intent → `intents/`; spec → `openspec/` and `docs/product/PRODUCT.md`; plan →
    `openspec/changes/<slug>/tasks.md` or `plan.md`; queue → GitHub; release state →
    `PUBLISHED.md`; your to-do list → `BLOCKED.md`.
  - `docs/README.md`: mark `HANDOFF.md`, `TASKS-2026-09-04.md`, `docs/factory/STATE.md` and
    `docs/factory/QUEUE.md` as history, and link `PRODUCT.md`.
- **Proof:** `sh scripts/check-docs-index.sh` and `sh scripts/check-links.sh` are green;
  `grep -c 'PRODUCT.md' docs/README.md` prints at least 1.
- **What you will see:** one "start here" table.
- **If you say no:** agents keep starting from stale pages.
- **Size:** S. **Sign-off:** agent. What `main` should be (it is 262 commits behind this
  branch) and the repo consolidation in `BLOCKED.md` stay your open questions.
- **Depends on:** B-03 (its proof check is red today).

---

## Deliberately not a block yet

- **An isolated project copy per agent (git worktrees)**, the Orca review's first block. It
  helps several agents on **one** machine, not across machines. The **Later** list in
  `ROADMAP.md` isolates agents a different way (each agent gets its own Unix user and its own
  daemon), not with worktrees. Done properly, it needs a spec (a new request field,
  capability and CLI flag), validation of hostile names (for example `../x`, `a;b`, and the
  colon that tmux cannot handle), and a clean-up step, since this Mac already has 15
  worktrees. That is L. It comes back as its own intent if B-10 or a "parallel agents"
  intent asks for it.
- **Agent evals in CI and a CI-health control band** (playbook 4.1 and 6.1). Re-running
  existing checks when `CLAUDE.md` changes would prove nothing, because no check reads
  `CLAUDE.md`. A real eval runs an agent and grades the result: paid model calls, and an API
  key in a public repo's workflow. That is L with its own security decision, and it only pays
  off once agents run unattended (after B-16) on a green CI (after B-19).
- **A plan section inside run records.** A plan written into a record at the end of a run
  cannot show that it came first. B-16 item 5 replaces it.
- **Per-device tokens** (cut off one lost phone without re-pairing everything, and say which
  device approved). L; it touches pairing and auth, the most sensitive code. It needs its own
  intent.
- **A read-open, write-gated proxy for agent-built apps.** Follows B-08, and only if the
  serving intent (B-17) says those apps need a backend at all.
- **A secrets-in-diff hook** reusing `redact.ts`, and fixing the false positives in
  `.claude/hooks/block-merge.sh` (it blocks some read-only commands). Both are under
  `.claude/**`, which is protected. Worth doing after B-12 shows what the baseline finds.
- **Rules for the empty "architecture" gate.** No rule is known yet to put in it.
- **Agent-in-CI triage, on-call chat, managed settings.** The playbook's later steps. There
  are no customers, no pager and no second person yet.
- **Creating the `factory:*` labels and re-triaging the 107 open issues.** The labels were
  never created (`.factory/scripts/bootstrap-github.sh` was never applied), and the issues
  date from 2026-08-27/28. Re-triage them against the new intents after B-06, B-10, B-16 and
  B-17, not before.
- **Skills clean-up** (about 70 installed, several overlapping). They are advisory only;
  prune when a run shows one being ignored.
- **Other `ROADMAP.md` "Now" items** (terminal gestures, hold-to-talk, model picker, Mac
  permissions at setup, friendly app addresses). These are product features, not lifecycle
  work; each enters as an intent.
- **The brain probe order in `brain.ts`** (`BLOCKED.md`). A product slice, not lifecycle work.
- **`CONSTRAINTS.md`.** `docs/product/PRODUCT.md` §11 rule 6 calls it "the floor", but no such
  file exists at the repo root. Flagged, not planned.
- **The dormant `.claude/hooks/stop-published.sh`.** It is not wired today, and the mission it
  served has ended. Nothing to do unless a new publish mission starts.

## Open questions for Arya

1. B-04: protect `main` only, or also `backup/2026-07-02`?
2. B-05: accept the version downgrade from the stray `1.0`? Where should the website's
   GitHub links point?
3. B-10: what is the one thing that breaks or confuses you when you run agents on the Mac, Pi
   and Jetson together?
4. B-15: close all, keep a subset (L), or park? Where is the Cursor background agent switched
   off? And does `ROADMAP.md` ("no account system") or `PRODUCT.md` §10 (an optional account
   for problem reports) govern the account PRs?
5. B-16: which tier? The facts point between `greenfield` and `oss`. Do you accept that each
   load-bearing path makes the matching blocks attended and deep-gated?
6. B-17: should a client see the approvals log on the phone, in a file, or both? Which
   feature, if any, do you want in Rust?
7. B-19: if the iPhone build needs Xcode 27 and GitHub does not offer it, which option?
8. B-20: which of the three ways out for the deep gate?
9. B-22: what should `main` be, and do you approve the repo consolidation in `BLOCKED.md`?

---

## Decisions: how the two critiques were handled

The draft was reviewed twice: once for order and scope (critique 1), and once from your point
of view as a founder (critique 2). The draft's block numbers are not used here, so draft
blocks are named in words.

**Kept and folded in:**

- **The baseline is red** (critique 1). Confirmed by re-running the three checks on
  `5710d51`. This became B-03, which also absorbs the draft's installer block, widened from
  `bin/` only to every `AGENTS.md`/`INDEX.md` under `install/` (17 files), fixed in two places
  (the packager's `skip` and the `--src` staging copy).
- **Invented dependencies removed** (critique 1). The PR pile no longer waits on branch
  protection; the charter no longer waits on the pile; the app-key and redaction fixes no
  longer wait on intents; the audit skill no longer waits on `REVIEW.md`; the source-of-truth
  table no longer waits on the pile.
- **Missing dependencies added** (critique 1). Everything that runs `check-all.sh` depends on
  B-03. The load-bearing trade-off is spelled out in B-16. Until B-16, agent blocks run
  attended only.
- **"Draft intent" is not enough** (critique 1). An intent must be accepted, and a feature
  needs a spec, before build blocks start (B-11, B-18). In B-06, you accept the intent
  **before** the spec, not by signing the spec.
- **Proofs that could pass on dead work** (critique 1). `REVIEW.md` is now wired to the
  critic and proved on a bad diff (B-21). The approvals log records the chosen option,
  including typed answers (B-18). The run-record plan is replaced by a git-history rule
  (B-16). Evals moved out.
- **A release block** (critique 1). Added as B-14, with `check-published.sh` as its finish
  line.
- **The deep-gate block reframed** (critique 1). Its proof no longer claims `deep` goes green,
  and dropping a gate requires a `DECISIONS.md` entry (B-20).
- **CI split into diagnose, then fix** (critique 1). "Make the job non-blocking" no longer
  counts as green (B-19).
- **Theme block without the root tint** (critique 1). `project.yml` needs no edit;
  `PRODUCT.md` must name `Theme.swift` (B-09).
- **Keystroke delay in streaming redaction** (critique 1). Added a latency bound and a
  prefix-only option (B-13).
- **`node` on the CI runner** (critique 1). Flagged as unverified in B-12.
- **The TestFlight proof checks the public group and a non-development device** (critique 1).
  Applied in B-05.
- **Wording.** "About 21 PRs build forbidden features" became "may contradict", and the
  `ROADMAP.md` versus `PRODUCT.md` §10 conflict became an open question (critique 1). "The
  pile refills" is now marked unverified (both critiques). The `CLAUDE.md` "more than two"
  is on this branch, not only on `main` (critique 1). App keys no longer imply public
  sharing (critique 1).
- **Order for a founder** (critique 2). TestFlight and the design sitting moved to the top of
  your lane; process-only blocks moved to the end.
- **Your time counted and capped** (critique 2): fourteen asks in total, three this week.
- **One design interview, not two** (critique 2). The design intent and the design spec are
  now one sitting (B-06), including the website question.
- **Only two intents this week** (critique 2): design (B-06) and multi-machine (B-10). The
  other three are B-17.
- **Multi-machine had no block** (critique 2). Added B-10 and B-11, and relabelled the draft's
  worktree block as single-machine.
- **The TypeScript and Rust answer must include a real "yes"** (critique 2), and the
  TypeScript split question is included. Folded into the B-17 intent instead of a separate
  ADR (critique 1: a separate document now is close to YAGNI).
- **The approvals log needs a place to be seen** (critique 2). That is B-17 item 1, a
  dependency of B-18.
- **The app-key block does not finish your serving ask** (critique 2). Said plainly in B-08.
- **The website links to the August snapshot** (critique 2). Moved into B-05 as your decision.
- **The teaching pages were missing** (critique 2). Added as B-07.
- **"Top to bottom" contradicted "two lanes"** (critique 2). Now two lanes, each top to
  bottom.
- **"What you will see" and "If you say no" on every block, plus a "customer can see it"
  column** (critique 2). Added.

**Refuted or only partly accepted, and why:**

- **Critique 2: the installer clean-up must precede TestFlight because the notes would ship
  in it.** The reason is wrong, but the dependency stands. `project.yml` never mentions
  `install/payload`, so the phone app does not ship those files. It does compile `iOS/`,
  `Watch/`, `Shared/` and both widget folders whole, though, and eight of today's notes files
  sit there. Whether they end up inside the app is unverified. So B-05 still depends on B-03,
  and B-03 now includes a check on the generated Xcode project.
- **Critique 2: park the charter unless agents run unattended this month.** Partly accepted:
  it moved down, behind the customer blocks. It stays a block, because an unattended loop
  already opened 119 pull requests on 22–23 September (123 open Cursor pull requests in all),
  and the charter is where you decide whether that may
  happen again.
- **Critique 2: the "verify everything" block is one sentence, not a block.** Partly accepted:
  it is S and near the end. Dropping or changing a required gate needs a recorded decision
  under the charter, so it is more than one sentence.
- **Critique 2: make CI S by marking the iPhone job non-blocking.** Not accepted as the
  default. It would make the proof ("CI succeeded") true by definition (critique 1's point).
  It stays one of your options, with its honest proof.
- **Critique 2: let the audit decide whether streaming redaction is real before doing it.**
  Partly accepted: B-13 comes after B-12 where possible. It is not blocked on B-12, because a
  secret split across a chunk boundary is a known class of bug with a cheap, testable fix.
- **Critique 2: park the source-of-truth block.** Kept, but last. It is S, and it stops
  agents starting from a July handoff page.
- **Critique 1: move the evals block to "not yet" and fold the plan block into the charter.**
  Accepted, as critique 1 proposed.
- **Critique 1 and 2: the worktree block.** Both objected: it is mislabelled, L-sized, and
  pulls Later work forward. It moved to "Deliberately not a block yet" rather than being
  kept and relabelled, because by this file's own size rule an L is not a block.
