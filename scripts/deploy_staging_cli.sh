#!/usr/bin/env bash
set -euo pipefail

# Deploy staging infrastructure from CLI (no GitHub Actions)
# Prereqs:
#   - az login
#   - export POSTGRES_PASSWORD
#   - OR use GitHub CLI auth (gh auth login)
# Optional:
#   - export REGISTRY (default: ghcr.io)
#   - export IMAGE_NAME (default: <git remote repo>)
#   - export IMAGE_TAG (default: sha-<git sha>)
#   - export AZURE_RESOURCE_GROUP (default: rg-ip-geo-analytics)
#   - export AZURE_LOCATION (default: westeurope)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_FILE="$ROOT_DIR/infra/main.bicep"

REGISTRY="${REGISTRY:-ghcr.io}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-rg-ip-geo-analytics1}"
AZURE_LOCATION="${AZURE_LOCATION:-westeurope}"

if [[ -z "${REGISTRY_USERNAME:-}" || -z "${REGISTRY_PASSWORD:-}" ]]; then
  if command -v gh >/dev/null 2>&1; then
    GH_TOKEN="$(gh auth token 2>/dev/null || true)"
    if [[ -n "$GH_TOKEN" ]]; then
      REGISTRY_PASSWORD="$GH_TOKEN"
      REGISTRY_USERNAME="$(gh api user -q .login 2>/dev/null || true)"
    fi
  fi
fi

if [[ -z "${REGISTRY_USERNAME:-}" || -z "${REGISTRY_PASSWORD:-}" ]]; then
  echo "REGISTRY_USERNAME and REGISTRY_PASSWORD are required."
  echo "Tip: run 'gh auth login' or set REGISTRY_USERNAME/REGISTRY_PASSWORD env vars."
  exit 1
fi

POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-analytics123}"

IMAGE_NAME_DEFAULT="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null | sed -E 's#.*github\.com[:/]##; s#\.git$##' || true)"
IMAGE_NAME="${IMAGE_NAME:-$IMAGE_NAME_DEFAULT}"
if [[ -z "$IMAGE_NAME" ]]; then
  echo "IMAGE_NAME is required (e.g. macel94/ip-geo-analytics)."
  exit 1
fi

# Default to 'latest' tag. Override with IMAGE_TAG env var to use a specific commit SHA.
# To use git SHA: export IMAGE_TAG="sha-$(git rev-parse --short=12 HEAD)"
IMAGE_TAG="${IMAGE_TAG:-latest}"

az group create \
  --name "$AZURE_RESOURCE_GROUP" \
  --location "$AZURE_LOCATION" \
  --output none >/dev/null

az deployment group create \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --template-file "$INFRA_FILE" \
  --parameters \
    location="$AZURE_LOCATION" \
    environment=staging \
    imageTag="$REGISTRY/$IMAGE_NAME:$IMAGE_TAG" \
    registryServer="$REGISTRY" \
    registryUsername="$REGISTRY_USERNAME" \
    registryPassword="$REGISTRY_PASSWORD" \
    postgresPassword="$POSTGRES_PASSWORD" \
  --query 'properties.outputs' \
  -o json
