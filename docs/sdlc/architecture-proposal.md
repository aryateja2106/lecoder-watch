# Architecture proposal: modules, security, your own apps, and many machines

**Status:** proposed. **Decision owner:** Arya. **Date:** 2026-09-27.
**Tree:** branch `sdlc/ai-native-playbook`, tip `5710d51` (2026-09-27).

Nothing in this document is built. Every file it names was opened in that tree. Anything that was
read in code but not proven by running it is marked **unverified**. This is the final version of
a draft that a second, sceptical reviewer then tried to knock down. Each of the reviewer's
points is answered where it belongs, marked **Accepted** or **Rejected**, with the reason.

## How to read this

Each of the four topics has the same shape:

1. **In plain words**: what is true today and what I recommend, with no jargon.
2. **What the review changed**: each objection and how it was settled.
3. **First slice**: the smallest piece of work, the files it touches, and the `scripts/check-*.sh`
   that proves it.
4. **If you want the mechanics**: a folded section with the technical detail, for you or an
   agent.
5. **Questions for Arya**: each one can be answered with yes/no or by picking a letter.

Three rules outrank everything below, and every proposal was checked against them:

- **The non-goals.** No cloud relay, no VNC, no account system. Local-first forever
  (`ROADMAP.md:112-118`, `docs/product/PRODUCT.md` §10).
- **Reviewable in one sitting.** The daemon stays dependency-light Bun + TypeScript. One
  capability is one module plus a small `server.ts` patch (`ROADMAP.md:20-22`,
  `docs/product/PRODUCT.md:457`).
- **Verify by running, not by building** (`AGENTS.md:21-25`). Every proof boots a throwaway
  daemon on a spare port and never touches the live one on `:8899` (`AGENTS.md:52-58`).

> **Why some security detail is missing on purpose.** This repository is public. The
> project's own rule is that an unfixed security hole is described by its *outcome* only, and
> the step-by-step reproduction goes into the check that is committed *together with* the fix
> (`docs/sdlc/references/security-audit-skill.md:290-309`). Topic 3 follows that rule.

## Summary

| Topic | Draft said | Final recommendation | First slice | Needs your OK because |
|---|---|---|---|---|
| 1. TypeScript + Rust | Rust as separate helper programs; first one an audit-log checker | **No Rust now.** Keep one written rule for the day Rust is justified. Make module compatibility enforceable in TypeScript instead | A tiny check that stops new daemon features from shipping without a client-side guard | Nothing (a new check only) |
| 2. Security and audit | A daemon logbook first; vendor the audit skill into the repo | **Close known doors first, then the logbook**, and the logbook must cover terminal typing too | Require the password (bearer) to mint a pairing code (finding SEC-03) | It changes pairing and edits two existing checks |
| 3. Your own apps | Longer app-link secrets first, then app servers | **Give agent-built apps their own address (port) first**, then longer secrets. App servers wait for a real app that needs one | Serve apps on their own port; the daemon port only redirects | It edits three existing checks |
| 4. Many machines | New daemon code for a separate project copy per agent | **No new daemon code.** Prove the agent tools' own "separate copy" option through the existing start-a-session path. "What to show where" becomes a design intent | A check that two sessions started from one project land in two separate copies | Nothing (a new check only) |

**Order of work.** 3 → 2 → 3's second slice → 2's audit steps. Topic 4's slice and topic 1's
slice are new checks only, so they can run in parallel with anything
(`AGENTS.md:229` allows a single new check in parallel). The slices in topics 2 and 3 all
touch pairing, `install/payload/meshd/server.ts` or existing checks, so they run one at a time,
with you present (`AGENTS.md:233-239`, `CLAUDE.md` non-negotiable 3).

---

## 1. TypeScript and Rust: how to split the modules and keep them compatible

### In plain words

Your product has one small background program on each machine, `meshd`, written in
TypeScript. It already works alongside one program written in another language: `mesh-input`,
a Swift helper that moves the Mac's pointer. The daemon starts it as a **separate program** and
sends it one line of text per command, so if the helper crashes, the daemon keeps running. That
is the only safe way Rust should ever come in.

My recommendation is **no Rust for now**. Nothing in the product has been measured as slow.
Adding Rust would cost a new toolchain on every build machine and a separate build for each kind
of machine (Mac, Pi, Jetson) on every release. That is a lot of cost for no gain, in a year where
the focus is revenue.

The more useful answer to "how do I make the modules compatible" has nothing to do with the
language. Each daemon feature announces itself with a name (a "capability"), and the phone and
watch are supposed to check that name before showing the feature. Today, 16 of the 32 names are
checked by nothing (`docs/agents/CONTRACTS.md:94-129`). When a phone meets an older daemon, it
can show a broken screen instead of saying what is missing. The first slice stops that number
from growing.

