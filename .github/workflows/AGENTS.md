# .github/workflows/ — the automatic build-and-check run GitHub does on every pull request and on pushes to the main working branches

**Read first:** `ci.yml` (the whole pipeline; comments explain each choice), `docs/agents/CHECKS.md` (what each check proves), `scripts/check-all.sh` (what the `apps` job runs)
**Surface:** checks
**Serialized (one agent at a time):** `ci.yml` — load-bearing (`docs/factory/CHARTER.md:50`); a change forces `deep` gates and a human read
**Prove a change:** no local runner — open a PR (or push a matching branch) and read it with `gh run view`; locally the same steps are `sh scripts/check-all.sh` plus the three xcodebuilds in root `AGENTS.md:134-145`
**Traps:**
- Push triggers are a fixed list (`ci.yml:13-19`: `main`, `backup/**`, `release/**`, `feat/**`, `fix/**`, `claude/**`, `codex/**`); other prefixes (e.g. `sdlc/**`) get CI only through a PR.
- The `daemon` job names its 17 Linux-safe checks one by one (`ci.yml:55-104`); a new Linux-safe check is absent there until added. The `apps` job picks up every `scripts/check-*` through `check-all.sh` (`:170-171`).
- `MESH_SMOKE_REQUIRED: '1'` (`:125`) turns a missing simulator into a failure on purpose; do not remove it to get green.
- Never add a second smoke / `xcodebuild test` step: two runs on one simulator kill each other (`:162-169`).
- `MESH_LINKS_REQUIRED=1` (`:111`) makes an offline runner fail, not skip.
**SDLC stage:** Deploy (5.3) — the pre-merge check; no deploy job and no AI step in CI.
**Map:** see the file list above (1 file, 171 lines).
