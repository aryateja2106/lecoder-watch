# intent/ — NOT the place for new ideas: this is the tool list and test phrases for the small on-device model that turns a spoken wrist command into an action

> **Warning — two folders, one letter apart.** `intent/` (this one, singular) is the local-brain
> tool catalogue plus its acceptance test. Playbook Stage 1 intents ("what problem, for whom")
> go in `intents/` (plural). Never write a playbook intent here; never put tool schemas there.

**Read first:** `scripts/check-intent.sh` (what this proves, the floor), `docs/product/PRODUCT.md` §9 at :376 (the design), `docs/adr-2026-09-22-on-device-brain.md` (the next slice)
**Surface:** data
**Serialized (one agent at a time):** `cases.jsonl` — the frozen acceptance suite (`check-intent.sh:5`); add cases, never edit an expected answer to make a run pass
**Prove a change:** `sh scripts/check-intent.sh` (floor 24/28 right tool, `check-intent.sh:11-21`); `MESH_INTENT_REQUIRED=1` makes a missing model binary a failure instead of a skip
**Traps:**
- It SKIPs with exit 0 on this Mac: the Needle binary it wants (`references/external/models/needle2/`, `check-intent.sh:23`) is not on disk (2026-09-27 run). A green `check-all.sh` says nothing about this suite. Downloading the model is Arya's decision; the script prints the command, do not run it unasked.
- `mesh-tools.json` is hand-maintained. PRODUCT.md:396 says it is "generated from this document", but no generator exists (`git grep mesh-tools` finds only docs and the check), and it has drifted: it adds `copy_file` (:359) and `search_knowledge` (:392) and lacks `switch_machine` from PRODUCT.md:400.
- `send_key` allows `y` and `n` (`mesh-tools.json:68-69`), which are not daemon keys (`install/payload/meshd/server.ts:674-693`). "Every tool is an existing daemon route" (`check-intent.sh:4`) is not fully true; the mapping layer is unbuilt.
- Nothing in the apps or daemon reads these files yet (no Swift/TS consumer found); this is a measurement, not a live feature. Root AGENTS.md rule 1 applies before claiming the wrist understands a phrase.
**SDLC stage:** Test — a 28-case eval suite for one model (the playbook's "20–50 real tasks with acceptance checks") (see [docs/sdlc/4-test.html](../docs/sdlc/4-test.html))
**Map:** see the file list above (`mesh-tools.json`: 16 tools; `cases.jsonl`: 28 cases)
