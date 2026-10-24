#!/usr/bin/env bash
# ==============================================================================
# ZeetaFin Platform — Automated Rollback Engine
# Description: Instantly rolls back the production container stack to a previous
#              stable Docker image tag or Git commit SHA.
#
# Usage:
#   ./rollback.sh <TARGET_IMAGE_TAG> [ECR_REGISTRY] [AWS_REGION]
#
# Example:
#   ./rollback.sh sha-a1b2c3d
# ==============================================================================

set -euo pipefail

# Directory and Configuration Defaults
APP_DIR="${APP_DIR:-/home/ubuntu/zeetafin-app}"
COMPOSE_FILE="${APP_DIR}/docker-compose.prod.yml"
ENV_FILE="${APP_DIR}/.env"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

if [ $# -lt 1 ]; then
  log_error "Usage: $0 <TARGET_IMAGE_TAG> [ECR_REGISTRY] [AWS_REGION]"
  log_error "Example: $0 sha-9f2b84c"
  exit 1
fi

TARGET_TAG="$1"
ECR_REGISTRY="${2:-${ECR_REGISTRY:-}}"
AWS_REGION="${3:-${AWS_REGION:-us-east-1}}"

echo "=================================================================="
echo "  ZeetaFin Production Rollback Engine                             "
echo "  Timestamp:    $(date -u +'%Y-%m-%dT%H:%M:%SZ')                  "
echo "  Target Tag:   ${TARGET_TAG}                                     "
echo "=================================================================="

cd "${APP_DIR}"

if [ ! -f "${COMPOSE_FILE}" ]; then
  log_error "Compose file ${COMPOSE_FILE} not found. Cannot rollback."
  exit 1
fi

if [ ! -f "${ENV_FILE}" ]; then
  log_error "Environment file ${ENV_FILE} not found."
  exit 1
fi

# 1. Capture current running image tag for audit logging
CURRENT_TAG=$(grep "^IMAGE_TAG=" "${ENV_FILE}" | cut -d'=' -f2 || echo "unknown")
log_warn "Initiating rollback: Current tag [${CURRENT_TAG}] -> Rollback target [${TARGET_TAG}]"

# 2. Amazon ECR Authentication
if [ -n "${ECR_REGISTRY}" ] && command -v aws &> /dev/null; then
  log_info "Authenticating with Amazon ECR..."
  aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ECR_REGISTRY}"
fi

# 3. Export target tag and update .env file
export IMAGE_TAG="${TARGET_TAG}"
sed -i "s|^IMAGE_TAG=.*|IMAGE_TAG=${TARGET_TAG}|" "${ENV_FILE}"

# 4. Pull target rollback images
log_info "Pulling rollback images for tag ${TARGET_TAG}..."
if ! docker compose -f "${COMPOSE_FILE}" pull; then
  log_error "Failed to pull image with tag ${TARGET_TAG}. Reverting .env to ${CURRENT_TAG}."
  sed -i "s|^IMAGE_TAG=.*|IMAGE_TAG=${CURRENT_TAG}|" "${ENV_FILE}"
  exit 1
fi

# 5. Swap containers with rollback version
log_info "Recreating container instances with target version..."
docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans --force-recreate

# 6. Verify health of rolled-back services
log_info "Waiting for service initialization (10s)..."
sleep 10

MAX_ATTEMPTS=15
check_health() {
  local url="$1"
  local name="$2"
  local attempts=0

  while [ $attempts -lt $MAX_ATTEMPTS ]; do
    attempts=$((attempts + 1))
    if curl -s -f -o /dev/null "${url}"; then
      log_success "${name} is operational at ${url}."
      return 0
    fi
    sleep 2
  done
  log_error "${name} healthcheck failed after rollback."
  return 1
}

check_health "http://127.0.0.1:3001/api/docs" "Backend API"
check_health "http://127.0.0.1:3000/" "Frontend Portal"

echo ""
log_success "Rollback to ${TARGET_TAG} completed successfully and verified."
echo "=================================================================="
