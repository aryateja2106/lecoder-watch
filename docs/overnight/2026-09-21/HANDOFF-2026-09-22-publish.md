# Handoff — LeSearch AI publish run, 2026-09-22 evening

Supersedes [HANDOFF-2026-09-22.md](HANDOFF-2026-09-22.md) for anything the two disagree on.
Written from the publish session in worktree `compassionate-cohen-53d9fb`. The definition
of done is now a file, not a judgement: **`scripts/check-published.sh`**. Read
[PUBLISHED.md](../../../PUBLISHED.md) first — it is the ledger that check reads — then
[BLOCKED.md](../../../BLOCKED.md) for what only Arya can do.

## Where things are

- **Branch:** `feat/lesearch-ai-overnight-2026-09-21`, shared right now by **two sessions**
  on this Mac. Rebase, never merge; fetch before every push. Draft PR
  https://github.com/aryateja2106/lecoder-watch/pull/133, body updated with the third-pass
  table.
- **Version:** app 0.8.0 (build 3) == daemon 0.8.0. Fleet mac / pi / jetson on 0.8.0.
- **Live:** https://lesearch.ai serves the 0.8.0 landing (Vercel project
  `lesearch-website`, `vercel deploy --prod` from `web/`), plus `/getting-started`,
  `/privacy`, `/install.sh`, `/beta`.
- **Backend:** Supabase `zmisjteztezaqfflwbgf` (org LeSearch AI). Schema lives in
  `supabase/migrations/`; keys in the gitignored `supabase/.env`. Auth e-mail +
  password with confirmations **off** (no SMTP yet — BLOCKED.md).
- **Feedback loop:** app → `public.feedback` (insert-only for the app) → launchd job
  `ai.lesearch.feedback-worker` every 10 min → deduped GitHub issues labeled `from-users`
  on LeSearch-AI/mesh. Proven end to end: issues/1 plus a deduped comment.

## The finish line

```sh
sh scripts/check-published.sh                    # structural (what check-all runs)
MESH_PUBLISHED=1 sh scripts/check-published.sh   # the live finish line
```

It asserts, in one run, everything the publish mission asked for and names each thing that
is still missing. The project Stop hook `.claude/hooks/stop-published.sh` (wired from the
machine-local `.claude/settings.local.json`) runs the live form and blocks a stop while it
is red, with a 25-strikes escape when the same assertion stays red with no new commit.
**Never loosen it.** Add evidence to PUBLISHED.md, fix the product, or record a blocker.

## What is left

1. One clean `sh scripts/check-all.sh` + `./.claude/scripts/gates.sh full` with **no other
   session driving a simulator**, then paste the `FACTORY_GATES:` line and its SHA into
   PUBLISHED.md (`Gate`, `Gate SHA`, `Gate log`) and commit the log file.
2. `docs/product/shots/*.png` — `sh scripts/product-shots.sh` (drives
   `UITests/ScreenshotTests`, exports from the xcresult). `check-web-docs.sh` stays red
   until they exist and `bun scripts/build-web-docs.ts` has copied them into `web/shots/`;
   then redeploy `web/`.
3. The fresh-eyes findings → issues labeled `ux-review`; anything blocking a first-time
   user's core flow gets fixed before the promise line, the rest triaged in PUBLISHED.md.
4. Then the ADR §6 slices (`docs/adr-2026-09-22-platform-shape.md`): exposed-secrets reach
   + pinned tasks → VNC credential flow (attended) → plugin route loader → artifacts +
   KB search → installer runs hooks/skills install (already wired: `install_agent_hooks`
   and `install_skills` run at the end of a fresh install).

## Traps this session added to the list

- **Two sessions, one Mac.** `scripts/check-ios-smoke.sh` always picks the newest iPhone
  simulator, so two sessions running it (or any `xcodebuild test`) kill each other's
  runner — "Test crashed with signal kill/term before establishing connection",
  "RequestDenied … xctrunner". Hand the simulator over explicitly. Put
  `xcrun simctl bootstatus <udid> -b` in front of a run: the device shuts itself down
  between runs, which produces the same symptoms.
- **`check-all` counts an INCONCLUSIVE smoke as FAIL**, so contention reads as a real red.
- iOS shows a **Save Password?** sheet over the app after a signup; it lives in the app's
  own accessibility tree (`app.buttons["Not Now"]`, not springboard).
- A SwiftUI `TextField` reports its **placeholder** as `value` on iOS 27, and `typeText`
  on a `TextField(axis: .vertical)` element can miss — type to the first responder
  (`app.typeText`) and assert on what the server received, not on the field.
- **PostgREST** needs SELECT to honour `Prefer: return=representation`; an insert-only
  role must mint the row id on the client and send `return=minimal`.
- **Supabase's built-in mailer** only delivers to team members, so a real signup never
  confirms without custom SMTP.
- The `block-merge.sh` PreToolUse hook refuses any shell line naming `.claude/` next to a
  writing command — including `cd` into a worktree under `.claude/worktrees/`. Drop the
  `cd`; the tool's working directory persists.
- `~/.mesh/bin/mesh` is `#!/usr/bin/env bun`, so calling it by absolute path over
  `ssh host '…'` fails with `/usr/bin/env: 'bun': No such file or directory` — the PATH
  line the installer writes lives in an interactive-only part of `.bashrc`.

## Do not

- Merge, push `main`, force-push, delete a repo, or archive anything in the LeSearch-AI org
  before Arya answers the list in BLOCKED.md.
- Edit CHARTER, gates.conf, gates.sh, AGENTS.md, `.github`, or an existing `scripts/check-*`.
- Loosen `scripts/check-published.sh`.
- Restart or type into Arya's live Mac from the remote screen; test on `arya@arya-pi` or
  `aryateja-jetson`.
