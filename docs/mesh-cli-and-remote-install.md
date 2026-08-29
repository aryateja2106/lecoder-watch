# mesh CLI + one-curl remote install (2026-07-07)

Add any tailnet machine to the mesh with one curl, drive it from the shell, upgrade/remove cleanly.

## First time? Do exactly this

Four steps on the machine you want to control from your wrist. Nothing to configure.

**1. Install it.** Paste this into Terminal and press Enter:

```sh
curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh | sh
```

You will see a few lines scroll past and then `meshd: up`. The installer also adds one
line to your `~/.zshrc` so the `mesh` command exists in every new terminal, and it tells
you at the end to run `source ~/.zshrc` (or just open a new terminal window) so it works
in the one you are standing in. Do that now.

**2. Run the wizard.**

```sh
mesh setup
```

It walks the remaining steps and tells you what it is doing at each one.

**3. Say yes to the permission dialogs.** The wizard checks what this machine can
actually do and shows you a short list. On a Mac, anything marked `!!` is a permission
macOS has not granted yet — the wizard offers to bring up the real system dialogs, and
you click **Allow** (or flip the switch in System Settings, which it opens for you).
Without these, the watch can see your machine but cannot click or type on it.

**4. Scan the square.** The wizard prints a QR code. Open the **Camera** app on your
iPhone, point it at the code, and tap the banner that slides down. The phone adds this
machine — and every other machine it already knows about — in one go. The watch follows
automatically.

That is the whole setup. The last thing the wizard prints is your fleet:

```sh
mesh status      # every machine on one line: version, uptime, health
mesh upgrade     # keep this machine current (run it any time)
```

If you ever want the steps individually: `mesh doctor` (what works), `mesh doctor --fix`
(show the permission dialogs), `mesh pair` (the QR again), `mesh status` (the fleet).
`mesh help` lists everything; `mesh help <command>` explains one.

> Terminal says `command not found: mesh`? The PATH line has not been loaded into that
> window yet. Run `source ~/.zshrc`, or use the full path `~/.mesh/bin/mesh setup`. The
> line the installer adds is `eval "$(~/.mesh/bin/mesh shellenv)"` — you can add it to
> any shell startup file by hand.

## Serve the installer (on the Mac, always-latest)

```sh
sh scripts/serve-installer.sh          # repackages this checkout + serves on tailnet :8890
```
Prints the Mac's tailscale URL (e.g. `http://100.94.221.115:8890`). Re-run any time to publish the latest.
For always-on, wrap it in a launchd service (LaunchAgent running `serve-installer.sh`).

## Add a new host (on the target machine)

Connect, then one curl:
```sh
ssh <user>@<host-ip>
curl -fsSL http://100.94.221.115:8890/install.sh | sh -s -- --token testtoken
```
Or one line (works when no sudo prompt is needed):
```sh
ssh <user>@<host-ip> 'curl -fsSL http://100.94.221.115:8890/install.sh | sh -s -- --token testtoken'
```
Installs meshd + rmux-bridge + tools + the `mesh` CLI under `~/.mesh`, starts meshd
(systemd --user on Linux, launchd on macOS). If it reports tmux missing:
`sudo apt install -y tmux` then re-run with `--upgrade`.

- **Upgrade to latest:** `mesh upgrade` (see below). The raw
  `curl … | sh -s -- --upgrade` still works and preserves the token, but it is the blunt
  version: it reinstalls without ever proving the new daemon boots.
- **Uninstall:** `curl -fsSL http://100.94.221.115:8890/install.sh | sh -s -- --uninstall --purge`

Then add it in the app (Settings → add machine: ip, port 8899, token testtoken) or the CLI below.

## mesh CLI

Config: `~/.mesh/hosts.json`. `mesh --help`, `mesh help <cmd>`, `mesh man`. `--json` for agents.

```sh
mesh host add dataflow 100.80.10.95        # register a host (default port 8899, token testtoken)
mesh hosts                                 # list hosts + reachability
mesh ls -H dataflow                        # sessions on that host
mesh new fix-bug -H dataflow --cmd claude --task "fix the failing test"
mesh peek fix-bug -H dataflow -n 60        # recent output
mesh send fix-bug "run the tests" -H dataflow
mesh key  fix-bug enter -H dataflow        # approve a prompt
mesh usage -H dataflow                     # limits
mesh kill fix-bug -H dataflow
```
`-H` selects the host; omit it to use the default (`mesh host default <name>`), else localhost.

## Keeping the fleet current

```sh
mesh status                                # every machine: version, uptime, doctor score
mesh upgrade                               # this machine, from the latest release
mesh upgrade --src ~/Projects/lecoder-watch/install   # from a checkout (unreleased build)
mesh upgrade -H dataflow                   # a remote host, and wait for it to flip
```
`mesh status` is how you spot a host left behind. `mesh upgrade` stages the new payload,
boots it on a scratch port and makes it report its own version *before* anything moves,
swaps by rename, restarts the real service, and rolls back to the previous meshd if the
restarted daemon does not come up. Token, `hosts.json`, push tokens, KB and event log are
never touched. `-H` runs the installer in the host's own tmux session (so it survives the
restart it causes) and polls for up to 3 minutes.

## Rotating a leaked token

A meshd bearer token is a shell on that machine. If one turns up in a log, a screenshot,
a pasted config or an AI session transcript, rotate it the same day:

```sh
mesh token rotate                 # on the machine itself; asks for confirmation
mesh token rotate --yes           # no prompt
mesh token rotate -H dataflow     # rotate a peer from here
```

Locally it mints 64 new hex characters into `~/.mesh/token` (0600), keeps the previous
value as `~/.mesh/token.bak-<UTC>`, rewrites the launchd plist / systemd unit — they
embed the token, so restarting without that would bring the daemon back up on the old
one — restarts meshd, and then *proves* the running daemon serves the new token by
pairing against itself over loopback. It refuses to report success on anything less.

**The new token is never printed**, not even with `--json`. That is deliberate: printing
it is how the previous two leaked. It is in `~/.mesh/token`; better still, never read it
and let `mesh pair` hand it to the phone.

**Everything holding the old token is now locked out**, and there is no endpoint that
pushes a new token to peers (there will not be one — that is a fleet-wide remote
credential write). So afterwards:

- phone + watch: run `mesh pair` on the rotated machine and scan the code again;
- every other machine with an entry for it: `mesh host add <name> <ip> --token <new>`
  run on that machine, or re-pair it.

With `-H`, the rotation runs in its own tmux session on the target (so it survives the
daemon restart it causes) and the success signal is negative: your stored token must
start being **rejected with 401**. That is the only evidence available from here, and it
is the right one. The new token stays on that machine — copy it there or re-pair.

## Notes
- Tokens are per-machine and minted by `mesh pair`; there is no shared secret. If you find one written down somewhere, `mesh token rotate` is the fix.
- For a Linux remote, cmux/cmux-bridge is inert (macOS-only); it installs meshd core + rmux-bridge + tools.
- "Latest only": the serve script repackages this checkout each run; `mesh upgrade -H <host>` (or `--upgrade`) on any host pulls it. One source of truth.
- On Linux, `systemctl --user enable --now` is a no-op on an already-running unit, so upgrades used to copy files and leave the old daemon serving from memory. `install.sh` now restarts explicitly, and `mesh status` shows you the version each host is actually running.
