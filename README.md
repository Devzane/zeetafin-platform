# ZeetaFin ERP — Cloud Infrastructure & Automated CI/CD Platform

> Production-grade AWS cloud infrastructure, hardened configuration management, multi-stage container orchestration, and zero-downtime CI/CD delivery for an enterprise financial management platform.

[![AWS](https://img.shields.io/badge/AWS-Cloud_Infrastructure-232F3E?logo=amazon-aws&logoColor=white)](#cloud-architecture)
[![Terraform](https://img.shields.io/badge/Terraform-1.10_IaC-7B42BC?logo=terraform&logoColor=white)](#infrastructure-as-code)
[![Ansible](https://img.shields.io/badge/Ansible-Configuration_Management-EE0000?logo=ansible&logoColor=white)](#configuration-management)
[![Docker](https://img.shields.io/badge/Docker-Multi--Stage_Builds-2496ED?logo=docker&logoColor=white)](#containerization)
[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-Automated_CI%2FCD-2088FF?logo=github-actions&logoColor=white)](#cicd-deployment-engine)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16_Alpine-4169E1?logo=postgresql&logoColor=white)](#local-quickstart)

---

## 🏛️ System Architecture

The ZeetaFin cloud platform is engineered as a secure, highly available, multi-tier system hosted on Amazon Web Services (AWS). All resources are provisioned strictly via Infrastructure as Code (Terraform) and provisioned via automated configuration management (Ansible).

![Cloud Architecture](docs/architecture/architecture.png)

### Key Architectural Boundaries
1. **Network Layer (VPC)**: Custom Virtual Private Cloud (`10.0.0.0/16`) with deterministically partitioned public subnets, Internet Gateway, and custom route tables.
2. **Security & Compute Hardening**: Ubuntu 24.04 LTS compute node with strict **IMDSv2** enforcement (`http_tokens = "required"`, `http_put_response_hop_limit = 1`), completely mitigating Server-Side Request Forgery (SSRF) credential extraction.
3. **Container Delivery & Storage**: Elastic Container Registry (ECR) repositories with lifecycle policies, storing multi-stage production images built via GitHub Actions Buildx.
4. **Data Persistence**: Isolated PostgreSQL 16 Alpine container backed by Docker named volumes, ensuring state survives host rebuilds and zero-downtime container swaps.

---

## 📂 Enterprise Monorepo Structure

```text
zeetafin-platform/
├── .github/                           # CI/CD Workflows & Repository Policies
│   ├── workflows/
│   │   ├── ci-backend.yml             # NestJS lint, unit tests, build validation on PR
│   │   ├── ci-frontend.yml            # Next.js lint, type check, standalone build on PR
│   │   ├── ci-infra.yml               # Terraform fmt, validate, tflint, security audit
│   │   └── cd-deploy.yml              # ECR build & push, EC2 SSH deploy trigger
│   └── pull_request_template.md       # Enterprise PR checklist (lint, tests, security)
│
├── apps/                              # Application Microservices
│   ├── backend/                       # NestJS Core ERP API + multi-stage Dockerfile
│   └── frontend/                      # Next.js 14 Web Portal + standalone Dockerfile
│
├── infra/                             # Infrastructure as Code & Config
│   ├── terraform/                     # bootstrap/ (remote state), modules/, environments/prod/
│   └── ansible/                       # Configuration management (ansible.cfg, inventory, roles)
│
├── deploy/                            # Runtime Operations & Ops
│   ├── docker-compose.yml             # Local developer environment
│   ├── docker-compose.prod.yml        # Production runtime stack
│   ├── env/                           # Sanitized .env.example templates
│   └── scripts/                       # deploy.sh, rollback.sh, healthcheck.sh
│
├── docs/                              # Architecture, Runbooks & Articles
│   ├── architecture/                  # System & CI/CD topology diagrams
│   ├── runbooks/                      # disaster-recovery.md, secret-rotation.md
│   └── articles/                      # Complete 12-part technical writing portfolio
│
├── Makefile                           # Developer ergonomics (make dev, make test, make deploy)
├── .gitignore                         # Universal enterprise gitignore
└── README.md                          # Executive recruiter showcase & platform overview
```

---

## ⚡ Continuous Integration & Deployment (CI/CD)

The platform implements automated validation and deployment pipelines using GitHub Actions:

```text
[Developer Push / Pull Request]
        │
        ├──► PR Opened ──► Fast CI Gates (ci-backend.yml, ci-frontend.yml, ci-infra.yml)
        │                   • TypeScript build & lint checks
        │                   • Dockerfile syntax & multi-stage build tests
        │                   • Terraform format & validation
        │
        └──► Merge to main ──► CD Delivery Pipeline (cd-deploy.yml)
                              • Authenticate with AWS via least-privilege IAM bot
                              • Build multi-stage images with layer caching (Buildx)
                              • Push versioned tags (Git SHA + latest) to Amazon ECR
                              • SSH into EC2 host to trigger atomic container swap
                              • Execute dual-vantage healthcheck probe
```

### Production Deployment & Rollback Ergonomics
* **Zero-Downtime Deployment**: [`deploy/scripts/deploy.sh`](deploy/scripts/deploy.sh) pulls latest images, performs atomic container recreations, runs container health probes, and prunes obsolete dangling layers.
* **Instant Rollback Engine**: [`deploy/scripts/rollback.sh`](deploy/scripts/rollback.sh) provides instant, single-command reversion to any previous Git SHA image tag if healthchecks fail.

---

## 📚 Technical Writing Portfolio (12-Part Engineering Series)

This repository serves as an enterprise reference implementation. Every design decision, security hardening gate, and automation script is thoroughly documented in our 12-part engineering deep-dive series located in [`docs/articles/`](docs/articles/):

| Part | Title | Focus Area |
| :--- | :--- | :--- |
| **01** | [AWS VPC Infrastructure with Terraform](docs/articles/01-aws-vpc-infrastructure-terraform.md) | VPC, CIDR architecture, IGW, Route Tables |
| **02** | [EC2 IAM & IMDSv2 Hardening](docs/articles/02-ec2-iam-imdsv2-hardening.md) | IMDSv2 enforcement, Security Groups, IAM roles |
| **03** | [Ansible Automation for Docker](docs/articles/03-ansible-automation-docker.md) | Host provisioning, package locks, Docker CE |
| **04** | [Idempotency Testing & Troubleshooting](docs/articles/04-idempotency-testing-troubleshooting.md) | Zero-drift verification, idempotency validation |
| **05** | [Enterprise App Architecture & Docker Overview](docs/articles/05-enterprise-app-architecture-docker-overview.md) | Microservices topology, multi-tier decoupling |
| **06** | [NestJS Backend Multi-Stage Docker Build](docs/articles/06-nestjs-backend-multi-stage-docker-build.md) | Build caching, non-root users, image optimization |
| **07** | [Next.js Standalone Containerization](docs/articles/07-nextjs-frontend-standalone-containerization.md) | Standalone output, minimal Alpine runner |
| **08** | [Docker Compose Orchestration & ECR Push](docs/articles/08-docker-compose-orchestration-and-ecr-push.md) | Multi-container networking, healthchecks |
| **09** | [AWS IAM & ECR Security](docs/articles/09-aws-iam-ecr-github-secrets-security.md) | Least-privilege IAM bot users, GitHub Secrets |
| **10** | [GitHub Actions CI/CD Pipeline Architecture](docs/articles/10-github-actions-ci-cd-workflow-architecture.md) | Workflow triggers, Buildx caching, concurrency |
| **11** | [EC2 Remote Deployment Engine Automation](docs/articles/11-ec2-remote-deployment-engine-automation.md) | Atomic zero-downtime swaps, container health |
| **12** | [End-to-End Verification & Observability](docs/articles/12-end-to-end-verification-observability-troubleshooting.md) | Smoke testing, failure recovery, observability |

---

## 🛠️ SRE Operational Runbooks

Standard Operating Procedures (SOPs) for site reliability and enterprise maintenance:
* 📖 [**Disaster Recovery Runbook**](docs/runbooks/disaster-recovery.md): Complete instructions for re-provisioning the compute host with Terraform, configuring with Ansible, and restoring database state from S3 snapshots.
* 🔐 [**Secret Rotation Runbook**](docs/runbooks/secret-rotation.md): Step-by-step procedures for zero-downtime rotation of IAM credentials, database passwords, and JWT secret keys.

---

## 🚀 Quickstart & Developer Ergonomics

A root `Makefile` provides standardized commands for development and operational lifecycle management:

```bash
# Clone the repository
git clone https://github.com/Devzane/zeetafin-platform.git
cd zeetafin-platform

# View all available developer commands
make help

# Start local full-stack development environment (NestJS + Next.js + PostgreSQL)
make dev

# Run application test suites and typechecks
make test

# Verify Terraform formatting across all infrastructure modules
make lint
```

---

## 🛡️ License & Attributions

Developed as part of the Vectra Automation engineering initiative. Designed as a production reference blueprint for cloud-native enterprise application delivery.
