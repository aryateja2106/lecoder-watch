# skills-staged — skills that are finished but not yet counted

`mesh skills install` installs every directory under `share/skills/` and
`scripts/check-mesh-skills.sh` asserts the exact number it expects (4 as of 0.6). A skill lands
here when it is ready but the count in that check has not been raised yet — raising it is a
test-file edit, which an unattended run may not make (`docs/factory/CHARTER.md`,
`TESTS_ARE_LOAD_BEARING`). To promote one: `git mv` it into `share/skills/`, bump the count in
`check-mesh-skills.sh`, run `sh scripts/check-mesh-skills.sh`.

- `mesh-knowledge/` — `/search <query>` and `/remember <title> — <body>` over the shared KB (`mesh kb`). Added 2026-09-22.
