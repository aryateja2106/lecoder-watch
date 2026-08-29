# Agent Brain

The requirements that hold whichever harness is adopted and whichever model runs.

## ADDED Requirements

### Requirement: The shell layer stays a persistent session

Any agent runtime added to this product SHALL execute through the existing persistent
multiplexer sessions, and SHALL NOT replace them with per-command process spawning.

This is not a preference. Stateless subprocess execution cannot preserve a working
directory, cannot answer an interactive prompt, and cannot host a long-running process —
which is why every comparable project that started there has since moved away from it.

#### Scenario: An adopted harness reaches the machine
- **WHEN** an agent runtime executes a command on a host
- **THEN** it SHALL do so through a session whose state persists across calls
- **AND** a working directory set by one command SHALL still apply to the next

#### Scenario: A long-running process
- **WHEN** an agent starts a process that outlives the call that started it
- **THEN** the process SHALL keep running
- **AND** its output SHALL remain readable from the phone and the watch

### Requirement: The brain runs on the machine, not the phone

The agent loop SHALL run on the host machine, so that work continues while the phone is
asleep, out of range, or closed.

A phone-hosted loop would stop the moment the screen locked, which contradicts the entire
premise of watching an agent from a wrist.

#### Scenario: The phone goes away mid-task
- **WHEN** an agent is working and the phone locks or loses the network
- **THEN** the agent SHALL continue
- **AND** on reconnecting, the client SHALL show what happened in the meantime

### Requirement: The model is swappable, and which one is running is visible

The runtime SHALL accept any OpenAI-compatible endpoint, local or hosted, and the client
SHALL show which model is answering.

A user who is told the product is local-first must be able to see when it is not.

#### Scenario: Pointing at a local model
- **WHEN** the user configures a local endpoint
- **THEN** the agent loop SHALL use it with no code change

#### Scenario: Being honest about the brain
- **WHEN** a session is driven by a hosted frontier model
- **THEN** the client SHALL say so rather than implying the work stayed on the machine

### Requirement: Claims about local capability match what is running

Documentation and marketing SHALL NOT describe the product as locally-powered while its
default configuration sends work to a hosted API.

#### Scenario: Describing the product
- **WHEN** the README or the landing page describes where inference happens
- **THEN** it SHALL state the default accurately, and describe local models as supported
  rather than as the default, until that changes
