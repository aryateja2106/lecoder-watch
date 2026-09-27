# Reference-images/ — 16 iPhone screenshots of other remote-terminal and remote-desktop apps, kept as design inspiration (June 2026)

**Surface:** media — inspiration only; no code, doc or check references this folder (git grep finds it only in `docs/product/RESET-2026-09-06.md:50,148`, which lists it as not carried into the clean tree).
**What is here:** a third-party SSH terminal with an esc/tab/ctrl/arrow key bar (`IMG_8638.png`), its host settings sheet (port, SSH agent, jump host, startup scripts; `IMG_8645.png`), a lock-screen Live Activity from a terminal app (`IMG_8649.png`), and a VNC client showing a Linux desktop under a ctrl/alt/cmd modifier bar (`VNC-UI*.png`). Which apps they are is unverified.
**Traps:** the screenshots show a tailnet IP, a machine user@host and, in `VNC-UI.png`, an on-screen sign-in code; `openspec/config.yaml:83` says never commit real IPs. Do not copy them into `web/` or docs; use `docs/product/shots/` for our own UI.
