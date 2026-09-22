## Why

Shipping an account that looks like a copy of the mesh would be a broken launch. The owner's words for the boundary are: "The account is identity. It is not a copy of `~/.mesh`." and "Pretending the phone is synced is a broken launch."

The person this is for can type an email, a username, and a password. They do not configure SSH keys, port forwarding, a VPN, or a database. Ritik is the person who confirms the new Supabase project. An executing agent does not stand in for either of them.

## What Changes

- Add a contract other agents can execute for the website account, without a second implementation of work that already exists on draft pull requests.
- State that an account is identity only: email, username, device labels, public keys, and sealed blobs. It is a different database from the heartbeat project. Do not apply identity SQL to the telemetry project.
- State that install and pairing work logged out. The website does not render machine IPs. Password reset does not grant mailbox plaintext. The device private key stays on the machine.
- State that real sign-up waits on Ritik confirming a new $10/month Supabase project. Do not create that project. Do not put keys in git.
- State that a live Jev call waits on a credit card on the Vercel team. Do not call the gateway. Do not commit a key.
- Keep this change to spec files. Do not edit `Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `project.yml`, or pairing code.

No daemon route, wire type, or pairing payload changes. Install and the 8-character pairing code keep working with no account.

## Capabilities

### New Capabilities

- `account-identity`: What a website account stores, which database it uses, and what install, pairing, the website, password reset, and the device private key do.
- `account-launch-gates`: The two external waits (Ritik's project, a Vercel team card), the ban on keys in git, and the rule that this change does not rebuild finished slices or edit shared contracts.

### Modified Capabilities

- None. `terminal-sessions` stays as it is. The daemon does not learn about accounts.

## Non-goals

- Rebuilding the account pages, the identity SQL, the seal, the key file, the note draft, or the Jev filter. Those drafts are the implementation. Re-check each pull request tip before touching the same files, and do not open a second copy.
- Creating a Supabase project, applying identity SQL to the heartbeat project `zmisjteztezaqfflwbgf`, or committing `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, or `AI_GATEWAY_API_KEY`.
- A live call to the Vercel AI Gateway, including `POST https://ai-gateway.vercel.sh/v1/evaluate`.
- A sign-in screen on iPhone, Watch, or the menu bar. Native sealed sync stays a later change, and it reuses the existing seal and key file.
- A price, a Pro flag, a machine cap, a relay, or any edit to `openspec/changes/reach-my-mac-from-anywhere/`.
- Teaching `meshd` about accounts. No new route in `server.ts`.

## Impact

- This change adds only `openspec/changes/account-launch-handoff/`.
- Finished drafts stay where they are: account pages on pull request 150 (`cursor/account-site-e469`, tip `41cdbbc`), identity SQL on pull request 135, the note draft on pull request 154 (tip `cba3ac7`), the key file on pull request 155 (tip `03e40f5`) and pull request 157 (tip `bb1dd5c`, branch `cursor/swift-device-key-e469`), the seal on pull request 152, and the Jev filter on pull request 156.
- The heartbeat database `zmisjteztezaqfflwbgf` is untouched. The only Supabase project in the LeSearch AI org today is that heartbeat project.
- Production `mesh.lesearch.ai` is untouched. The Vercel preview of pull request 150 still redirects to Vercel sign-in.