### What the review changed

- **The Rust audit-log checker is cut. Accepted.** The draft itself said nothing needs Rust.
  The checker would be about 20 lines of TypeScript. The argument that a second language catches
  bugs does not hold for one call to a standard hash function. It also depended on two later
  pieces of work (a hash chain and copying it off the machine) that are themselves deferred.
- **A Rust check would turn the whole test suite red on machines without Rust. Accepted.**
  `scripts/check-all.sh:29-33` runs every `check-*.sh`, and `.github/workflows/ci.yml` installs
  no Rust. A check that fails without `cargo` would break the suite everywhere else.
- **The slice was not small. Accepted.** It touched the installer, the release packaging and a
  version-lockstep rule. That is the part of this product that has failed silently before.
- **Keep one paragraph as the rule, and ask why Rust. Accepted**, with one addition from this
  review: your earlier product, the `lesearch` Rust control plane, is listed as retired in
  `docs/product/PRODUCT.md:75`. "Bring Rust features" may mean "bring back features from that
  product", not "write new code in Rust". That is a question below, not an assumption.

### The rule, if Rust ever comes

> A Rust program is added only when a measurement or an accepted intent justifies it. It runs as
> a separate process that speaks newline-delimited JSON, like `mesh-input`. It is never loaded
> inside `meshd`. The route table, authentication and pairing stay in TypeScript. A capability
> never has a live TypeScript *and* a live Rust version at the same time.

### First slice: stop the "unguarded feature" count from growing

- **Files:** one new file, `scripts/check-capability-ratchet.sh`. No product code changes.
- **What it does:** counts the capabilities that `docs/agents/CONTRACTS.md` marks
  "(nothing gates it)" and fails if the count is above 16, today's number. The count may go
  down, never up. A new daemon feature then has to arrive with a guard on the phone or watch.
- **Proof:** `sh scripts/check-capability-ratchet.sh` passes on today's tree. Adding a
  capability string to the list in `install/payload/meshd/server.ts:51` and regenerating the map
  with `sh scripts/codemap.sh`, without a client guard, must make it fail. The builder shows
  this once in a scratch copy and pastes the output. `./.claude/scripts/gates.sh fast` ends
  GREEN.

<details>
<summary>If you want the mechanics</summary>

**What exists today**

- `meshd` is one Bun process. Entry: `install/payload/meshd/server.ts`, version `0.8.0` at
  `server.ts:30`, capabilities list at `server.ts:51`, advertised on `/health`.
- The one native helper is a sidecar. `install/payload/bin/mesh-input.swift` is compiled on the
  user's Mac by `swiftc` when needed (`install/payload/meshd/input.ts`), and it reads JSON lines on
  stdin. macOS grants Accessibility per binary (`CONTEXT.md:77`), which is one reason the helper
  is a stable separate file.
- The terminal bridge `install/payload/rmux-bridge/src/server.ts` imports the daemon's redactor
  by relative path. "One implementation, several processes" is already the pattern.
- `git ls-files '*.rs' Cargo.toml` returns 0 files. `.github/workflows/ci.yml` mentions neither
  `cargo` nor Rust.
- The measured numbers people cite as reasons for Rust are fine in TypeScript: a 139 MB
  transcript stored in 1.6 s, an append in 65 ms, daemon peak 105 MB of memory
  (`docs/sdlc/references/agent-git.md:200-203`).
- `docs/sdlc/references/agent-git.md:191-210` compares the options: separate helper program,
  WebAssembly, N-API addon, `bun:ffi`. Its recommendation, which this document adopts: no Rust
  now; WebAssembly if a pure computation is measured slow; a separate helper if something needs
  the OS or its own crash domain; never code loaded inside `meshd`.

**If a Rust helper is ever approved**, the shape is taken from agent-git
(`docs/sdlc/references/agent-git.md:212-225`): a pure library crate plus a thin binary crate in
one new top-level folder, never inside `install/payload/meshd/` (`AGENTS.md:48-50`, one daemon
copy); a handshake line with a protocol number as the first message; credentials in that first
message or an environment variable, never in command-line arguments, which every local user can
read (`docs/sdlc/references/agent-git.md:177`); the feature advertised as a capability only after
the handshake succeeds; binaries built per platform at release time and never committed; and a
name of the form `mesh-<job>`, never `lesearch` or `lecoder` (`docs/product/PRODUCT.md:75`).

