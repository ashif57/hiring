# ── inference-worker ──────────────────────────────────────────────────────────
# Runs the Python worker that loads gemma-3-270m and handles inference::run_inference
# The model is downloaded during image build so the container needs no internet at runtime.
# Build arg HF_TOKEN is optional — gemma-3-270m is public, no token needed.
# ------------------------------------------------------------------------------

FROM python:3.11-slim

WORKDIR /app

# System deps needed by torch / transformers
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies first (better layer caching)
# --timeout 300 prevents pip dropping large downloads (torch CPU wheel is ~200MB)
COPY requirements.txt .
RUN pip install --no-cache-dir --timeout 300 -r requirements.txt

# Pre-download the model into the image so the container works without internet.
# Copy worker source
COPY inference_worker.py .

# III_URL is overridden at runtime via --env or docker-compose environment:
#   - local:  ws://iii-engine:49134
#   - AWS:    ws://10.0.2.10:49134  (vm-engine private IP)
ENV III_URL=ws://iii-engine:49134

# No ports exposed — worker connects OUTBOUND to iii engine only
CMD ["python", "inference_worker.py"]
