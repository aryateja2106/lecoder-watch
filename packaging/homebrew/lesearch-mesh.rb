# Homebrew formula for the `mesh` CLI — the command-line client for the meshd HTTP
# API that the MeshWatch iPhone and Watch apps drive.
#
# SCOPE: this installs the CLIENT ONLY. It does not install, start or supervise
# meshd. A machine you want to control still needs the curl installer:
#   curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh | sh
# Brew is for the laptop you type on; the installer is for every box you reach.
#
# WHERE THIS FILE BELONGS: a Homebrew tap repo. This copy is the source of truth
# and gets copied there on release. THE TAP DOES NOT EXIST YET — create it with:
#
#   gh repo create LeSearch-AI/homebrew-tap --public \
#     --description "Homebrew tap for LeSearch AI tools"
#   git clone https://github.com/LeSearch-AI/homebrew-tap /tmp/homebrew-tap
#   mkdir -p /tmp/homebrew-tap/Formula
#   cp packaging/homebrew/lesearch-mesh.rb /tmp/homebrew-tap/Formula/
#   git -C /tmp/homebrew-tap add Formula/lesearch-mesh.rb
#   git -C /tmp/homebrew-tap commit -m "lesearch-mesh 0.2.1"
#   git -C /tmp/homebrew-tap push
#
# Users then run:
#   brew tap lesearch-ai/tap
#   brew install lesearch-ai/tap/lesearch-mesh
# (`lesearch-ai/tap` is Homebrew's shorthand for the repo `LeSearch-AI/homebrew-tap`.)
#
# BUMPING: url + sha256 + version move together on every release. Recompute with
#   curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/download/vX.Y.Z/mesh-install.tgz | shasum -a 256

class LesearchMesh < Formula
  desc "Command-line client for a MeshWatch mesh (meshd HTTP API)"
  homepage "https://github.com/LeSearch-AI/mesh-install"
  url "https://github.com/LeSearch-AI/mesh-install/releases/download/v0.2.1/mesh-install.tgz"
  # Verified against the release asset digest on 2026-08-12.
  sha256 "b7276f36aec20f48a442912714e28988a2b522875312640a0729b8095539f807"
  version "0.2.1"
  # TODO: neither this repo nor LeSearch-AI/mesh-install has a LICENSE file, so
  # there is nothing truthful to put in `license`. Add one (MIT matches Orca) and
  # then set it here — Homebrew's audit warns on a missing license.

  # `mesh` is a bun script (#!/usr/bin/env bun), not a compiled binary, so bun is
  # a runtime dependency rather than a build one.
  depends_on "bun"

  def install
    # The tarball's entries all live under a single `install/` directory, which
    # Homebrew normally strips when staging. Handle both, so a change in either
    # end does not silently break the formula.
    root = Pathname.pwd/"install"
    root = Pathname.pwd unless root.directory?

    bin.install root/"payload/bin/mesh"
    man1.install root/"payload/share/man/man1/mesh.1"
  end

  def caveats
    <<~EOS
      This installs the `mesh` client only. To put a machine ON the mesh, run the
      installer there (it sets up meshd under launchd/systemd and prints a token):

        curl -fsSL https://github.com/LeSearch-AI/mesh-install/releases/latest/download/install.sh | sh

      Then register it:  mesh host add <name> <ip> --token <token>

      `mesh man` looks for ~/.mesh/share/man/man1/mesh.1 and will not find this
      copy; use `man mesh` instead, or set MESH_HOME.
    EOS
  end

  test do
    # `mesh version` reports the CLI's own VERSION const, which is still 0.1.0 and
    # has drifted from the release version (see docs/RELEASING.md) — asserting on
    # it would be asserting on a bug. The help banner is stable and true.
    assert_match "control a MeshWatch mesh", shell_output("#{bin}/mesh help")
    assert_match "mesh host add", shell_output("#{bin}/mesh help host")
  end
end