**Why the capability ratchet is the compatibility answer.** `docs/product/PRODUCT.md:452` says
clients gate on capabilities, never on version strings. The generated table in
`docs/agents/CONTRACTS.md:94-129` shows that half of the advertised capabilities have no client
guard; several (`events`, `agents`, `pair`) are older than the capability system and may never
need one. So the check does not demand that the count reach zero. It only stops it from
growing. `docs/sdlc/references/orca.md:146` describes the same "number that may only go down"
technique.

**Draft ideas kept out:** the `rust/` workspace, `mesh-verify`, the three-target release build,
and the version-lockstep check. None has a user today.

</details>

### Questions for Arya

1. When you said "bring TypeScript and Rust features", which did you mean?
   (a) write some parts in Rust · (b) bring back features from the old `lesearch` Rust control
   plane · (c) borrow features from Rust tools like agent-git · (d) learn Rust on this project.
2. If (a): is there one specific feature you want in Rust? If not, the answer stays "not yet".
3. May the capability ratchet check be added? (yes/no)
4. Should the "if Rust ever comes" rule above be copied into `AGENTS.md`? `AGENTS.md` is a
   protected file, so only you can say yes. (yes/no)

---

## 2. Security and auditability

### In plain words

The daemon's front door is well guarded: a long secret (the token) checked in a way that leaks
nothing through timing, a check that stops ordinary web pages from sneaking in, and one-time
pairing codes. Secrets that agents print are masked before they leave the machine.

"Auditability" can mean two different things, and you may want both:

- **A way to audit the app for holes.** The Cloudflare security-audit skill you pointed to does
  this. It costs no product code.
- **A logbook of who did what on each machine.** For example: "who approved that agent at
  2 a.m.?" Today, when you tap Allow on the phone, the daemon presses Enter in the agent's
  terminal and writes nothing down (`docs/sdlc/references/openmuse.md:13-15`).

The review changed the order. "Security is paramount" means closing doors already known to be
open **before** installing a camera. One known door is in pairing (this topic). A more serious
one is in how your own apps are served (topic 3, which goes first). The logbook comes after
both. When it comes, it has to record terminal typing as well, because that is how you approve
agents most often.

### What the review changed

- **Password checks and the local-program exemption are as the draft described.** Confirmed
  by reading `install/payload/meshd/auth.ts`, `install/payload/meshd/loopback-trust.ts:14-39`
  and `install/payload/meshd/pair.ts`. No change needed.
- **"A web page in the Mac's browser can do nothing" was wrong. Accepted.** A page that an
  agent built can very likely act as you when it is opened on the Mac itself. This was found by
  reading the code and has not been reproduced by running it. The fix is topic 3's first slice.
- **"No route can forget to log" was wrong for terminal typing. Accepted.** The phone's
  terminal sends keystrokes over a live connection that bypasses the place the draft's logbook
  sat. The draft's proof would have gone green while the most-used input path stayed unlogged.
  That is the "compiles green, dead in use" pattern `AGENTS.md:21-25` warns about. **Fix
  chosen:** when a terminal connection closes, the logbook records how many bytes and how many
  Enter presses were sent through it. It never records the content itself.
- **The logbook must cope with a connection that has been upgraded to a live terminal.
  Accepted.** In that case the request handler returns nothing
  (`install/payload/meshd/pty.ts:42-59`), and the logbook code must handle that.
- **Close known doors first. Accepted, with one correction from this review.** Requiring the
  password to create a pairing code (SEC-03) stops a local program from collecting **every
  other machine's** token. It does **not** stop that program from using **this** machine,
  because the local-program exemption still applies to every other route. Protecting this
  machine from a sandboxed agent needs the separate decision on the exemption's default, which
  `docs/product/PRODUCT.md:184` already lists as yours.
- **Decide how long the logbook is kept before it ships. Accepted.** An append-only file on the
  always-on Jetson with no limit fills the disk slowly.
- **Tamper-proof chaining of log lines is deferred. Accepted.** It protects only against an
  attacker who already holds your token, and no client or incident has asked for it.
- **Copying the audit skill into `.claude/skills/` is not needed for the first run. Accepted in
  part.** For the first, read-only run, a pinned copy kept outside the repo is lighter and
  touches no protected folder. **Kept for later:** vendoring gives Codex and Cursor the same
  skill and lets a check prove the copy was not modified
  (`docs/sdlc/references/security-audit-skill.md:451-473`). If audits become a habit, that is
  worth doing. It is a question below.

### Order inside this topic

