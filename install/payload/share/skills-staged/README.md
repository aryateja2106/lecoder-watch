# skills-staged — skills that are finished but not yet counted

`mesh skills install` installs every directory under `share/skills/` and
`scripts/check-mesh-skills.sh` asserts the exact number it expects (5 as of 0.8). A skill lands
here when it is ready but the count in that check has not been raised yet — raising it is a
test-file edit, which an unattended run may not make (`docs/factory/CHARTER.md`,
`TESTS_ARE_LOAD_BEARING`). To promote one: `git mv` it into `share/skills/`, bump the count in
`check-mesh-skills.sh`, run `sh scripts/check-mesh-skills.sh`.

Nothing is staged. `mesh-knowledge` (`/search`, `/remember`, `/seek`) was promoted on 2026-09-23.
