#!/bin/sh

# Run interactive agents through MeshWatch event wrappers.
# These commands preserve the agent's normal terminal UI.

~/.mesh/bin/mesh-agent-run claude claude
~/.mesh/bin/mesh-agent-run codex codex
~/.mesh/bin/mesh-agent-run pi "$SHELL"
