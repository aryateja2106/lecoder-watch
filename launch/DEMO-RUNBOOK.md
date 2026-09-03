# 90–120 second launch demo runbook

Goal: prove one real attention handoff — an agent on an owned machine asks a
question, the person answers from a physical Apple device, and the same session
continues. Record current product behavior only. Do not show pairing codes,
tokens, personal files, or a simulated notification as product proof.

## Sterile setup

Use a dedicated demo macOS account and dedicated or freshly isolated iPhone/Watch
pair. The account must contain no personal browser profile, messages, repositories,
SSH material, or existing `~/.mesh` fleet. Name real demo machines before pairing:
`Atlas-Studio` and, only if a second machine is genuinely available, `Orbit-Lab`.
There is no supported daemon display-name override; crop the host name or omit the
shot if the real device cannot carry a publishable name.

Use an already authenticated **demo** Claude Code account. Do not copy, display, or
inspect credentials. Install the current candidate build and run `mesh hooks status`.
Run `mesh hooks install` only inside the dedicated demo account if Notification and
Stop are not installed.

From the current repository root, prepare one disposable project and a daemon on a
spare port. Run setup outside the recording window:

```sh
product_root="$(git rev-parse --show-toplevel)"
demo_root="$(mktemp -d -t lesearch-mesh-demo)"
demo_repo="$demo_root/OrbitNotes"
demo_port=18898
demo_token="$(openssl rand -hex 32)"

mkdir "$demo_repo"
cd "$demo_repo"
git init -q
git config user.name "Demo User"
git config user.email "demo@example.invalid"
printf '# Orbit Notes\n\nRelease status: undecided.\n' > README.md
git add README.md
git commit -qm 'chore: seed demo'

export MESHD_PORT="$demo_port"
export MESHD_TOKEN="$demo_token"
export MESHD_EVENTS_PATH="$demo_root/agent-events.jsonl"
export MESHD_KB_PATH="$demo_root/kb.sqlite"
export MESHD_TELEMETRY=off
bun run "$product_root/install/payload/meshd/server.ts" >"$demo_root/meshd.log" 2>&1 &
demo_pid=$!
curl -fsS "http://127.0.0.1:$demo_port/health" >/dev/null && echo "health ok"
```

Use a trusted private LAN. Pair from a non-recorded terminal with
`mesh pair --port "$demo_port"`; never capture its QR, address, or one-time code.
The product has no hosted relay or account, so off-network access requires an
existing VPN and must not be implied.

Start the real session from the same exported environment:

```sh
mesh new release-check --cmd claude --cwd "$demo_repo" --task 'Read README.md. Before editing, ask exactly one question: should the release status be "Ready" or "Queued"? After I answer, change only that line, run git diff --check, and report the result.'
```

This is a real bounded task in a fictional repository. Do not paste prepared output
into the terminal or post a synthetic `/events` payload. If the hook does not produce
an attention state, use the fallback below.

## 112-second storyboard

| Time | Picture | Evidence the shot must contain |
| --- | --- | --- |
| 0–8s | Physical Mac, agent session running | `OrbitNotes` and `release-check`; no personal prompt, path, or account name |
| 8–24s | Agent reaches its real Ready/Queued question | The same session name and legible question; hold long enough to read |
| 24–43s | Physical Watch receives/opens the attention state | Real notification or current in-app Needs You state; finger interaction stays in frame |
| 43–60s | User reviews and sends **Ready** | Visible confirmation before dispatch; one response, no destructive prompt |
| 60–79s | Physical iPhone opens the same live terminal | Agent updates the real file and reports `git diff --check`; continuity is obvious |
| 79–92s | Machine list or supported remote control | Show a second machine only if it is live; show remote control only when `/health` advertises the capability and permissions work |
| 92–104s | Simple local-first card | “Your machine. Reachable LAN or your existing VPN. No LeSearch relay.” |
| 104–112s | Logo and one beta CTA | Use the exact launch CTA; no invented availability date or pricing |

Keep the question, session name, repository, and answer identical across every
surface. Record the Mac, iPhone, and Watch in one rehearsal before shooting inserts;
continuity matters more than visual polish.

## Evidence and human verification

Before calling the cut a product demo, a person must verify on the physical devices:

- Watch: the alert reaches the intended watch; opens the correct machine/session;
  question text is readable; Crown scrolling works; review occurs before send; the
  answer is sent once; the session visibly leaves its waiting state.
- iPhone: the same session is current rather than cached; terminal output advances
  after the Watch answer; typing requires confirmation; reconnect/stale states are
  honest; screen/trackpad controls work only on a host advertising those capabilities.
- Network: the phone reaches the spare-port daemon on the trusted LAN or an existing
  VPN. Do not describe this as access “from anywhere” without that boundary.
- Mac: `README.md` contains the selected status and `git diff --check` succeeds after
  the response. Keep that result as internal capture evidence.

Simulator footage can help frame an insert, but it cannot prove physical notifications,
haptics, microphone/dictation, Crown behavior, WatchConnectivity, or wrist legibility.

## Redaction pass

Reject or crop any frame containing:

- a bearer token, pairing QR/code, APNs material, login/auth code, recovery key, or
  contents of `~/.mesh`, `~/.ssh`, keychains, environment files, or credential stores;
- a real hostname, IP address, Wi-Fi name, username, home-directory path, Git remote,
  email, project, branch, browser tab, notification, contact, calendar item, or clipboard;
- unrelated terminal history, agent transcripts, usage/billing details, menu-bar apps,
  desktop files, VNC content, or another machine reflected in glass;
- stale status, a capability unavailable on that host, generated UI, or a reference
  image presented as the current product.

Treat the existing 133.7-second reference recording and all `Reference-images/` files
as private source material until reviewed frame by frame. Prefer new captures.

## Honest fallbacks

- **Hook or APNs fails:** show the real Needs You state after an in-app refresh and say
  “monitor and respond.” Remove notification/haptic claims; never post a fake event.
- **Physical Watch cannot complete the loop:** publish an iPhone-only product demo or
  reshoot. Do not use a simulator to substantiate “from your wrist.”
- **Second machine is unavailable:** omit the fleet beat. One real machine is stronger
  than a fabricated second host.
- **Screen/trackpad is unsupported or permissions fail:** show the text terminal. Do
  not use an old VNC screenshot as proof.
- **Agent output diverges:** restart the disposable repository and capture another real
  run. Do not splice a question and answer from different sessions.

## Shoot and finish

Capture only six sources: Mac screen, physical Watch interaction, physical iPhone screen,
one hardware establishing shot, optional real second-machine shot, and the logo/CTA card.
Use a clean 16:9, 1080p master with hard cuts, restrained device framing, readable
captions, and one neutral sound bed or none. Avoid 3D mockups, fake cursor motion, and
extra UI animation. Keep the unredacted sources private; export and review one sanitized
master.

After capture, stop only the daemon started above with `kill "$demo_pid"`, then run
`unset MESHD_PORT MESHD_TOKEN MESHD_EVENTS_PATH MESHD_KB_PATH MESHD_TELEMETRY`.
Do not delete the demo repository until the final continuity and redaction review passes.
