# Releasing

Two artifacts ship from this repo:

- **The mesh payload** — `meshd`, `rmux-bridge`, the hook tools and the `mesh` CLI.
  Published as a GitHub release of the public repo
  [LeSearch-AI/mesh-install](https://github.com/LeSearch-AI/mesh-install), which
  holds no source: it exists so the advertised one-liner resolves without auth.
- **The app** — the iPhone relay and watchOS app, built in Xcode. Not on the App
  Store; it is installed from Xcode onto the maintainer's devices.

They share one version number and one git tag.

## The contract

Semver, on the tag. The tag is authoritative; everything else has to be made to
agree with it before it is cut.

| Bump  | When |
| ----- | ---- |
| MAJOR | A breaking change to the meshd HTTP API (an endpoint or a response field the app parses is removed or renamed), a breaking `install.sh` flag change, or a payload layout an already-published `install.sh` cannot validate. |
| MINOR | A new endpoint, capability, session source or CLI command; a user-visible app feature. |
| PATCH | Fixes, performance, docs, packaging. |

**The compatibility surface is old `install.sh` + new tarball.** The published
`install.sh` is stamped with `.../releases/latest/download`, so a copy someone
piped a month ago still fetches today's `mesh-install.tgz`. `validate_payload`
lives inside that old `install.sh`, so *adding* files to the payload is always
safe; *removing* one that an older installer requires (`meshd/server.ts`,
`meshd/package.json`, `rmux-bridge/src/server.ts`, `rmux-bridge/package.json`,
`rmux-bridge/public/index.html`, and `bin/{mesh,mesh-event,mesh-hook,mesh-agent-run,mesh-codex-notify,mesh-self-check}`)
breaks installs for everyone who did not re-download. That is a MAJOR.

## Version strings that must move together

`install/payload/meshd/server.ts` `VERSION` and `project.yml`
`MARKETING_VERSION` are the two the contract names: the first is what
`/health` reports and what the Machines tab and `mesh health` display, the second
is the app's `CFBundleShortVersionString`. A user comparing "the app says 0.1.0,
the daemon says 0.2.1" has no way to tell what they are running.

**They currently disagree.** Verified state of the tree at 2026-08-12:

| Where | Value | What it drives |
| ----- | ----- | -------------- |
| git tag (this repo) | *none yet* | triggers `.github/workflows/release.yml` |
| latest release of LeSearch-AI/mesh-install | `v0.2.1` | what `latest/download` resolves to |
| `install/payload/meshd/server.ts:13` `const VERSION` | `0.2.1` | `/health.meshdVersion`, startup log |
| `project.yml:10` `MARKETING_VERSION` | `0.1.0` | app version on both targets |
| `project.yml:11` `CURRENT_PROJECT_VERSION` | `1` | build number; bump on every device build |
| `install/payload/bin/mesh:10` `const VERSION` | `0.1.0` | `mesh version`, the help banner |
| `install/payload/share/man/man1/mesh.1:1` `.TH` | `mesh 0.1.0`, dated 2026-07-07 | `man mesh` footer |
| `install/payload/meshd/package.json` `version` | `0.1.0` | nothing at runtime (`private: true`) |
| `meshd/server.ts:12` `const VERSION` | `0.2.0` | nothing — dev copy, never packaged |
| `packaging/npm/package.json` `version` | `0.2.1` | npm, when published |
| `packaging/homebrew/lesearch-mesh.rb` `url`/`sha256`/`version` | `0.2.1` | brew, when the tap exists |

Fixing the drift is a release chore, not a code change: set every row to the tag
being cut. Note also that **0.2.0 was never published** — releases went
v0.1.0 (2026-06-20) → v0.2.1 (2026-08-12) — so the `0.2.0` in the dev copy of
`meshd/server.ts` corresponds to nothing.

`CURRENT_PROJECT_VERSION` is the exception: it is a build counter, monotonically
increasing, unrelated to semver.

## Cutting a release

1. **Bump every row of the table above** to the new version, including the `.TH`
   date in `mesh.1`, the formula's `url`/`sha256`/`version` (the sha256 can only
   be computed after publishing — see step 7), and `packaging/npm/package.json`.
2. **Update `CHANGELOG.md`**: rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`,
   open a fresh empty `[Unreleased]`, and add the link references at the bottom.
   The workflow extracts this exact section as the release notes and **fails the
   build if there is no `## [X.Y.Z]` heading**.
3. **Run the checks that do not need Xcode:**
   ```sh
   sh -n install/install.sh
   bun scripts/check-orca-adapter.ts
   sh scripts/check-package-mesh-install.sh
   ```
4. **If the app changed, run the Xcode-side checks too** — the release workflow
   cannot, so this is the only gate on them:
   ```sh
   # Each check compiles against the Shared/ types it exercises; the exact
   # command is in a comment at the top of each file.
   swiftc Shared/Install.swift scripts/check-install-summary.swift -o /tmp/cis && /tmp/cis
   swiftc Shared/Models.swift Shared/LimitHelpers.swift scripts/check-limit-helpers.swift -o /tmp/clh && /tmp/clh
   swiftc Shared/Models.swift scripts/check-session-state.swift -o /tmp/css && /tmp/css
   xcodegen generate
   xcodebuild -scheme "MeshWatch" -destination 'generic/platform=iOS' build
   xcodebuild -scheme "MeshWatch Watch App" -destination 'generic/platform=watchOS' build
   ```
