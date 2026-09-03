# Core agent stack — applied 2026-09-02

## Kept (7) and what each now carries

| agent | version | rtk | ponytail 4.9 | caveman 2.4 | global instructions |
|---|---|---|---|---|---|
| claude | 2.1.257 | PreToolUse hook (native) | plugin | plugin + `/caveman` | `~/.claude/CLAUDE.md` = OMC 5.1 block + `@~/.agents/BASE.md` + `@RTK.md` |
| codex | 0.152.0 | `~/.codex/AGENTS.md` rules + RTK.md | plugin (trust hooks: run `codex`, `/hooks`) | `~/.agents/skills` (native read) | `~/.codex/AGENTS.md` 21.6 KB (~5.4k tok — trim candidate) |
| agy (Antigravity) | 1.1.22 | per-project: `rtk init --agent antigravity` | plugin `~/.gemini/config/plugins/ponytail` | `~/.agents/skills` | `~/.gemini/GEMINI.md` imports BASE.md |
| pi | 0.84.4 | `~/.pi/agent/extensions/rtk.ts` | `pi install git:…/ponytail` | `pi install git:…/caveman` | project AGENTS.md only |
| omp (Oh My Pi) | 18.0.11 | `~/.omp/agent/extensions/rtk.ts` | omp plugin 4.9.0 | omp plugin caveman-installer 2.4.0 | none (providers off in config.yml) |
| dsh | 0.1.1-rc.2 | `~/.dsh/rtk-shims` (pre-existing) | `~/.dsh/skills/ponytail.md` | `~/.dsh/skills/caveman.md`, `caveman-compress.md` | per-profile patches |
| cursor-agent | 2026.08.31 | `~/.cursor/hooks.json` preToolUse | `~/.agents/skills/ponytail*` | `~/.agents/skills/caveman*` | project AGENTS.md |

`~/.gemini` is Antigravity's home (`antigravity-cli/brain|knowledge`, plugins) — never delete it.

## Removed (quarantined, reversible) → `/Volumes/External Storage/QUARANTINE-2026-09-02/`
Binaries: gemini-cli (brew), multica (brew), hermes, jcode. launchd: `ai.hermes.gateway` unloaded + plist moved. Dotdirs: .hermes 2.1G, .jcode, .alook, .copilot, .claude-free, .claude-mc, .cagent, .smolvm, .paseo 988M, .notebooklm-mcp-cli, .headroom, .playwright-mcp, .cf-agentic, .mcpc, .gjc, .lescout, .omx-runs. Repos: multica-arya (clean, on GitHub), multica-arya-latest. Misc: migrate-gbrain.sh, SecondBrain.shell-bak. Total 4.8 GB.
Left alone: omnara (daemon, remote-control not a coding agent), oh-my-codex npm (omx, stale — remove if unused), old plugin caches 4.15.4/4.7.0 (pinned by another live Claude PID; auto-swept).

## Plugins (Claude)
OMC 4.15.6 → **5.1.0** (npm `omc` 5.1.0 too; `omc setup --force` ran; v5 dropped ultrawork/ccg/omc-reference/sciomc/deep-dive/… → use `/execute /team /review /research /remember /wiki`). ponytail 4.7.0 → **4.9.0** (`/ponytail default <mode>` persists; SubagentStart hook). **caveman** added (marketplace JuliusBrussee/caveman). 8 stale `enabledPlugins:false` keys removed. Legacy skill backups removed.
Commands now: `/oh-my-claudecode:{ai-slop-cleaner ask autopilot autoresearch cancel configure-notifications debug deep-interview deepinit drydock execute external-context graph hud launch minimal-code-discipline omc-doctor omc-setup plan project-session-manager ralph ralplan release remember research review self-improve skill skillify team trace ultragoal verify visual-verdict wiki}` · `/ponytail{,-audit,-debt,-gain,-help,-review}` · `/caveman{,-help,-stats,-compress,-commit,-review,-learn,-explore,-init}`.

## rtk
0.46.0 (brew latest). 0.47.0 released today, brew not bottled yet → `brew upgrade rtk` in 1–2 days. `rtk gain`: 323K tokens saved (51%) over 1184 commands so far. Config file not created (defaults fine).
Caveman proxy (input-side, 33% claimed) NOT installed — opt-in: `caveman setup --install` then run `caveman claude` / `caveman codex`. `caveman learn` needs it too.

## MCP
MCP_DOCKER (dead) removed from Claude + Codex. Needs auth if wanted: cloudflare×4, mobbin, Apify. Rest connected.

## Skills
Catalog: `~/3-Resources/skills-catalog/INDEX.md` — 289 unique (68 dups folded), tick-list by category; 25 real design skills. Pool: `~/.agents/skills` (28) ← symlinked into `~/.claude/skills` (29); Codex/Cursor/Antigravity read pool natively. Cloud-only caveman skills pruned.
Design pick suggestion (keep 5, drop the other 20): `impeccable` (general UI), `design-taste-frontend` (web anti-slop), `meshwatch-ui-taste` + `claude-design-to-meshwatch-swiftui` (Apple native), `imagegen-frontend-mobile` (screen concepts). Overlapping: high-end-visual-design, gpt-taste, minimalist-ui, industrial-brutalist-ui, stitch-design-taste, redesign-existing-projects, scrollcraft, image-to-code, imagegen-frontend-web, brandkit, higgsfield×5.

## Knowledge hub `~/Knowledge`
vault (SecondBrain, moved) · okf (moved) · agent-memory/ (symlinks: claude ×7, lecoder-watch, omc ×4, omp mnemopi, dsh notes, codex history) · legacy-memory-systems/ (mempalace, gbrain, agentmemory, claude-mem — 387 MB). Old paths symlinked back; zshrc VAULT, BASE.md, _nav-hub/brain, ops/config.yaml updated. README inside.

## Shell
`.zshrc` 491 → 347 lines (backup `.zshrc.bak-2026-09-02`): removed amp/gemini/clawhip/openclaw/kiro/PAI/claude-mem/mission-control; `aihelp` rewritten for core-7. Stale: `airepo` alias points at `vault/ops/scripts/airepo.sh` which does not exist.

## You
- `sudo ~/2-Areas/machine/delete-old-tm-backups.sh` (1.3 TB)
- `codex` → `/hooks` → trust ponytail's 2 hooks
- Restart cmux (Shift+Enter) · reopen Obsidian vault from `~/Knowledge/vault`
- Decide: iOS/watchOS 26.5 sim runtimes (11 GB), Docker Desktop (12 GB), QUARANTINE-2026-09-01 (129 GB) date
