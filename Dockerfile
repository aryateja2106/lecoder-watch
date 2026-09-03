# meshd only — the Bun + TypeScript daemon for Linux hosts and VPS boxes.
# Apple Watch, iPhone, and Mac menu-bar apps are not containerized.
#
# Build (multi-arch, optional):
#   docker buildx build --platform linux/amd64,linux/arm64 -t meshd .
FROM oven/bun:1-debian

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    tmux curl ca-certificates openssl \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/mesh
COPY install/payload/meshd/ ./meshd/
COPY install/payload/bin/mesh /usr/local/bin/mesh
RUN chmod +x /usr/local/bin/mesh

COPY docker/entrypoint.sh /usr/local/bin/meshd-entrypoint
RUN chmod +x /usr/local/bin/meshd-entrypoint

ENV HOME=/data \
    MESH_HOME=/data/.mesh \
    MESHD_HOST=0.0.0.0 \
    MESHD_PORT=8899 \
    MESH_MUX=tmux

EXPOSE 8899
VOLUME ["/data"]

WORKDIR /opt/mesh/meshd
ENTRYPOINT ["/usr/local/bin/meshd-entrypoint"]
CMD ["bun", "run", "server.ts"]
