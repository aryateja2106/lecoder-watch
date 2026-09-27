# Generated/ — the app settings files (Info.plist) for the iPhone, Watch and Mac apps, written by the project generator from project.yml

**Read first:** `project.yml` (`info:` blocks at 69-101, 126-133, 177-191 are the source), `docs/playbooks/xcode-cli.md` (xcodegen is the source of truth)
**Surface:** agent-config
**Serialized (one agent at a time):** all three follow `project.yml`, which is serialized (AGENTS.md "Must be serialized")
**Prove a change:** `xcodegen generate` then `git diff Generated/` (must equal your `project.yml` change); `sh scripts/check-brand.sh` (`scripts/check-brand.sh:20,34`); compile the owning scheme (`docs/playbooks/xcode-cli.md:80-92`)
**Traps:**
- Never hand-edit: `project.yml` `info: path` + `properties` make `xcodegen generate` rewrite these (commit 0ef035a).
- `ci_scripts/ci_pre_xcodebuild.sh:4-6` calls them hand-authored — wrong; trust `project.yml`.
- Xcode Cloud stamps `CFBundleVersion` into `iOS-Info.plist` and `Watch-Info.plist` only (`ci_scripts/ci_pre_xcodebuild.sh:42-44`); widget plists keep `$(CURRENT_PROJECT_VERSION)`, though `project.yml:153-154` says they must match.
- `GENERATE_INFOPLIST_FILE: NO` (`project.yml:21`): a usage string missing here is missing from the app.
**SDLC stage:** Build and Deploy — version, name and permission strings Apple reads at upload and install.
**Map:** see the file list above (3 files)
