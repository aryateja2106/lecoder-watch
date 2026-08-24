# Connectivity

These requirements hold whichever option the owner picks, so they can be implemented before
the decision is made.

## ADDED Requirements

### Requirement: The product states its actual reach

The app and its documentation SHALL describe honestly where the product does and does not
work, and SHALL NOT imply reach it does not have.

A user who installs this, leaves the house and taps the app must understand what they are
seeing within seconds, without concluding it is broken.

#### Scenario: A machine is unreachable because the user left the network
- **WHEN** no paired machine can be reached and the device is not on a network that has
  ever reached one
- **THEN** the app SHALL say that machines are reachable at home or over the user's own VPN
- **AND** it SHALL NOT present this as an error or a fault with the machine

#### Scenario: Documentation does not overstate
- **WHEN** the README describes what the product does
- **THEN** it SHALL state that working from outside the user's own network requires a VPN
  they already run, or a rendezvous service, and that neither is bundled today

### Requirement: No connectivity vendor is required

The product SHALL work over any network path the user already has — LAN, Tailscale,
NetBird, WireGuard, or any other — and SHALL NOT require, bundle, or hard-code a named
provider.

#### Scenario: A user with no VPN
- **WHEN** a user has no VPN at all and is on the same network as the machine
- **THEN** pairing and every feature SHALL work

#### Scenario: A user with a VPN we have never heard of
- **WHEN** a machine is reachable at an address only that VPN routes
- **THEN** pairing SHALL accept that address and every feature SHALL work

### Requirement: Plaintext credentials never leave a trusted network

The daemon SHALL NOT be reachable from the public internet while it authenticates with a
bearer token over unencrypted HTTP.

The token is replayable by anyone on the path. This is a defensible trade on a home
network and indefensible across the internet, so it gates any relay work.

#### Scenario: A relay or tunnel is introduced
- **WHEN** any mechanism is added that makes a daemon reachable from outside the user's
  own network
- **THEN** transport encryption SHALL be in place first
- **AND** the client SHALL trust exactly one certificate for exactly one machine, pinned
  at pairing time

#### Scenario: A token is weak or shared
- **WHEN** a paired host presents a token that is not machine-minted and high-entropy
- **THEN** `mesh doctor` SHALL report it as failing and name the host
