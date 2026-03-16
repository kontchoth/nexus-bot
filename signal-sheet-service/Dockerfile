# signal-sheet-service — Cloud Run container
# Multi-stage build: keeps final image lean (no build tools)

# ── Stage 1: install dependencies ─────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /build

# Install system deps needed by Pillow
RUN apt-get update && apt-get install -y --no-install-recommends \
    libfreetype6-dev \
    fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: runtime ──────────────────────────────────────────────────────────
FROM python:3.11-slim

WORKDIR /app

# Copy fonts (needed by screenshot renderer)
RUN apt-get update && apt-get install -y --no-install-recommends \
    fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Non-root user (Cloud Run security best practice)
RUN adduser --disabled-password --gecos "" appuser

# Copy application source (owned by appuser)
COPY --chown=appuser:appuser . .

USER appuser

# Cloud Run injects PORT env var (default 8080)
ENV PORT=8080
EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", \
     "--workers", "1", "--log-level", "info"]
