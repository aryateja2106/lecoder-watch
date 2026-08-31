# Local Inference

Requirements for running a local model server on a host machine behind the daemon.
These extend, and never override, the agent-brain requirements in
[local-brain-and-harness](../../../local-brain-and-harness/specs/agent-brain/spec.md):
persistent sessions, brain-on-the-machine, endpoint swappability, and honest claims
all still hold.

## ADDED Requirements

### Requirement: The daemon reports the local brain truthfully

The daemon SHALL expose whether a local model server is reachable and which model it
has loaded, as a capability-gated route, and clients SHALL treat the absence of the
capability as "unknown", never as "no model" or as an error.

The fleet runs released payloads, not this repo (AGENTS.md rule 6): an old daemon
answers 200 with the old shape, so clients must gate on the capability string.

#### Scenario: A local server is running
- **WHEN** a client asks the daemon about the local brain while a model server is
  reachable on the machine
- **THEN** the daemon SHALL report it reachable and name the loaded model
- **AND** the client SHALL show that model as the one answering

#### Scenario: The server is down or was never installed
- **WHEN** no local model server responds on the configured endpoint
- **THEN** the daemon SHALL answer success with "not reachable" rather than an
  HTTP error, so a missing brain is a state, not a fault

#### Scenario: An old daemon in the fleet
- **WHEN** a client talks to a daemon whose capability list lacks the brain entry
- **THEN** the client SHALL show nothing about local models on that machine, and
  SHALL NOT infer anything from probing other routes

### Requirement: The model server is never exposed beyond the daemon's auth

The local model server SHALL bind loopback only, and any access from another machine
SHALL pass through the daemon's existing bearer-token auth. The server's own
unauthenticated surface SHALL NOT be reachable from the network.

The server we front has no auth or TLS of its own, by its own design; the daemon is
the boundary that already solves this for every other capability.

#### Scenario: A request from the phone
- **WHEN** a client on another device uses the local brain
- **THEN** the request SHALL carry the daemon's bearer token and be rejected
  without it, exactly like every other authed route

#### Scenario: A scan from the local network
- **WHEN** another machine on the network connects to the model server's port
  directly
- **THEN** the connection SHALL be refused, because the server is bound to loopback

### Requirement: Fit is proven before serving starts

Before a model is installed or loaded, the machine's free disk and memory SHALL be
checked against that model's stated requirements, and on a shortfall the operation
SHALL refuse up front, stating both numbers. A model install SHALL be resumable and
SHALL NOT require transient space beyond the model's final size plus a bounded
scratch allowance.

Both reference engines converged on plan-then-refuse: a daemon must never OOM or
fill the disk an hour into a long-running task.

#### Scenario: Not enough disk to install
- **WHEN** the user picks a model whose download exceeds free disk
- **THEN** the install SHALL refuse before transferring anything, showing required
  vs available

#### Scenario: An interrupted install
- **WHEN** a model download is interrupted partway
- **THEN** re-running the install SHALL resume rather than restart, and the
  partial state SHALL never be served

#### Scenario: Not enough memory to load
- **WHEN** the server cannot fit the model's working set in available memory
- **THEN** it SHALL fail to start with both numbers stated, and the daemon SHALL
  report the brain not reachable — it SHALL NOT start and then die mid-task

### Requirement: One conversation at a time, without corruption

The local brain SHALL serve one generation at a time. When a second agent turn
arrives while one is running, it SHALL queue and then complete correctly; it SHALL
NOT corrupt either conversation, and long-running work SHALL NOT be starved
silently.

The server retains a single cached conversation prefix; interleaving two
conversations is legal but forfeits the cache, so the driving layer serializes
turns and sends complete history each turn.

#### Scenario: Two sessions want the brain
- **WHEN** a second session submits a turn while the first is generating
- **THEN** the second SHALL wait its turn and then receive a correct, complete
  answer
- **AND** the first session's output SHALL be unaffected

#### Scenario: The queue is full
- **WHEN** more turns are waiting than the server accepts
- **THEN** the excess turn SHALL be rejected with a clear busy signal the client
  can show, not dropped or hung

### Requirement: Local model lifecycle is one command in, one command out

Installing, serving, and removing a local model SHALL be a single user action each,
with the model chosen from a short named list that states its disk and memory cost
up front. Uninstall SHALL remove the model weights, the server, and its service
registration completely.

Target user: non-technical (the product brief's deciding assumption). Anyone this
requires to edit a config file or know a port number fails it.

#### Scenario: Installing the first model
- **WHEN** the user chooses a model from the offered list
- **THEN** one action SHALL download, verify, and start serving it, and the daemon
  SHALL report it as the local brain when it is ready

#### Scenario: Removing it all
- **WHEN** the user uninstalls
- **THEN** weights, server process, and service registration SHALL all be gone,
  and the daemon SHALL report no local brain — with the machine otherwise exactly
  as it was
