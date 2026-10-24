#!/usr/bin/env bash
# ==============================================================================
# ZeetaFin ERP — Phase 3 Deployment Health & Availability Prober
# ==============================================================================

set -euo pipefail

HOST="${1:-127.0.0.1}"
BACKEND_URL="http://${HOST}:3001/api/docs"
FRONTEND_URL="http://${HOST}:3000/"

echo "Probing ZeetaFin ERP endpoints on host: ${HOST}..."

# Test Backend
echo -n "Checking Backend (${BACKEND_URL})... "
HTTP_CODE_BACKEND=$(curl -s -o /dev/null -w "%{http_code}" "${BACKEND_URL}" || echo "000")
if [ "${HTTP_CODE_BACKEND}" -eq 200 ] || [ "${HTTP_CODE_BACKEND}" -eq 301 ] || [ "${HTTP_CODE_BACKEND}" -eq 302 ]; then
  echo "OK (HTTP ${HTTP_CODE_BACKEND})"
else
  echo "FAILED (HTTP ${HTTP_CODE_BACKEND})"
  exit 1
fi

# Test Frontend
echo -n "Checking Frontend (${FRONTEND_URL})... "
HTTP_CODE_FRONTEND=$(curl -s -o /dev/null -w "%{http_code}" "${FRONTEND_URL}" || echo "000")
if [ "${HTTP_CODE_FRONTEND}" -eq 200 ] || [ "${HTTP_CODE_FRONTEND}" -eq 307 ] || [ "${HTTP_CODE_FRONTEND}" -eq 308 ]; then
  echo "OK (HTTP ${HTTP_CODE_FRONTEND})"
else
  echo "FAILED (HTTP ${HTTP_CODE_FRONTEND})"
  exit 1
fi

echo "All services healthy and responsive!"
exit 0
