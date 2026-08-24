# Reach my Mac from anywhere

## Why

The product promises "use your Mac from your wrist". Today that is only true on the user's
own network, or over a VPN they already run and configured themselves.

The target user is explicitly non-technical: *"i want them to be able to copy paste a
command and run it and be able to securely connect."* Those two facts do not currently
meet. Someone who installs this, walks out of the house, and taps the app sees nothing —
and there is no instruction we can give them that fixes it, because the fix is a VPN they
were promised they would not need.

This is the single decision that most determines whether the first cohort of users keeps
the app. Every reported bug is downstream of it in importance.

## The constraint nobody can engineer around

Reaching a machine behind a home NAT, from a phone on cellular, requires **some** third
party to introduce the two endpoints. There is no exception. Every product that does this
works the same way: attempt a direct peer-to-peer connection via hole punching, and fall
back to an encrypted relay when the NAT refuses.

- **Jump Desktop** uses WebRTC, trying direct UDP first (ports 35384–35484) and falling
  back to global relays on TCP/UDP 80 and 443. End-to-end encrypted with DTLS/SRTP, so the
  relay cannot decrypt. ([support.jumpdesktop.com](https://support.jumpdesktop.com/hc/en-us/articles/16970337116045-Connectivity-options-in-Jump-Desktop-for-Teams))
- **Tailscale** uses a coordination server plus DERP relays, the same shape.
- **Screens**, **TeamViewer**, **Chrome Remote Desktop**: all broker-plus-relay.

So **"no servers of ours" and "works from anywhere with zero setup" are mutually
exclusive.** Continuing to claim both is the thing to stop doing, whichever option is
chosen. Note that the nearest competitor, Moshi, does not solve this either — it tells the
user to bring Tailscale.

## Non-goals

- Building our own VPN, or bundling one.
- Requiring Tailscale, NetBird, or any named vendor. The user explicitly refuses to force
  one, and a user who already has a VPN must keep working exactly as today.
- Storing user data, screens, keystrokes or terminal output on any server we run.
- Solving this before the reported wrist bugs are confirmed fixed on a real device.

## Options

### A. Stay local-only, and say so clearly

Ship nothing. Make the README, the app's empty state, and the pairing flow explain in plain
words that this works at home or over your own VPN, and detect + guide the common VPNs the
user may already have.

- **Cost:** none. **Honest:** yes. **Keeps the promise:** no.
- Best if the first cohort is mostly at a desk, or already runs Tailscale.

### B. Optional, self-hostable rendezvous + relay (recommended)

A small service that does two things and holds nothing: introduce two endpoints (exchange
ICE candidates), and relay encrypted bytes when hole punching fails. Run one instance for
users who want it; publish it so anyone can run their own, which preserves the local-first
claim as a *default*, not a lie.

- **Cost:** one small always-on service, plus relayed bandwidth for the minority of NATs
  that refuse direct connections. Relay traffic is the expensive case, so measure the
  direct-connection hit rate before sizing anything.
- **Keeps the promise:** yes, for the user who opts in.
- **Requires:** deciding what the broker learns (at minimum: which endpoints want to talk,
  and when). That is the privacy cost and it must be stated, not buried.

### C. Piggyback on Apple

Investigate whether two devices on the same iCloud account can find each other off-LAN via
Network.framework. **Unverified** — must be confirmed against Apple's documentation before
being treated as an option, and it would not help Linux hosts at all.

## Recommendation

**B, with A shipped first.** A is a documentation change that can land today and stops the
product overstating itself. B is the real answer and should be designed only after the
security work below, because exposing a daemon that speaks plaintext HTTP to a relay would
be indefensible.

## Blocking prerequisite: the transport

`meshd` currently binds `0.0.0.0:8899` and authenticates with a **bearer token over plain
HTTP**. On a home network that is a defensible trade. Reachable from the internet through a
relay it is not: the token is replayable by anyone on the path.

Any work on B must be preceded by transport security — at minimum TLS with a pinned
self-signed certificate minted during pairing, so the phone trusts exactly one certificate
for exactly one machine and nothing else changes about the pairing UX.

A separate, immediate finding: at least one paired host in the current fleet is still using
the literal token `testtoken`. Rotate before any of this.

## Open questions for the owner

1. Are you willing to run one small always-on service? If not, the answer is A and the
   promise changes.
2. If yes: does it relay bytes, or only introduce endpoints and let direct connections fail
   when NAT refuses? Introduce-only is far cheaper and works for most home NATs.
3. What is the acceptable privacy statement for the broker?
4. Does this gate the App Store submission, or ship after?
