# ADR 2026-09-22 — the platform shape: onboarding, plugins, artifacts, and what a phone reads

**Status:** proposed. **Decision owner:** Arya. Written from the second review of 2026-09-22
(remote control usable; "now make it a platform"). Each section says what exists, what is
decided, and the first slice. Nothing here is built unless the row says so.

## 1. Onboarding: one command, a QR, done

**Exists (today):** `curl … | sh` installs meshd + bridge + tools and, since 473eafa, ends with
the pairing QR on an interactive terminal; scanning adopts the whole fleet; `mesh setup` is the
wizard for permissions; Guides on the phone say where the switches are.

**Decided:**
- The install one-liner is the whole first step; nothing else is typed. `mesh setup` becomes
  what the QR page on the phone links to for the *machine-side* leftovers (Accessibility /
  Screen Recording on a Mac; `loginctl enable-linger` on Linux), shown as a checklist that
  re-reads `/doctor` every few seconds until green.
- Skills, hooks and tools are installed by the installer, not asked for: `mesh hooks install`
  (Claude Code + Antigravity today; cursor and pi next per `docs/agents/harnesses.md`) and
  `mesh skills install` run at the end of a fresh install, idempotently.

**Not decided, needs Arya:** whether a fresh install should also pull the CLI agents the
machine lacks (claude/codex/fx) — it costs minutes and asks for sign-ins; the honest default
is *no*, with the Guides row "Install an agent on this machine" listing the one-liners.

## 2. Passwords, VNC, SSH — what the app will and will not touch

**Facts:** meshd already gives screen + input without VNC (that was the point). The old noVNC
row appears only when a bridge is detected. The app never sees an SSH or login password today,
and the Keychain on the phone holds only meshd bearer tokens.

**Decided:**
- **No password prompts in the app.** The mesh token *is* the credential; it is minted on the
  machine, handed over by QR, rotated by `mesh token rotate`. Nothing else is asked for.
- **VNC is opt-in and Tailscale-only.** `mesh vnc enable` (Mac: `kickstart` Screen Sharing +
  a VNC-only password set via `sysadminctl`/`defaults`, never the login password; Linux:
  `x11vnc -storepasswd` into `~/.mesh/vnc.pass`, bound to the tailscale IP) generates the VNC
  password itself, stores it in the machine's Keychain / a 0600 file, and the phone learns it
  through the paired daemon (`GET /vnc/credential`, bearer-gated) — the person never types it.
  This is the "help them create a new VNC password" ask done without a password field.
- **Reusing the login password for VNC is refused** on purpose: macOS will not export it, and a
  VNC password is a weaker secret than a login.
- SSH stays outside the app. The Terminal tab is already a shell on the machine over the
  bearer, which is the thing SSH would have been for.

**First slice:** `mesh vnc enable|disable|status` + `/vnc/credential` + the phone's Open VNC
row using it. Check: throwaway daemon mints a credential, the route refuses without bearer.

## 3. Agents from the phone: terminal + web, pinned tasks, attention

**Exists:** New session (CLI picker, cwd, task), events → *Needs you* row + bell + Choose card,
`mesh hooks install`, exposures ledger (`/exposures`, "Exposed secrets" in Settings), chat view
for Claude/Codex/Cursor transcripts.

**Decided:**
- A **pinned task** is a session with a name, a task text and a "watch this" flag: the Live
  Activity + watch complication follow it until it stops. This is the existing
  `watchedAgent` plus persistence (`UserDefaults` list) and a Pin button on the session
  screen. No new daemon route.
- **Web-auth steps** (an agent that needs a browser sign-in): the daemon already opens URLs
  on the machine (`/open`); the phone shows the URL from the pane (link chips exist) and the
  Screen & control thumbnail is where the sign-in happens. No embedded browser of ours.
- **Exposed keys:** `/exposures` is the ledger; the gap is *reach* — surface the count on the
  machine row and in the bell when > 0, with "rotate" as the verb. One-line change per surface.

## 4. Plugins: what "modular" means here, concretely

**Exists:** skills under `install/payload/share/skills/` (installed into `~/.claude/skills`,
`~/.codex/skills`, `~/.cursor/skills`, `~/.agents/skills` by `mesh skills install`); hook
clients (`mesh-hook`, `mesh-codex-notify`); a daemon whose routes are one module + two lines
each (`docs/agents/CONTRACTS.md`); `docs/agents/*` as the LLM-readable map.

**Decided — three plugin surfaces, no new runtime:**
1. **Skills** (already): a folder with `SKILL.md`; `mesh skills install` symlinks it for every
   harness. A user's own skills live in `~/.mesh/skills/` and are installed the same way.
2. **Hooks** (already, per harness): the contract is `docs/agents/harnesses.md` §B — post to
   `/events` with `session`, `level`, `replyable`, `pane`. A new CLI is a hook, not a fork.
3. **Daemon routes** (new, small): `~/.mesh/plugins/<name>/index.ts` exporting
   `routes(req, url) → Response | null`, loaded at boot after the built-ins, namespaced under
   `/x/<name>/…`, bearer-gated like everything else, and listed in `/health.plugins`. That is
   ~30 lines in `server.ts` and one doc page; it is how "my friend's Claude adds a feature"
   happens without touching our tree. The phone's Apps tab lists a plugin's declared
   `pages` (an HTML file the plugin serves) the way it lists built apps today.

**The documentation rule:** every plugin surface has a page under `docs/plugins/` written for
an LLM first (inputs, outputs, one worked example, the check that proves it), and
`docs/agents/CODEMAP.md` names it. The bar is: a new user's Claude Code can add a route from
the docs alone. The reference is dsh / the deepseek harness (`~/deepseek-harness`).

**First slice:** the route loader + `docs/plugins/README.md` + `check-plugins.sh` (throwaway
daemon loads a fixture plugin, its route answers, an unauthenticated call is refused).

## 5. What a phone reads: files, artifacts, knowledge

**Exists (today, 473eafa+):** Files → tap a file → **FileViewer**: Markdown rendered (headings,
lists, code, tables), HTML shown in a WebView, code/text with pinch to size, copy and share.
`mesh kb` + `/search` for the knowledge base.

**Decided:**
- **Artifacts** are files an agent puts in `~/.mesh/artifacts/<session>/` (a convention, not a
  route): the session screen lists that folder's newest files as chips → FileViewer. Sharing
  = the phone's share sheet (the file is already on the phone once viewed). No cloud.
- **Knowledge base on the phone:** a search field on the Files tab that calls
  `/kb/search?federate=1` and opens results in FileViewer (they are Markdown). One screen.
- **Images** in FileViewer: `/fs/read?raw=1` into an `Image` — next.
- GitHub / code sharing: not now. The `gh` CLI in a session is the honest answer until an
  agent can open a PR from a task; when it can, the PR URL is a link chip like any other.

## 6. Order of work (after this ADR)

1. Exposed-secrets reach (§3) and pinned tasks (§3) — small, visible, no new routes.
2. VNC credential flow (§2) — needs a Mac test with Screen Sharing on; do not run on Arya's
   live Mac unattended.
3. Plugin route loader + docs page (§4).
4. Artifacts convention + KB search on the phone (§5).
5. Installer runs hooks/skills install (§1).

Each lands with a check and a run record; nothing in the list edits an existing check.
