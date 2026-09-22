## ADDED Requirements

### Requirement: An account is identity only

A website account SHALL store only identity: email, username, device labels, public keys, and sealed blobs. The account MUST be a different database from the heartbeat project. The account SHALL NOT be a copy of `~/.mesh`.

The heartbeat project `zmisjteztezaqfflwbgf` remains the telemetry database. An agent MUST NOT apply identity SQL to the telemetry project.

#### Scenario: A person creates an account

- **WHEN** a person creates a website account with a username, an email, and a password
- **THEN** the account record holds that identity and nothing that can open a machine
- **AND** the stored device fields are a user-typed label, a platform, and a public key
- **AND** the stored sync payload is sealed ciphertext

#### Scenario: Identity SQL is pointed at the heartbeat project

- **WHEN** an agent is about to run the identity migration against project `zmisjteztezaqfflwbgf`
- **THEN** the agent MUST stop before any statement runs
- **AND** the heartbeat rows stay insert-only telemetry, unlinked to any account

#### Scenario: A column would hold a machine secret

- **WHEN** a proposed account column, log line, or support export contains a mesh token, pairing code, host list, tailnet address, LAN address, public IP, MAC address, APNs token, terminal text, or the device private key
- **THEN** that write is a failed account design
- **AND** the agent MUST NOT add the column or the log

### Requirement: Install and pairing work logged out

Installing the daemon and pairing a phone with the 8-character code SHALL work when nobody is signed in. An account MUST NOT be required to install. Until a later native change lands, signing in on the website SHALL NOT move a mesh token, a tailnet address, or a host list onto a second device.

#### Scenario: A person installs with no account

- **WHEN** a person runs the homepage install command and pairs a phone with the 8-character code, and they have never created an account
- **THEN** the daemon installs and the phone pairs
- **AND** the website is not on that path

#### Scenario: Website sign-in is treated as device sync

- **WHEN** a person signs in on the website and expects the phone to receive the machines from another device
- **THEN** the account pages state that the phone is not synced
- **AND** no mesh token, tailnet address, or host list is copied to the second device

### Requirement: The website does not render machine IPs

The website SHALL NOT render a machine IP, hostname, port, or tailnet address, including for the signed-in owner. A device row on the website shows a label. The empty state says pairing still happens on the machine.

#### Scenario: Devices are listed for the signed-in owner

- **WHEN** a signed-in person opens the website devices view
- **THEN** each row shows the user-typed label
- **AND** the page shows no IP address

#### Scenario: A bad client uploaded an address

- **WHEN** a client attempts to store an IP on the account
- **THEN** the schema has nowhere to put it
- **AND** the website does not render an IP

### Requirement: Password reset does not grant mailbox plaintext

Resetting a password SHALL set a new password and SHALL NOT grant mailbox plaintext. The reset flow MUST NOT read or write devices or the mailbox.

#### Scenario: A person sets a new password

- **WHEN** a person completes password reset from the recovery email
- **THEN** the next sign-in uses the new password
- **AND** mailbox ciphertext stays sealed
- **AND** the reset response contains no device secret and no mailbox plaintext

#### Scenario: Reset is used to recover a machine

- **WHEN** a person resets a forgotten password and then asks the account for the mesh token or the host list
- **THEN** the account still has no copy of those secrets
- **AND** the machines stay reachable only by pairing on the device that already holds them

### Requirement: The device private key stays on the machine

The device private key SHALL stay on the machine that generated it. The account database and the website MUST NOT receive that private key. The uploaded device material is the public key and the sealed blob.

#### Scenario: A device registers

- **WHEN** a device is registered to an account
- **THEN** the account stores the public key and the user-typed label
- **AND** the private key remains in the Apple Keychain or in `~/.mesh/device.key` with mode 600

#### Scenario: An upload includes the private key

- **WHEN** a client attempts to upload the device private key
- **THEN** that upload is rejected as an account write
- **AND** the private key is not stored in the account database, in a log, or in git
