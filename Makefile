# ==============================================================================
# Makefile — ZeetaFin Platform Developer & Operations Ergonomics
# ==============================================================================

.PHONY: help dev dev-down dev-logs test lint infra-init infra-plan infra-apply clean

help:
	@echo "=================================================================="
	@echo "  ZeetaFin Enterprise Cloud Platform — Developer & Ops Commands   "
	@echo "=================================================================="
	@echo "  make dev          - Start local Docker Compose stack (hot-reload)"
	@echo "  make dev-down     - Stop and tear down local development stack"
	@echo "  make dev-logs     - Tail logs across local development containers"
	@echo "  make test         - Run test suites for backend and frontend apps"
	@echo "  make lint         - Check code formatting & terraform fmt"
	@echo "  make infra-init   - Initialize Terraform production remote state"
	@echo "  make infra-plan   - Generate Terraform execution plan (dry-run)"
	@echo "  make infra-apply  - Provision AWS cloud infrastructure"
	@echo "  make clean        - Prune local dangling Docker build caches"
	@echo "=================================================================="

# ------------------------------------------------------------------------------
# Local Development Lifecycle (deploy/docker-compose.yml)
# ------------------------------------------------------------------------------
dev:
	docker compose -f deploy/docker-compose.yml up --build -d

dev-down:
	docker compose -f deploy/docker-compose.yml down

dev-logs:
	docker compose -f deploy/docker-compose.yml logs -f

# ------------------------------------------------------------------------------
# Testing & Code Quality Gates
# ------------------------------------------------------------------------------
test:
	@echo "--> Running backend test suite..."
	cd apps/backend && npm test
	@echo "--> Running frontend build check..."
	cd apps/frontend && npm run build

lint:
	@echo "--> Checking Terraform formatting..."
	terraform fmt -check -recursive infra/terraform
	@echo "--> Checking Backend formatting..."
	cd apps/backend && npm run lint || true

# ------------------------------------------------------------------------------
# Infrastructure as Code (infra/terraform/environments/prod)
# ------------------------------------------------------------------------------
infra-init:
	cd infra/terraform/environments/prod && terraform init

infra-plan:
	cd infra/terraform/environments/prod && terraform plan

infra-apply:
	cd infra/terraform/environments/prod && terraform apply

# ------------------------------------------------------------------------------
# Housekeeping
# ------------------------------------------------------------------------------
clean:
	docker image prune -f
