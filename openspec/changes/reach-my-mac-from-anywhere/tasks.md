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

## If B — transport first, always

- [ ] **TLS with a certificate pinned at pairing.** The daemon mints a self-signed
      certificate; pairing hands its fingerprint to the phone alongside the token; the
      client trusts that one certificate for that one machine.
      *Verify by running: a `curl` without the pin is refused, the app with the pin
      succeeds, and a machine re-paired after a certificate change is refused until
      re-paired.*
- [ ] **Reject plaintext once TLS exists**, except on loopback.
      *Verify by running: plain HTTP from another host is refused; `127.0.0.1` still works
      for the menu-bar app.*

## If B — then the service

- [ ] **Rendezvous only, first.** Exchange endpoint candidates; let direct connections
      succeed or fail. No relaying yet — this is most of the value for a fraction of the
      cost.
      *Verify by running: a phone on cellular reaches a Mac behind a home NAT with no VPN.*
- [ ] **Publish it so it can be self-hosted**, which is what keeps "local-first" true as a
      default rather than a slogan.
      *Verify by running: point a second install at a self-hosted instance and pair.*
- [ ] **Relay fallback**, only if the measured direct-connection rate justifies it.
      *Verify by running: force hole-punching to fail and confirm the session still works
      and that the relay cannot read the bytes.*
- [ ] **State plainly what the broker learns**, in the app and the README.
