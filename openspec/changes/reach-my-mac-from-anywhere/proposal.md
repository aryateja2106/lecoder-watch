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

## Verified platform constraints that shrink the option space

Researched August 2026. These are not preferences; they eliminate designs.

- **The watch can only speak HTTP(S) via `URLSessionDataTask`.** Apple's TN3135 documents
  that watchOS blocks low-level networking outright — Network framework, BSD sockets,
  `URLSessionStreamTask`, `URLSessionWebSocketTask` and every Bonjour API — outside
  audio-streaming, CallKit VoIP and a tvOS app-service case. **This rules out WireGuard,
  Noise, QUIC and WebRTC running natively on the wrist**, and with them any ICE/TURN design,
  which Bun cannot speak either. A plain TCP relay is therefore both cheaper and the only
  thing that works.
- **There is no Apple back door.** `includePeerToPeer` enables link technologies (AWDL,
  peer-to-peer Wi-Fi, Bluetooth) only; Multipeer Connectivity is Wi-Fi and Bluetooth PAN;
  `.local` is link-local by RFC 6762. None crosses a NAT. There is no public API by which
  two devices on one iCloud account find each other off-LAN — Apple killed Back to My Mac in
  Mojave and shut it off entirely on 2019-07-01.
- **ATS on iOS 17+ / macOS 14+ no longer permits connections to raw IP addresses by
  default.** That is why the app currently carries a blanket `NSAllowsArbitraryLoads`, which
  is itself an App Review risk and indefensible for a daemon that executes shell commands.
- **VPN and cellular interfaces are not "local networks"** (TN3179), so a tailnet address
  never triggers the local-network prompt while a LAN IP does. Also: macOS 15's auto-allow
  covers launchd **daemons** and root, but explicitly **not** launchd **agents** — which is
  exactly what `install/install.sh` creates in `~/Library/LaunchAgents`.
- **Do not build the default on Tailscale.** Its free Personal plan is explicitly
  non-commercial, so users would be in violation the day this charges money.

## The honest security verdict on what ships today

`meshd` is a Bun server on `0.0.0.0:8899` with a bearer token, no TLS, exposing endpoints
that execute shell commands. Stated plainly: **a remote-code-execution box with a password
sent in the clear.**

On WPA2-PSK home Wi-Fi, anyone who knows the network password can decrypt a captured session
and lift the token. On *any* network including WPA3, ARP or DNS spoofing yields the token
without sniffing at all, because there is no server authentication whatsoever — the client
has no way to tell the real daemon from an impostor.

**The minimum defensible fix is not Noise or WireGuard.** It is per-install **self-signed TLS
with the SPKI fingerprint carried in the pairing payload and pinned** in the app's
`URLSession` trust delegate. That buys confidentiality, server authentication and replay
protection; it works on watchOS because data tasks are supported; it lets the blanket
`NSAllowsArbitraryLoads` be narrowed to `NSAllowsLocalNetworking`; and it keeps us inside
Apple's *exempt* encryption category, so `ITSAppUsesNonExemptEncryption` stays `false` and no
annual self-classification report is triggered — which rolling our own cipher would.

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

**Ship A immediately, then B — and do the TLS work before either is exposed off-LAN.**

Concretely, the shape the evidence points at:

- **Default:** LAN-direct over **pinned TLS**, discovered by Bonjour.
- **Off-LAN:** one small **SniTun-style plain TCP relay** that routes by device key and
  forwards opaque bytes it cannot decrypt. This is precisely the Nabu Casa architecture,
  whose ~$6.50/month retail price is a useful anchor for what this is worth. For 10–15 users
  the hosting is a rounding error — on the order of $4–6/month on a small VPS.
  A plain TCP relay, not TURN: neither watchOS nor Bun can speak WebRTC/ICE.
- **Fallback:** **bring your own network.** If the user already runs Tailscale, NetBird,
  ZeroTier, WireGuard or a port-forward, the app just takes the address and no relay is
  involved. That honours the no-forced-vendor constraint without asking a non-technical user
  to decide anything.

Every incumbent does a version of this: Screens Connect adds UPnP/NAT-PMP with a broker
holding name→public IP:port; Jump Desktop, Chrome Remote Desktop, TeamViewer, AnyDesk and
RustDesk all use a broker for device-ID→endpoint plus a relay fallback that cannot decrypt.
Syncthing's documentation is refreshingly blunt that its discovery server "can deduce which
devices are connected to each other" — that is the privacy cost, and it should be stated in
those terms rather than buried.

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
