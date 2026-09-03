# meshd only — the Bun + TypeScript daemon for Linux hosts and VPS boxes.
# Apple Watch, iPhone, and Mac menu-bar apps are not containerized.
#
# Official slim tag is Debian (trixie-slim), not Alpine. Hub name is `1-slim`
# (there is no `1-debian-slim` tag). Multi-arch: linux/amd64 + linux/arm64.
# A plain `docker build` produces the host arch. For both:
#   docker buildx build --platform linux/amd64,linux/arm64 -t meshd .
FROM oven/bun:1-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    tmux ca-certificates openssl \
  && rm -rf /var/lib/apt/lists/* \
  && if ! id bun >/dev/null 2>&1; then \
       groupadd --gid 1000 bun \
       && useradd --uid 1000 --gid bun --home-dir /home/bun --create-home bun; \
     fi \
  && mkdir -p /data/.mesh \
  && chown -R bun:bun /data

WORKDIR /opt/mesh
COPY --chown=bun:bun install/payload/meshd/ ./meshd/
COPY --chown=bun:bun install/payload/bin/mesh /usr/local/bin/mesh
COPY --chown=bun:bun docker/entrypoint.sh /usr/local/bin/meshd-entrypoint
RUN chmod 755 /usr/local/bin/mesh /usr/local/bin/meshd-entrypoint

# HOME=/data is load-bearing: meshd writes to homedir()/.mesh and ignores MESH_HOME.
# MESH_HOME is for the mesh CLI in the same container so both land on the volume.
ENV HOME=/data \
    MESH_HOME=/data/.mesh \
    MESHD_HOST=0.0.0.0 \
    MESHD_PORT=8899 \
    MESH_MUX=tmux \
    MESHD_CONTAINER=1

EXPOSE 8899
VOLUME ["/data"]
USER bun

WORKDIR /opt/mesh/meshd
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["bun", "-e", "const r=await fetch('http://127.0.0.1:8899/health'); if (!r.ok) process.exit(1)"]
ENTRYPOINT ["/usr/local/bin/meshd-entrypoint"]
CMD ["bun", "run", "server.ts"]
