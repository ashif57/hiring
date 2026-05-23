# ── caller-worker ─────────────────────────────────────────────────────────────
# Runs the TypeScript worker that exposes the HTTP trigger and fans requests
# into inference::run_inference via RPC.
# ------------------------------------------------------------------------------

FROM node:20-slim

WORKDIR /app

# Install all dependencies (including devDeps — tsx is needed to run TS directly)
COPY package.json package-lock.json ./
RUN npm ci

# Copy source
COPY tsconfig.json ./
COPY src/ ./src/

# III_URL is overridden at runtime via --env or docker-compose environment
ENV III_URL=ws://iii-engine:49134

# No ports exposed — worker connects OUTBOUND to iii engine only
CMD ["npx", "tsx", "src/worker.ts"]