5. **Commit on a branch** (never `main`), then tag and push the tag:
   ```sh
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```
6. **The workflow does the rest** — see `.github/workflows/release.yml`. It lints
   `install.sh`, runs the payload self-checks, builds `mesh-install.tgz`, stamps
   and emits `install.sh`, writes `SHA256SUMS.txt`, publishes all three to
   LeSearch-AI/mesh-install with the changelog section as notes, then
   re-downloads them and compares.
7. **Update the Homebrew formula** with the published tarball's checksum:
   ```sh
   curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/download/vX.Y.Z/mesh-install.tgz | shasum -a 256
   ```
   and copy `packaging/homebrew/lesearch-mesh.rb` into the tap repo (which does
   not exist yet — the formula header has the `gh repo create` command).

### Manual fallback

This is how v0.1.0 and v0.2.1 were actually cut, and it still works if the
workflow is down or `RELEASE_TOKEN` has expired:

```sh
mkdir -p /tmp/dist
sh scripts/package-mesh-install.sh /tmp/dist/mesh-install.tgz \
  https://github.com/LeSearch-AI/mesh-install/releases/latest/download
cd /tmp/dist && shasum -a 256 install.sh mesh-install.tgz > SHA256SUMS.txt
gh release create vX.Y.Z --repo LeSearch-AI/mesh-install \
  --title "vX.Y.Z" --notes-file NOTES.md \
  install.sh mesh-install.tgz SHA256SUMS.txt
```

**Package from a clean tree.** `package-mesh-install.sh` tars the working
directory, not `git ls-files`, so untracked files ship. The published v0.2.1
tarball contains `install/payload/meshd/.omc/state/sessions/<uuid>/` for exactly
this reason, and `scripts/check-package-mesh-install.sh` only rejects `.omx/`.
Run `git clean -nxd install/` first, or package from a fresh clone. The CI job
builds from a fresh checkout and hard-fails on `.omc`/`.omx`/`.git`/`.DS_Store`
paths in the tarball.

## Verifying a release

The only test that matters is a stranger's: download from the public URL, into a
directory with nothing else in it.

```sh
tmp=$(mktemp -d); cd "$tmp"
base=https://github.com/LeSearch-AI/mesh-install/releases/latest/download
for f in install.sh mesh-install.tgz SHA256SUMS.txt; do curl -fsSL -O "$base/$f"; done

shasum -a 256 -c SHA256SUMS.txt            # both must say OK
grep '^MESH_SRC_DEFAULT=' install.sh       # must be a URL, never "__MESH_SRC__"
sh -n install.sh                           # parses as POSIX sh

# Sandboxed install: own prefix, own service label, nothing started, so this
# cannot disturb the meshd already running on this machine.
MESH_LABEL_PREFIX=ai.lesearch.verify \
  sh install.sh --prefix "$tmp/mesh" --no-start --src "$tmp/mesh-install.tgz"
"$tmp/mesh/bin/mesh" help                  # the CLI actually made it into the payload
rm -rf "$tmp"
```

Verified against v0.2.1 on 2026-08-12: checksums OK, stamp
`https://github.com/LeSearch-AI/mesh-install/releases/latest/download`, sandboxed
install exits 0 and `bin/mesh` runs.

`mesh-install.tgz` is **not** byte-reproducible — `tarfile` records mtimes, so two
builds of the same tree differ. `install.sh` is: rebuilding v0.2.1's from a clean
checkout of that commit reproduces
`d2a9914ed12067fff35b69ace9def15848556dec4b89c5e5f6727e1ab8c2fee6` exactly. Compare
tarballs by `tar tzf` listing, not by checksum. (Doing that on v0.2.1 is how the
`.omc/` leak above was found: 45 entries published against 39 from a clean tree.)

Then the real thing, on a machine that has never had the mesh on it — a spare
box, a VM, or a fresh Unix user (`install.sh --user NAME` on Linux):

```sh
curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh | sh
~/.mesh/bin/mesh-self-check
```

`mesh-self-check` treats `meshd`, `/agents`, `/events`, `/tailnet`, `rmux-bridge`
and hook posting as required. Reboot the box and check `meshd` comes back —
"can't see machines" has historically meant dead daemons, not a broken app.

## Re-publishing a tag

`gh release create` refuses an existing release. To redo one:

```sh
gh release delete vX.Y.Z --repo LeSearch-AI/mesh-install --cleanup-tag --yes
```

then re-run the workflow from the Actions tab (`workflow_dispatch` takes the tag
as an input, so no re-tagging is needed).

## Secrets and repos

- `RELEASE_TOKEN` — repo secret on `aryateja2106/lecoder-watch`. A PAT with write
  access to `LeSearch-AI/mesh-install` (classic `repo`, or fine-grained with
  Contents: Read and write on that repo). The automatic `GITHUB_TOKEN` is scoped
  to this repo only and **cannot** publish cross-repo.
- `LeSearch-AI/homebrew-tap` — does not exist yet; needed only for `brew install`.
- npm org `@lesearch` — needed only to publish `packaging/npm`. Nothing is
  published there today, and there is no LICENSE file in either repo, so
  `package.json` says `UNLICENSED`. Pick a license first.