1. **SEC-03: a pairing code needs the password** (first slice, below).
2. **First read-only security audit** of the daemon, installer and bridges with the Cloudflare
   skill. Results stay on your Mac, never in git (`docs/sdlc/references/security-audit-skill.md:290-294`).
   The nine known findings in `docs/review-2026-09-17.md:93-101` are its starting list.
3. **The logbook** (`audit.ts`), including terminal counts and a size or age limit.

### First slice: a pairing code needs the password (SEC-03)

- **Files:** `install/payload/meshd/server.ts:1356` (minting requires the token itself; the
  local-program exemption no longer applies to this one route);
  `MeshDesktop/LocalDaemon.swift:91` (the Mac menu bar app reads `~/.mesh/token` and sends it);
  `scripts/check-token-rotate.sh:75` (sends the token); `scripts/check-pair-auth.sh:38` (expects
  refusal without a token instead of success); `docs/product/PRODUCT.md:184` (the rule is
  restated). The `mesh` command line already sends the token (`install/payload/bin/mesh:799`).
- **Proof:** `sh scripts/check-pair-auth.sh` (edited: no token now means 401, the token still
  means 200) and `sh scripts/check-token-rotate.sh` (edited: green with the token sent). Also
  `./.claude/scripts/gates.sh fast`, then `full`, because the Mac app's Swift is only compiled by
  the `full` gate.
- **Human gate:** it changes pairing (`AGENTS.md:239`) and edits two existing checks. The run is
  attended, with your explicit OK.

<details>
<summary>If you want the mechanics</summary>

**Layers every request passes today** (`install/payload/meshd/server.ts:1327-1363`):

| Layer | Where | What it does |
|---|---|---|
| Host check | `server.ts:1260-1268`, called at `:1333` | Refuses a `Host` that is not loopback, a `*.ts.net` name, or one of the machine's own names or addresses (DNS-rebinding defence) |
| Open routes | `server.ts:1334-1348` | `/health`; `GET /a/*` gated by the key in the path |
| Browser check | `server.ts:1196-1207`, called at `:1350` | Refuses cross-site requests; allows a request whose `Origin` is the daemon's own |
| Pairing | `server.ts:1356`, `pair.ts` | Short code, 10 minutes, single use; a claim returns this machine's token and every token in `~/.mesh/hosts.json` |
| Bearer | `auth.ts` | Fail-closed on an empty token; constant-time compare |
| Local-program exemption | `loopback-trust.ts:14-39` | A caller on 127.0.0.1 skips the bearer unless a forward header is present or `MESHD_TRUST_LOOPBACK=0` |
| Mirror token | `sessions.ts` | Opens only the session list, index and redacted chunks |
| Redaction | `redact.ts` | Masks secrets on outbound paths and counts each hit by fingerprint |

**What is not enforced** (read in code): no per-action log; no limit on failed password
attempts; no TLS, and the default bind is all interfaces (`server.ts:28`, finding SEC-01); no
per-route scopes, since the token can do anything by design.

