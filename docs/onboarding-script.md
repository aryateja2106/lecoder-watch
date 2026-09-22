# Onboarding, filmed — the fastest path from nothing to a session on your wrist

A shooting script for the first tutorial video, and the one place the *fastest* route is
written down. [getting-started.md](getting-started.md) is the prose guide a reader follows at
their own pace; this is the ninety seconds you record, with the exact commands, what appears
on screen after each one, and the traps that make a take unusable.

Everything below was run on 2026-09-22 against meshd 0.8.0 (the version
`curl -fsSL https://lesearch.ai/install.sh | sh` installs today) with the 0.8.0 app on a
physical iPhone and Apple Watch.

---

## What the viewer needs before you roll

- A Mac or a Linux box they can type one command into.
- An iPhone. (The watch is optional and takes no extra setup — it rides along with the phone.)
- Both on the same **Tailscale** tailnet, or on the same LAN. There is no account, no cloud
  relay and no SSH key: the machine mints a token for the phone, the phone keeps it in the
  Keychain, and nothing of ours sits in between.

Say that last sentence on camera. It is the difference between this and every other
"mobile terminal" and it is the question the comments will ask.

---

## The take — four commands, about a minute

### 1. Install the daemon (on the machine)

```sh
curl -fsSL https://lesearch.ai/install.sh | sh
```

It installs `meshd` and the `mesh` CLI under `~/.mesh`, starts the daemon (launchd on macOS, a
user systemd service on Linux), and makes both survive a reboot. Nothing runs as root.

**On screen:** a short log ending with the daemon's version and `mesh setup`.

### 2. One wizard for everything else (on the machine)

```sh
mesh setup
```

Four steps, narrated by the tool itself:

| Step | What it does | What you see |
|---|---|---|
| 1/4 | Confirms the daemon answers | `Daemon: meshd 0.8.0 running on <ip>:8899` |
| 2/4 | Runs `mesh doctor` and offers `--fix` for anything red | one line per capability; on macOS the two system dialogs (Accessibility, Screen Recording) appear here and you click Allow — on Linux nothing is asked |
| 3/4 | Prints the pairing QR and an eight-character code | a QR block, good for ten minutes, single use |
| 4/4 | Prints the fleet | `mesh status`, one row per machine |

**Trap for the edit:** the permission dialogs in 2/4 only appear the first time, and they
appear behind the terminal window. Move the terminal before you record, or the take has
forty seconds of nothing.

### 3. Scan the QR (on the phone)

Open the **Camera** app — not the LeSearch app — and point it at the QR. Tap the banner. The
app opens with the address, port and code already filled in; check the code matches the
terminal, tap **Pair**.

The screen that follows says how many machines were added. **If the machine you paired
already knew about others (`mesh hosts`), they all come along with their own tokens** — that
is the fastest multi-machine path and the thing worth showing: three machines, one scan.

**No camera in the shot?** LeSearch AI → **Machines** → **Add machine**, type the address,
the port and the eight characters. Case and the dash do not matter.

### 4. Wire the agent alerts (on the machine, once)

```sh
mesh hooks install
```

`mesh setup` deliberately does **not** do this — it is the one step that edits an agent's own
config. After it, Claude Code's prompts reach the phone and the watch as *Needs you* rows you
can answer with a tap. Codex and Antigravity print their one-line config instead.

---

## The payoff shot — 30 seconds, and the reason anyone installs this

Do not end on a paired row. End on work.

1. Phone → **Terminal** → the machine → **+ New session** → pick `claude`, set a working
   directory, type a task. The session starts on the machine.
2. Switch to **Terminal** mode in the session. This is the shot: the agent's real screen, in
   colour, with its cursor — a live pty attached over the tailnet, not a screenshot and not a
   poll. Pinch to change the font; the key bar has Ctrl and Alt (tap once for one key, tap
   again to lock), Esc, Tab, and ↑ that opens a d-pad when held.
3. Let the agent ask for permission. The phone shows the numbered list as **buttons**; tap one.
4. Raise your wrist: the same question, the same buttons, on the watch.

Steps 3 and 4 are the whole product. Film them last and do not cut them short.

---

## Multi-machine, for the second video

On the machine you paired, teach it about the others once:

```sh
mesh host add pi 100.94.168.17
mesh host add jetson 100.118.47.127
```

(`--token` if that machine minted its own; `mesh hosts` lists what it knows.) Then any phone
that pairs with this machine adopts the whole fleet in one scan. `mesh status` is the proof
shot: one row per machine, each with its version and `doctor: 7/7 ok`.

---

## When a machine will not come back

Removing a machine from the phone **tombstones** it: pairing with a *different* machine will
not resurrect it, on purpose, so a deliberate removal survives the next QR scan. Until 0.8.0
that was silent — the sheet said "Added 2 machines" and the third was simply gone. Now the
Pair screen lists it under **Not added**, with an **Add anyway** button that clears the
tombstone and adds it.

Two ways back, both in the app you have:

1. **Add anyway** — pair with any machine that knows the missing one, then tap it in the
   *Not added* section.
2. **Pair with the machine itself** — pairing a machine always un-removes it. Codes are
   minted only on the machine, so run it there (ssh is fine, the QR prints in your terminal):

   ```sh
   ssh <user>@<machine> 'PATH="$HOME/.bun/bin:$PATH" ~/.mesh/bin/mesh pair'
   ```

   The explicit `PATH` matters over a non-interactive ssh: `mesh` is a `#!/usr/bin/env bun`
   script and the installer puts bun on the PATH in the interactive part of the shell rc, so
   a bare `ssh host '~/.mesh/bin/mesh …'` dies with `env: 'bun': No such file or directory`.

## What not to claim on camera

- **The phone app is not on the App Store or TestFlight at 0.8.0 yet.** The daemon is
  published; the store build is older. Say "the app is in beta, link in the description" and
  point at whatever is live when you publish, or film with a build installed over the cable.
- **Streaming needs a 0.8.0 daemon.** Against an older one the terminal still works, in one
  colour, repainting from polls. If a viewer's terminal looks flat, that is the tell.
- The watch **shows** the terminal and answers prompts; it does not render video or a full
  emulator. Do not imply a terminal on the wrist.
- A machine whose **monitor is asleep** streams a black screen: the thumbnail and Screen &
  control are honest, there is simply nothing lit. Any input wakes it — a two-pixel pointer
  move is enough — so nudge the trackpad before you film that machine.
