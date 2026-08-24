# Tasks

Ordered. Everything before the decision point is safe to do now and useful whichever way
the decision goes.

## Before the decision

- [x] **Say what is true in the README.** A "what is, and is not, true yet" section stating
      that off-network with no VPN does not work, and why. *Done — verify by reading
      README.md.*
- [ ] **Rotate the weak token.** At least one paired host is using the literal string
      `testtoken`. *Verify by running: `mesh doctor -H pi` and confirming the token check
      passes, then `mesh hosts` still reaches it.*
- [ ] **Make `mesh doctor` fail a weak token.** Today it only checks that a token is set.
      Fail it when the token is short, or equal to any known placeholder.
      *Verify by running: point `MESH_HOME` at a fixture whose token is `testtoken` and
      confirm `mesh doctor` exits non-zero and names the host.*
- [ ] **Say it in the app, not only the README.** The empty/unreachable state should
      distinguish "this machine is off" from "you are not on a network that reaches it".
      *Verify on device: pair a machine, join cellular-only, confirm the wording. Needs
      Arya's iPhone — an agent cannot leave the network.*
- [ ] **Measure the real hit rate before designing a relay.** Instrument nothing on users;
      just test from a phone on cellular against a home NAT and record whether a direct
      UDP path can be established at all. *Verify by running the probe and recording the
      result in this file.*

## Decision point

- [ ] **Owner decides: A (document and stop) or B (rendezvous service).** See proposal.md,
      "Open questions for the owner". Nothing below starts until this is answered.

## Transport first, always — this is needed even for option A

Today's daemon is a shell-executing endpoint with a replayable password in the clear and no
server authentication at all. This is worth doing whether or not a relay is ever built.

- [ ] **Check Bun's TLS server is solid** for long-lived connections at the pinned version,
      before designing anything on top of it. This was explicitly NOT verified in research.
      *Verify by running: `Bun.serve` with a `tls` option and a self-signed cert, hit from a
      real device, held open for an hour.*
- [ ] **Mint a self-signed certificate per install** and carry its **SPKI fingerprint** in
      the pairing payload.
      *Verify by running: pair a machine and confirm the fingerprint arrives with the token.*
- [ ] **Pin it in the client's `URLSession` trust delegate.**
      *Verify by running: a `curl` without the pin is refused; the app succeeds; a machine
      whose certificate changed is refused until re-paired. Must be tested on the WATCH too
      — data tasks are all it has.*
- [ ] **Narrow ATS**: drop the blanket `NSAllowsArbitraryLoads` to `NSAllowsLocalNetworking`.
      Note ATS on iOS 17+ refuses raw IP addresses by default, so this interacts with how
      hosts are addressed — resolve that before flipping it.
      *Verify by running: the app still reaches a paired machine on both iOS and watchOS.*
- [ ] **Reject plaintext once TLS exists**, except on loopback for the menu-bar app.
      *Verify by running: plain HTTP from another host is refused; `127.0.0.1` still works.*
- [ ] **Confirm `ITSAppUsesNonExemptEncryption` can stay `false`.** Using OS TLS keeps us
      exempt; rolling our own cipher would not. Do not invent a handshake.

## If B — then the service

Note: hole-punching plus ICE/TURN is **not available to us** — watchOS blocks the low-level
networking it needs and Bun cannot speak WebRTC. A plain TCP relay is the design.

- [ ] **A SniTun-style TCP relay** that routes by device key and forwards opaque bytes it
      cannot decrypt. Same shape as Nabu Casa's. Budget ~$4–6/month for this cohort.
      *Verify by running: a phone on cellular reaches a Mac behind a home NAT with no VPN,
      and a packet capture at the relay shows only ciphertext.*
- [ ] **Publish it so it can be self-hosted**, which is what keeps "local-first" true as a
      default rather than a slogan.
      *Verify by running: point a second install at a self-hosted instance and pair.*
- [ ] **Relay fallback**, only if the measured direct-connection rate justifies it.
      *Verify by running: force hole-punching to fail and confirm the session still works
      and that the relay cannot read the bytes.*
- [ ] **State plainly what the broker learns**, in the app and the README.
