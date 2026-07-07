---
name: overnight-slice
description: Use for unattended or overnight work on MeshWatch — implement exactly one focused slice at a time, gate on a full build, commit only when green, and never leave uncommitted work behind.
---

# overnight-slice — one green slice at a time

Loop until out of slices or told to stop:

1. **Pick ONE slice.** Smallest shippable unit from PROGRESS.md "Next" (create PROGRESS.md with Done/Next/Blockers sections if missing; seed Next from HANDOFF.md). No slice = stop.
2. **Implement it.** Only files that slice needs. Run `xcodegen generate` if `project.yml` changed.
3. **Full gate** (all must pass):
   ```sh
   xcodegen generate
   xcodebuild -project MeshWatch.xcodeproj -scheme MeshWatch -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build
   xcodebuild -project MeshWatch.xcodeproj -scheme 'MeshWatch Watch App' -destination 'generic/platform=watchOS Simulator' -derivedDataPath build/DerivedData build
   ```
   Plus the repo's `scripts/check-*.sh` checks and any test targets that exist.
4. **Green → commit** that slice only (include the PROGRESS.md update from step 5 in the same commit). Never push.
   **Red → fix within the slice.** Two consecutive red gates on the same slice: revert the slice (`git checkout -- .` / `git clean -fd` on its files), record the blocker in PROGRESS.md, commit the PROGRESS.md note, move to the next slice. Never commit red; never leave the tree dirty between slices.
5. **Update PROGRESS.md**: move the slice to Done (one line: what + evidence), adjust Next, note Blockers.
6. Repeat from 1.

Hard rules: one slice in flight at a time; the working tree is clean after every iteration; a red gate never gets committed.
