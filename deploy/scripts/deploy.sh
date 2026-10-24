#!/usr/bin/env bash
# ==============================================================================
# ZeetaFin ERP — Phase 3 Production Container Deployment Script
# Description: Automated, idempotent deployment runner for AWS EC2 instances.
#              Authenticates to Amazon ECR, pulls latest images, recreates
#              containers cleanly without downtime/collision, and verifies health.
# ==============================================================================

set -euo pipefail

# Configuration Defaults (can be overridden by environment variables or CLI flags)
APP_DIR="${APP_DIR:-/home/ubuntu/zeetafin-app}"
COMPOSE_FILE="${APP_DIR}/docker-compose.prod.yml"
ENV_FILE="${APP_DIR}/.env"

IMAGE_TAG="${1:-${IMAGE_TAG:-latest}}"
ECR_REGISTRY="${2:-${ECR_REGISTRY:-}}"
AWS_REGION="${3:-${AWS_REGION:-us-east-1}}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=================================================================="
echo "  ZeetaFin CI/CD Deployment Engine — Phase 3 Container Rollout  "
echo "  Timestamp: $(date -u +'%Y-%m-%dT%H:%M:%SZ')                    "
echo "  Target Tag: ${IMAGE_TAG}                                        "
echo "=================================================================="

# 1. Directory and file validation
if [ ! -d "${APP_DIR}" ]; then
  log_info "Creating application workspace at ${APP_DIR}..."
  mkdir -p "${APP_DIR}"
fi

cd "${APP_DIR}"

if [ ! -f "${COMPOSE_FILE}" ]; then
  log_error "Compose file ${COMPOSE_FILE} not found. Aborting."
  exit 1
fi

if [ ! -f "${ENV_FILE}" ]; then
  log_warn "No .env file found at ${ENV_FILE}. Creating template..."
  if [ -f "${APP_DIR}/.env.example" ]; then
    cp "${APP_DIR}/.env.example" "${ENV_FILE}"
  else
    cat <<EOF > "${ENV_FILE}"
ECR_REGISTRY=${ECR_REGISTRY}
IMAGE_TAG=${IMAGE_TAG}
POSTGRES_USER=postgres
POSTGRES_PASSWORD=zeetafin_secret
POSTGRES_DB=zeetafin
JWT_SECRET=super_secret_jwt_key_zeetafin_devops_assignment_2026
NODE_ENV=production
DB_SYNC=true
DB_LOGGING=false
NEXT_PUBLIC_API_URL=http://localhost:3001/api
EOF
  fi
fi

# Ensure ECR_REGISTRY and IMAGE_TAG are exported into environment
export IMAGE_TAG="${IMAGE_TAG}"
if [ -n "${ECR_REGISTRY}" ]; then
  export ECR_REGISTRY="${ECR_REGISTRY}"
  # Update .env if needed
  if grep -q "^ECR_REGISTRY=" "${ENV_FILE}"; then
    sed -i "s|^ECR_REGISTRY=.*|ECR_REGISTRY=${ECR_REGISTRY}|" "${ENV_FILE}"
  else
    echo "ECR_REGISTRY=${ECR_REGISTRY}" >> "${ENV_FILE}"
  fi
fi

# 2. Amazon ECR Authentication
if [ -n "${ECR_REGISTRY}" ]; then
  log_info "Authenticating Docker CLI against Amazon ECR (${ECR_REGISTRY})..."
  if command -v aws &> /dev/null; then
    aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${ECR_REGISTRY}"
    log_success "Amazon ECR login succeeded."
  else
    log_warn "AWS CLI not detected on host. Relying on pre-authenticated session or credentials helper."
  fi
fi

# 3. Pull new images from ECR
log_info "Pulling updated Docker container images (tag: ${IMAGE_TAG})..."
docker compose -f "${COMPOSE_FILE}" pull

# 4. Graceful container replacement (Replaces old containers with new images)
log_info "Deploying updated container instances with zero/minimal downtime..."
docker compose -f "${COMPOSE_FILE}" up -d --remove-orphans --force-recreate

# 5. Health Check Loop
log_info "Verifying health status of deployed services..."
MAX_ATTEMPTS=20
SLEEP_INTERVAL=3

check_endpoint() {
  local url="$1"
  local name="$2"
  local attempts=0

  while [ $attempts -lt $MAX_ATTEMPTS ]; do
    attempts=$((attempts + 1))
    if curl -s -f -o /dev/null "${url}"; then
      log_success "${name} is healthy at ${url} (attempt ${attempts}/${MAX_ATTEMPTS})"
      return 0
    fi
    log_warn "${name} not ready yet. Retrying in ${SLEEP_INTERVAL}s... (${attempts}/${MAX_ATTEMPTS})"
    sleep $SLEEP_INTERVAL
  done

  log_error "Healthcheck failed for ${name} at ${url} after $((MAX_ATTEMPTS * SLEEP_INTERVAL)) seconds."
  return 1
}

# Allow containers time to initialize
sleep 5

# Validate Backend Swagger/API Docs & Frontend Home Page
check_endpoint "http://127.0.0.1:3001/api/docs" "ZeetaFin Backend"
check_endpoint "http://127.0.0.1:3000/" "ZeetaFin Frontend"

# 6. Housekeeping: Prune old untagged images to avoid disk exhaustion
log_info "Cleaning up obsolete dangling images..."
docker image prune -f --filter "until=24h" || true

# 7. Status report
echo ""
log_success "Deployment completed successfully! Current active containers:"
docker compose -f "${COMPOSE_FILE}" ps

echo "=================================================================="
echo "  ZeetaFin Phase 3 Deployment Successfully Verified!             "
echo "=================================================================="
