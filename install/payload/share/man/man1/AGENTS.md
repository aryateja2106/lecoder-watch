# install/payload/share/man/man1/ — the `mesh` manual page shown by `mesh man`

**Surface:** docs
**Prove a change:** `man ./mesh.1`; compare its verbs with `mesh help` (HELP text in `bin/mesh` from `:2297`); no dedicated check — add scripts/check-man-page.sh
**Traps:**
- Header still reads `"2026-07-07" "mesh 0.1.0" "MeshWatch"` (`mesh.1:1`); covers hosts, sessions, status only (`mesh.1:24-96`) and misses setup, pair, upgrade, token, hooks, skills, apps, cp, fleet, sessions, doctor, kb, exposures, uninstall.
- Not refreshed by `mesh upgrade` (`bin/mesh:1179-1181`).
