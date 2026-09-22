## 1. Re-check the finished slices

No task in this change needs Arya's physical iPhone or Apple Watch.

- [ ] 1.1 Re-check the account pages on pull request 150 before touching any account page. Record the current `headRefOid`. Leave the pages where they are. Do not add another `web/account/`. *Verify by running:* `gh pr view 150 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`
- [ ] 1.2 Re-check the identity SQL on pull request 135. It is the migration. Do not apply identity SQL to the telemetry project `zmisjteztezaqfflwbgf`, and do not add a second SQL file. *Verify by running:* `gh pr view 135 --repo aryateja2106/lecoder-watch --json title,state,headRefName,files`
- [ ] 1.3 Re-check the node seal/open helper on pull request 138. Record the current `headRefOid`. Do not start another copy. *Verify by running:* `gh pr view 138 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`
- [ ] 1.4 Re-check the Swift seal check on pull request 141. Record the current `headRefOid`. Do not start another copy. *Verify by running:* `gh pr view 141 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`
- [ ] 1.5 Re-check the menu-bar sealed upload bodies on pull request 152. That file is not in the Xcode target. Record the current `headRefOid`. Do not start another copy. *Verify by running:* `gh pr view 152 --repo aryateja2106/lecoder-watch --json title,state,headRefName,headRefOid`
- [ ] 1.6 Re-check the key file on pull requests 155 and 157, the note draft on pull request 154, and the Jev filter on pull request 156. Record each `headRefOid`. Do not start another key-file format, note draft, or filter. *Verify by running:* `gh pr view 155 --repo aryateja2106/lecoder-watch --json headRefOid && gh pr view 157 --repo aryateja2106/lecoder-watch --json headRefOid && gh pr view 154 --repo aryateja2106/lecoder-watch --json headRefOid && gh pr view 156 --repo aryateja2106/lecoder-watch --json headRefOid`
- [ ] 1.7 Re-check the account flow check on pull request 158, the sealed mailbox round trip on pull request 159, and the route-gated draft on pull request 160. Record each `headRefOid`. Do not start another copy of any of them. *Verify by running:* `gh pr view 158 --repo aryateja2106/lecoder-watch --json title,headRefOid && gh pr view 159 --repo aryateja2106/lecoder-watch --json title,headRefOid && gh pr view 160 --repo aryateja2106/lecoder-watch --json title,headRefOid`

## 2. Keep this change to spec files

- [ ] 2.1 Confirm the branch diff against `origin/main` contains only `openspec/changes/account-launch-handoff/`. Do not edit `Shared/Models.swift`, `Shared/MeshClient.swift`, `install/payload/meshd/server.ts`, `project.yml`, or pairing code. *Verify by running:* `git diff --name-only origin/main`
- [ ] 2.2 Confirm the shared contracts and pairing code are absent from the diff. *Verify by running:* `git diff --name-only origin/main -- Shared/Models.swift Shared/MeshClient.swift install/payload/meshd/server.ts install/payload/meshd/pair.ts project.yml`
- [ ] 2.3 Confirm this change did not add account pages, identity SQL, a node seal/open helper, a Swift seal check, menu-bar sealed upload bodies, a key file, a note draft, a Jev filter, an account flow check, a sealed mailbox round trip, or a route-gated draft. *Verify by running:* `git diff --name-only origin/main -- web/account supabase/account experiments/jev-routing install/payload/meshd MeshDesktop Shared`

## 3. Refuse the two live calls

- [ ] 3.1 Real sign-up waits on Ritik confirming a new $10/month Supabase project. Do not create that project. Do not put keys in git. Stop if the confirmation is missing. The env var names may appear as instructions. A JWT, a service-role secret, or a database URL must not. *Verify by running:* `if git grep -n -E 'eyJ[A-Za-z0-9_-]{8,}|sb_secret_|postgresql://' -- openspec/changes/account-launch-handoff; then exit 1; else echo 'no keys in the change'; fi`
- [ ] 3.2 A live Jev call waits on a credit card on the Vercel team. Do not call the gateway. Do not commit a key. The forbidden URL may be named. A curl or fetch of it must not appear. *Verify by running:* `if git grep -n -E 'curl .*ai-gateway|fetch\(.*ai-gateway' -- openspec/changes/account-launch-handoff; then exit 1; else echo 'no gateway call in the change'; fi`

## 4. Validate the spec

- [ ] 4.1 Validate the change in strict mode. *Verify by running:* `openspec validate account-launch-handoff --type change --strict`
- [ ] 4.2 Show the change status and confirm `tasks` is done. *Verify by running:* `openspec status --change account-launch-handoff`
