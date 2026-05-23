# ── iii-engine ────────────────────────────────────────────────────────────────
# Runs the iii engine (Rust binary) — the central WebSocket broker and HTTP server.
# Workers connect to :49134 (WebSocket).
# HTTP API is served on :3111.
# ------------------------------------------------------------------------------

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        jq \
    && rm -rf /var/lib/apt/lists/*

# Install the iii engine binary
RUN curl -fsSL https://install.iii.dev/iii/main/install.sh | sh

WORKDIR /app

# State store directory (mapped to a volume in production)
RUN mkdir -p /app/data

# Copy the engine-only config (no worker_path entries — workers run in separate containers)
COPY new-config.yaml ./config.yaml

# :3111  — HTTP API (proxied by nginx gateway)
# :49134 — WebSocket broker (workers connect here)
EXPOSE 3111 49134

CMD ["iii", "start"]
