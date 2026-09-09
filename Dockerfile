# meshd only — the Bun + TypeScript daemon for Linux hosts and VPS boxes.
# Apple Watch, iPhone, and Mac menu-bar apps are not containerized.
#
# Multi-stage: copy the bun binary from the official image onto debian:bookworm-slim
# so we do not inherit oven/bun's extra layers. Not Alpine (tmux + glibc).
# A plain `docker build` produces the host arch. For both:
#   docker buildx build --platform linux/amd64,linux/arm64 -t meshd .
FROM oven/bun:1-slim AS bun

FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    tmux curl ca-certificates openssl \
  && rm -rf /var/lib/apt/lists/* \
  && groupadd --gid 1000 mesh \
  && useradd --uid 1000 --gid mesh --home-dir /data --shell /bin/sh mesh \
  && mkdir -p /data/.mesh \
  && chown -R mesh:mesh /data

COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun
RUN chmod 755 /usr/local/bin/bun \
  && ln -sf /usr/local/bin/bun /usr/local/bin/bunx

WORKDIR /opt/mesh
COPY --chown=mesh:mesh install/payload/meshd/ ./meshd/
# CLI lives next to meshd so `mesh pair` can load ../meshd/qr.ts
COPY --chown=mesh:mesh install/payload/bin/mesh ./bin/mesh
COPY --chown=mesh:mesh docker/entrypoint.sh /usr/local/bin/meshd-entrypoint
RUN chmod 755 /opt/mesh/bin/mesh /usr/local/bin/meshd-entrypoint \
  && ln -sf /opt/mesh/bin/mesh /usr/local/bin/mesh

# HOME=/data is load-bearing: meshd writes to homedir()/.mesh and ignores MESH_HOME.
# MESH_HOME is for the mesh CLI in the same container so both land on the volume.
ENV HOME=/data \
    MESH_HOME=/data/.mesh \
    PATH="/opt/mesh/bin:/usr/local/bin:${PATH}" \
    MESHD_HOST=0.0.0.0 \
    MESHD_PORT=8899 \
    MESH_MUX=tmux \
    MESHD_CONTAINER=1

EXPOSE 8899
VOLUME ["/data"]
USER mesh

WORKDIR /opt/mesh/meshd
HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8899/health
ENTRYPOINT ["/usr/local/bin/meshd-entrypoint"]
CMD ["bun", "run", "server.ts"]
