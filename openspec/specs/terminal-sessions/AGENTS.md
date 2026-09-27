# openspec/specs/terminal-sessions/ — the promise that a real, lasting terminal on your machine can be driven from the watch and the phone

**Read first:** `spec.md` (requirements + scenarios), `scripts/check-watch-terminal-wiring.sh` (the check it names), `install/payload/meshd/server.ts:674` (`KEY_SEND_KEYS`, the key contract)
**Surface:** specs
**Serialized (one agent at a time):** `spec.md`
**Prove a change:** `openspec validate terminal-sessions --no-interactive` and `sh scripts/check-watch-terminal-wiring.sh` (enforces `spec.md:56-70`)
**Traps:**
- Written 2026-08-24; the key map has grown since. `server.ts:674-692` also accepts `shift-tab` and `shift-enter`, plus `ctrl-*`/`alt-*` patterns (`server.ts:695-696`); `spec.md:63-66` lists fewer. The check, not this prose, is the truth.
- `spec.md:72-82` says output is text, not pixels. The phone now also has a native PTY terminal (`pty` capability, `docs/agents/CONTRACTS.md:128`); read CONTRACTS.md before treating this spec as a description of the phone.
- "Known gaps" (`spec.md:96-107`) are owner decisions, not bugs to patch.
**SDLC stage:** Design — the accepted contract for the terminal capability, enforced by `scripts/check-watch-terminal-wiring.sh` (see [docs/sdlc/2-design.html](../../../docs/sdlc/2-design.html))
**Map:** see the file list above (one file)