**Threat table, corrected rows only** (the rest of the draft's table held up):

| Who | What they can do today | Status |
|---|---|---|
| A page in the Mac's browser from any other site | Nothing: the browser check refuses it | Holds |
| An agent-built app page opened on the Mac itself at a local address | Very likely everything the token allows | Found by reading, not reproduced. Fixed by topic 3's first slice |
| Another local user, or an agent sandboxed as its own user | This machine through the exemption; every paired machine's token through pairing | SEC-03 closes the second part. The first part is the exemption-default decision |
| Whoever answers a prompt through the phone's terminal | Types anything; nothing is recorded | The logbook step records counts |

**The logbook, when its turn comes** (third in this topic):

- New `install/payload/meshd/audit.ts`. `server.ts` wraps its request handler with it: an import,
  about three lines, a `GET /audit?since=` route and `"audit"` in the capability list.
- One line per non-`GET` request, per refusal (401, 421), per pairing claim, and per sensitive
  read (`/fs/read`, raw session reads). Status polls are skipped.
- Each line holds the time, method, route, status, how the caller got in (bearer, local,
  mirror, pair code, refused) and the caller's network address. For `/agents/:x/send` it holds
  the key names and the *length* of any text, never the text. On Tailscale each device has its
  own address, so the address mostly answers "which device" (unverified in this repo). True
  per-device identity needs per-device tokens, a pairing change deferred to your decision.
- Terminal connections: `install/payload/meshd/pty.ts` gets counters in its `message` handler
  (`pty.ts:115-131`) and writes one line in its `close` handler (`pty.ts:133-138`): session,
  bytes sent, Enter presses. Content is never logged.
- The file is `~/.mesh/audit.jsonl`, mode 0600, redacted before writing, with the path
  overridable by `MESHD_AUDIT_PATH` for tests, and rotated at the limit you choose.
- Proof: a new `scripts/check-audit-log.sh` that boots a throwaway daemon with a private tmux
  socket (the pattern in `scripts/check-approve-path.sh:36-43`) and asserts: a send with `enter`
  writes one line; a wrong token writes a 401 line; a status poll writes nothing; a fixture
  secret's text never appears, only its length; a terminal connection that sends two Enters
  writes one close line with `enters: 2`; the file mode is 0600; the file rotates at the limit;
  `/health` lists `audit`. `scripts/check-mesh-auth.sh`, `scripts/check-approve-path.sh`,
  `scripts/check-redact.sh` and `scripts/check-pty-route.sh` stay green unmodified.
  `docs/product/PRODUCT.md` §5.2 gains the module row in the same change
  (`scripts/check-product-spec.sh` enforces it), and `sh scripts/codemap.sh` keeps
  `scripts/check-codemap.sh` green.

**The first audit run**: source-only, because this Mac cannot enforce a memory limit on test
code and Docker is not running (`docs/sdlc/references/security-audit-skill.md:334-354`). Output
goes to `~/security-audit-skill/lecoder-watch/run-1/`. A confirmed finding with a one-file fix
gets a new `scripts/check-sec-<slug>.sh` committed together with the fix. Anything larger becomes
a draft `intents/YYYY-MM-DD-sec-<slug>.md` with `source: security-scan`, describing the outcome
only (`docs/sdlc/references/security-audit-skill.md:295-322`).

</details>

### Questions for Arya

1. "Auditability skills" meant: (a) a way to audit the app for holes · (b) a logbook of who did
   what · (c) both.
2. May the SEC-03 slice change pairing and edit `scripts/check-pair-auth.sh` and
   `scripts/check-token-rotate.sh`? (yes/no)
3. Do you run, or plan to run, agents as a separate user (the Linux `--user` install)? If yes,
   the local-program exemption should be off for those installs. (yes/no)
4. Keep the logbook for: (a) 30 days · (b) 90 days · (c) up to a fixed size, for example 50 MB ·
   (d) forever.
5. Terminal typing in the logbook: (a) counts only (bytes and Enter presses, recommended) ·
   (b) not at all, and the gap is written down in `docs/product/PRODUCT.md`.
6. Where do security findings live until fixed: (a) this Mac only (recommended) · (b) GitHub
   private security advisories · (c) a private repo.
7. Copy the audit skill into the repo for all three agent tools later, once audits are routine?
   (yes/no)

---

## 3. Serving your own apps securely from your machine

### In plain words

Today an agent can build you a web app, and your Mac serves it at a private link with a secret
in it. The app's data lives in the browser on each device, so a visitor cannot change anything
on your Mac. That part already matches "we don't want anyone to just access it and delete or
edit stuff" (`docs/sdlc/references/nethera.md:96-105`).

The review found a more important problem than the one the draft led with. The apps are served
**from the same address as the daemon itself**. Browsers treat everything at one address as one
trusted family. So an agent-built page, **when opened on the Mac itself** through a local
address, can very likely do anything your token can do, without knowing the token. This was
found by reading the code; it has not yet been reproduced by running it, and the first step
does that. It matters because agents build these pages, and the app-builder skill encourages
testing them at a local address (`install/payload/share/skills/pwa-local-app-builder/SKILL.md:27-29`).
Opening the app from your phone does not trigger it.

The fix is to give apps **their own address** (a second port). The daemon's port then only
forwards old app links to the new port, so links already saved on a Home Screen keep working.
After that comes the draft's fix: a longer secret in each link. Apps with their own server
(shared data, edit rights) wait until you name a real app that needs one.

### What the review changed

- **The shared-address problem goes first. Accepted.** A separate port is a separate address to
  a browser, which is the only way found that does not break something else (see the
  alternatives in the mechanics).
- **"It is one module change and one check" was too optimistic. Rejected.** This review found
  that three existing checks assume apps live on the daemon's port:
  `scripts/check-apps-serve.sh:43-64`, `scripts/check-apps-ota.sh:87-131` and
  `scripts/check-mesh-apps.sh:53,63`. The command line prints the daemon port in every app link
  (`install/payload/bin/mesh:2038-2041`), and wireless install maps `/a` to the daemon port
  (`install/payload/bin/mesh:1936`). All of these change, so the slice needs your OK to edit
  existing checks.
- **A browser "sandbox" header would be one line but breaks app storage. Accepted** as a
  rejected alternative. It gives the page a blank identity, and the app skill keeps data in
  browser storage (`install/payload/share/skills/pwa-local-app-builder/SKILL.md:24-26`).
- **The canonical spec and the code disagree. Accepted.** `docs/product/PRODUCT.md:185-187`
  says any request with an `Origin` header is refused. The code allows the daemon's own origin
  (`install/payload/meshd/server.ts:1200-1206`) so that the web console works. The first slice
  corrects the spec in the same change.
- **Longer link secrets second, not first. Accepted.** A correction the review also found:
  `mesh apps publish` already creates a **new** secret on every publish
  (`install/payload/bin/mesh:2038`), so a re-published app breaks saved links today. Only
  `mesh apps add` keeps the old one (`:2062-2063`). Keeping the old secret on publish is new
  behaviour, and the second slice names it.
- **App servers behind the daemon (`appproxy.ts`) are deferred. Accepted.** They would add the
  most new security-sensitive code in the whole proposal, for a need nobody has named yet.

### First slice: apps get their own port

- **Files:**
  - `install/payload/meshd/apps.ts`: a second listener for `/a/` on `MESHD_APPS_PORT`, bound to
    the same host as the daemon. Proposed default `8897`, which had no listener on this Mac on
    2026-09-27 (`lsof`). The fleet: unverified.
  - `install/payload/meshd/server.ts:1343-1348`: the daemon's own `/a/` route stops serving
    pages and only answers with a redirect to the app port.
  - `install/payload/bin/mesh`: the publish link (`:2040`) and the wireless-install mapping and
    status lines (`:1936`, `:1945`, `:1954`) use the app port.
  - Existing checks updated with your OK: `scripts/check-apps-serve.sh`,
    `scripts/check-apps-ota.sh`, `scripts/check-mesh-apps.sh` (the port in the link, and a
    redirect where a page used to be).
  - `docs/product/PRODUCT.md`: §5.4 states the real browser rule, and §3 notes the second port.
- **Proof:** a new `scripts/check-apps-origin.sh`. It boots a throwaway daemon and app port and
  publishes a fixture app. It asserts that the page is served on the app port, that the daemon
  port only redirects, that a request carrying the app port's origin is refused by the daemon,
  and that the web console at `/desktop` still works. It is run **once before the fix to show
  that it fails**. That run is the proof the hole is real, as the review demanded. Then the
  three edited checks, `sh scripts/check-package-mesh-install.sh`, and
  `./.claude/scripts/gates.sh fast` end GREEN.
- **Public-repo rule:** the new check describes the attack, so it is committed in the same
  change as the fix, never before.

### Second slice: 128-bit link secrets

- **Files:** `install/payload/bin/mesh:2038`, `:2063` (`randomHex(16)`; publish keeps the
  previous secret when one exists); `install/payload/meshd/apps.ts:90`, `:225` (accept 8 or 32
  hex characters, so old links still open); `mesh apps list` flags short keys.
- **Proof:** a new `scripts/check-apps-key-strength.sh` (a 32-hex key is minted; it serves 200;
  an old 8-hex fixture still serves 200; a wrong 32-hex key gets 404; publishing twice keeps the
  key). Existing assertions at `scripts/check-mesh-apps.sh:50,63` and
  `scripts/check-apps-ota.sh:58` widen to "8 or 32" with your OK
  (`docs/sdlc/references/nethera.md:167-170`).
- Both slices edit the same three check files. They can share **one attended session** with
  two separate commits.

<details>
<summary>If you want the mechanics</summary>

**Today's path**

- `install/payload/meshd/apps.ts:3-6` serves `~/.mesh/apps/<slug>/site/` at `/a/<slug>-<key>/`
  without the token, because Safari's "Add to Home Screen" cannot send one. The key in the path
  is the gate: 8 hex characters (`apps.ts:90`), minted by `randomHex(4)`
  (`install/payload/bin/mesh:2038`, `:2063`). No Content-Security-Policy is set
  (`grep -ci content-security install/payload/meshd/apps.ts` → 0).
- The route is mounted before the browser check (`server.ts:1343-1348`). The browser check
  deliberately lets the daemon's own origin through (`server.ts:1200-1206`), because the web
  console at `/desktop` posts to the daemon from a page the daemon served. On the Mac itself,
  that console works without a token through the local-program exemption.
- Wireless install puts `/a` behind Tailscale Serve on the machine's MagicDNS name
  (`install/payload/bin/mesh:1936-1946`). Through that path, requests carry a forward header,
  which removes the local exemption (`loopback-trust.ts:14-21`), and only `/a` is mapped. That
  path is not affected by the problem above.
- The step-by-step trace of the problem is intentionally not in this public file (see the note
  at the top). It goes into `scripts/check-apps-origin.sh` with the fix.

**Alternatives considered for the first slice**

| Option | Verdict | Why |
|---|---|---|
| Separate port for `/a/` | **Chosen** | A different port is a different origin to every browser, so the daemon's own-origin allowance can never apply to an app page. Old links keep working through a redirect |
| `Content-Security-Policy: sandbox` on app pages | Rejected | One line, but the page gets an opaque origin and loses the browser storage the app skill relies on (`SKILL.md:24-26`) |
| Refuse the local exemption for any request from a browser | Rejected | The web console at `/desktop` on the Mac depends on that exemption (its page reads `window.MESH_TOKEN`, which only the native app injects, `install/payload/meshd/desktop.html:55-58`). The documented "open `http://127.0.0.1:8899/desktop`" path (`docs/product/PRODUCT.md:86`) would stop working |
| Tell the daemon apart from app pages by the `Referer` header | Rejected | A page can rewrite its own path within its origin and can suppress the header |

**Later, only with a named need** (from the draft and `docs/sdlc/references/nethera.md:126-132`):
a plain-words reach label on every link ("your devices only", "this Wi-Fi", "anyone with the
link"); `mesh apps serve` for an app with its own backend, bound to 127.0.0.1 only; named,
shown-once, revocable write keys; the app's own secrets in a 0600 file outside the served
folder. Tailscale Funnel (public links) only after the 128-bit keys and only with your decision,
because it puts a third party in the traffic path.

</details>

### Questions for Arya

1. Do you ever open agent-built apps on the Mac itself, not just the phone? (yes/no) If yes,
   the first slice is urgent.
2. May the first slice edit `scripts/check-apps-serve.sh`, `scripts/check-apps-ota.sh` and
   `scripts/check-mesh-apps.sh`? (yes/no)
3. Port for apps: (a) `8897` · (b) another number you choose.
4. May the second slice widen the three 8-hex assertions to "8 or 32"? (yes/no)
5. Old 8-hex links: (a) keep working and get flagged in `mesh apps list` (recommended) ·
   (b) rotate automatically, which breaks them on phones that saved them.
6. Is there one real app you want that needs a server (for example shared data between two
   people)? (yes, name it / no). If no, app servers stay off the roadmap.
7. Who may open an app: (a) only your devices (today) · (b) anyone you send the link to, which
   means Tailscale Funnel and a third party in the path.
8. Should the daemon stop listening on plain home Wi-Fi by default and use Tailscale only
   (SEC-01)? (yes/no) It changes how pairing works on a machine without Tailscale.

---

## 4. Many machines, many agents (the core use)

### In plain words

Most of "connect my devices and run sessions across them" already works. The phone's Terminal
tab lists every machine's sessions (`iOS/TerminalView.swift`). The bell shows every agent
waiting on you across all machines, from one function (`Shared/Models.swift:735`). You can
search every past conversation on every machine and hand a conversation to another agent. You
can start an agent on any machine from the phone or with `mesh new … -H <machine>`.

The draft proposed new daemon code so that several agents on the same project each get their
own copy of it (a "git worktree"), the way Orca does. The review showed that the agent tools
already do this themselves: Claude Code has `-w/--worktree` and Codex has `--worktree`. The
daemon already accepts any command, and the phone's New Session sheet already takes a custom
command. So no new daemon code is needed. The first slice proves it with a check.

The bigger point: the thing you said is hurting is **"what to show where"**. That is a design
question, not an architecture one, so it moves to the design intent that the plans session is
writing with you.

### What the review changed

- **The daemon worktree module is cut. Accepted, on one condition this review adds.** Whether
  `claude -w` and `codex --worktree` behave well when started inside a background terminal
  session is **unverified**. For example, a trust prompt might stop them before the copy is
  made. So the first slice proves a path that needs no agent tool at all (plain `git worktree`
  in the start command). The agent-tool flags get one manual run with the output pasted. The
  draft's `worktree.ts` comes back only if both fail.
- **Your ask is about many machines, not collisions on one machine. Accepted.** Worktrees solve
  same-machine collisions, which is Orca's framing
  (`docs/sdlc/references/orca.md:11-16`). The phone toggle, the "finished, not looked at" marker
  and the honest host status (draft 4.2 to 4.4) move to the design intent.

### First slice: prove "one project, two agents, two copies" with no new daemon code

- **Files:** one new file, `scripts/check-agents-worktree.sh`. No product code changes, no
  `server.ts` change, so it can run in parallel with anything.
- **What it proves:** a throwaway daemon with a private tmux socket (as
  `scripts/check-approve-path.sh:36-43` does) and a temporary git repository. Two sessions are
  started through `POST /agents/new` with `cwd` set to the repository and a command of the form
  `git worktree add ../<repo>-<name> -b mesh/<name> && cd ../<repo>-<name> && exec sh`. The
  check asserts that `git worktree list` shows two distinct paths and that each session's
  current folder is its own copy. A session started without that command still behaves as
  before.
- **Also, once, by hand:** `mesh new a --cwd <repo> --cmd "claude -w a"` on this Mac and
  `mesh new b --cwd <repo> --cmd "codex --worktree" -H <machine>` on another, against the
  throwaway daemon (`AGENTS.md:52-58`), with the output pasted into a run record under
  `docs/factory/runs/`.
- **Proof:** `sh scripts/check-agents-worktree.sh` and `./.claude/scripts/gates.sh fast` end
  GREEN. When `git` or `tmux` is missing, the check prints `SKIP` with the reason, the same
  convention as `scripts/check-intent.sh:29`.

<details>
<summary>If you want the mechanics</summary>

**Evidence**

- `claude --help` on this Mac: `-w, --worktree [name]  Create a new git worktree for this
  session`. `codex --help`: `--worktree  Run the session in a new managed Git worktree`.
  Run 2026-09-27. Versions on the Pi and Jetson: unverified.
- `POST /agents/new` takes `cwd` and an arbitrary `cmd`, which is passed to the multiplexer as
  one shell string (`install/payload/meshd/server.ts:1506-1540`). So compound commands work.
  `mesh new` forwards `--cmd` and `--cwd` (`install/payload/bin/mesh:356-367`). The phone's New
  Session sheet sends a custom command when one is typed (`iOS/TerminalView.swift:291-296`).
- `mesh ls` lists one machine at a time (`install/payload/bin/mesh:315`). `mesh fleet` shows each
  machine's session count, memory and installed agent tools (`install/payload/bin/mesh:576`).

**Why the plain-git path is the one the check uses:** it works with every agent tool,
including ones with no worktree flag, and it tests only our daemon and `git`, which CI has. The
agent flags are third-party behaviour, and a permanent check should not depend on a logged-in
agent tool.

**Moved to the design intent** (from the draft and `docs/sdlc/references/orca.md:138-141`):
a "separate copy" option in the phone's New Session sheet (it would edit
`Shared/MeshClient.swift`, a one-agent-at-a-time file); a "finished, not looked at" marker; and
separate messages for "token rejected" versus "cannot reach the machine", which today share one
`error ?? "offline"` string in `Shared/Models.swift`.

**Not needed:** the daemon `worktree.ts` module, the `worktree` capability, and
`mesh new --worktree`.

</details>

### Questions for Arya

1. May the worktree check be added? (yes/no)
2. When you start a second agent on a project that already has one running, should it get its
   own copy: (a) always · (b) only when you tick a box · (c) never, you coordinate by hand.
3. Do you keep the same projects on several machines (for example, this repo on both the Mac
   and the Jetson)? (yes/no) If no, "same task on two machines" first needs a way to get the
   project onto the second machine.
4. Would a one-line fleet-wide list on the command line help (`mesh ls --all`: every session on
   every machine)? (yes/no)
5. Should "what to show where" on the phone and watch be the first question of your design
   intent? (yes/no)

---

## Things found while writing (not part of the four topics)

- **The spec and the code disagree about browser requests.** `docs/product/PRODUCT.md:185-187`
  versus `install/payload/meshd/server.ts:1200-1206`. Fixed inside topic 3's first slice.
- **`CONSTRAINTS.md` is missing.** `docs/product/PRODUCT.md:460` calls it "the floor", and no
  such file exists in the tree.
- **VNC conflict.** `docs/adr-2026-09-22-platform-shape.md` §2 proposes an opt-in
  `mesh vnc enable`; `ROADMAP.md:116` lists VNC as a non-goal. One of them has to change.
- **This document's own risk.** It names the files involved in an unfixed problem in a public
  repository. It stays at outcome level on purpose. If you would rather it stayed off GitHub
  until topic 3's first slice lands, keep it uncommitted or on a private branch.

## Review trail

- Draft: architecture draft of 2026-09-27 (the session's working notes, not in the repo).
- Sceptical review: same session's working notes. Its verdicts are answered inline above.
- Citation corrections: the draft cited lines in `docs/sdlc/references/openmuse.md` and
  `docs/sdlc/references/nethera.md` that no longer exist after those files were rewritten. Every
  reference citation in this document was re-read against the files at `5710d51`.
