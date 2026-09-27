# docs/recordings/ — drop zone for screen recordings Arya shares so an agent can watch a bug or a flow

**Surface:** media
**State:** created 2026-09-27 with only this file; no recording has been committed. The only other mention is `docs/self-serve-apps.md:58` (proof recordings in a built app's repo).
**Trap:** `.gitignore` does not ignore this folder or `*.mov` / `*.mp4` (`git check-ignore` exit 1), so `git add -A` would commit large videos. Stage recordings deliberately, or keep them out of git.
**Prove a change:** no dedicated check.
