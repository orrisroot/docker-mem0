#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Patch upstream Mem0 repository for embedding dimensions and subpath support
# ==============================================================================

REPO_DIR="repo"

if [ ! -d "${REPO_DIR}" ]; then
  echo "Error: Directory '${REPO_DIR}' not found. Please run 'git clone --depth 1 https://github.com/mem0ai/mem0.git repo' first." >&2
  exit 1
fi

echo "==> Patching upstream Mem0 repository in ./${REPO_DIR}..."

# 1. Patch server/main.py for MEM0_DEFAULT_EMBEDDER_DIMS support
MAIN_PY="${REPO_DIR}/server/main.py"
if [ -f "${MAIN_PY}" ]; then
  if grep -q "MEM0_DEFAULT_EMBEDDER_DIMS" "${MAIN_PY}"; then
    echo "  [SKIP] ${MAIN_PY} already supports MEM0_DEFAULT_EMBEDDER_DIMS."
  else
    echo "  [PATCH] Adding MEM0_DEFAULT_EMBEDDER_DIMS support to ${MAIN_PY}..."
    sed -i '/DEFAULT_EMBEDDER_MODEL =/a DEFAULT_EMBEDDER_DIMS = int(os.environ.get("MEM0_DEFAULT_EMBEDDER_DIMS", "1536"))' "${MAIN_PY}"
    sed -i '/"collection_name": POSTGRES_COLLECTION_NAME,/a \            "embedding_model_dims": DEFAULT_EMBEDDER_DIMS,' "${MAIN_PY}"
    sed -i 's/"model": DEFAULT_EMBEDDER_MODEL/&, "embedding_dims": DEFAULT_EMBEDDER_DIMS/' "${MAIN_PY}"
  fi
else
  echo "  [WARN] ${MAIN_PY} not found, skipping."
fi

# 2. Patch server/dashboard/next.config.mjs for basePath support
NEXT_CONFIG="${REPO_DIR}/server/dashboard/next.config.mjs"
if [ -f "${NEXT_CONFIG}" ]; then
  if grep -q "basePath:" "${NEXT_CONFIG}"; then
    echo "  [SKIP] ${NEXT_CONFIG} already configured with basePath."
  else
    echo "  [PATCH] Adding basePath support to ${NEXT_CONFIG}..."
    sed -i '1s/^/const basePath = process.env.DASHBOARD_SUBPATH || process.env.BASE_PATH || process.env.NEXT_PUBLIC_BASE_PATH || "";\n\n/' "${NEXT_CONFIG}"
    sed -i 's/const nextConfig = {/const nextConfig = {\n  basePath: basePath ? (basePath.startsWith("\/") ? basePath : `\/${basePath}`) : undefined,/' "${NEXT_CONFIG}"
  fi
else
  echo "  [WARN] ${NEXT_CONFIG} not found, skipping."
fi

# 3. Patch server/dashboard/Dockerfile to pass BASE_PATH build arg
DOCKERFILE="${REPO_DIR}/server/dashboard/Dockerfile"
if [ -f "${DOCKERFILE}" ]; then
  if grep -q "ARG BASE_PATH" "${DOCKERFILE}"; then
    echo "  [SKIP] ${DOCKERFILE} already has ARG BASE_PATH."
  else
    echo "  [PATCH] Adding ARG BASE_PATH to ${DOCKERFILE}..."
    sed -i '/FROM base AS builder/a ARG BASE_PATH=""\nENV BASE_PATH=${BASE_PATH}\nENV NEXT_PUBLIC_BASE_PATH=${BASE_PATH}' "${DOCKERFILE}"
  fi
else
  echo "  [WARN] ${DOCKERFILE} not found, skipping."
fi

echo "==> All patches successfully applied!"
