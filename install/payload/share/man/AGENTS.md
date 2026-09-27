# install/payload/share/man/ — the `mesh` manual page, in the standard Unix man format

**Surface:** docs
**Prove a change:** `man ./man1/mesh.1` renders; no check references it — add scripts/check-man-page.sh
**Traps:** stale since 2026-07-07 (see `man1/AGENTS.md`); `mesh man` opens `~/.mesh/share/man/man1/mesh.1` (`bin/mesh:2565-2569`).
