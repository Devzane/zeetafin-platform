## 🎯 Pull Request Overview

### Summary of Changes
<!-- Provide a concise description of what this change accomplishes and why it is needed. -->

### Architectural Domain
- [ ] `infra/` — Terraform Infrastructure as Code / S3 Backend / Modules
- [ ] `infra/ansible/` — Host Hardening / Configuration Management
- [ ] `apps/backend/` — NestJS ERP Core Service
- [ ] `apps/frontend/` — Next.js 14 Enterprise Portal
- [ ] `deploy/` — Docker Compose stacks / Runtime operational scripts
- [ ] `.github/` — CI/CD automation & pipeline definitions
- [ ] `docs/` — Architecture specifications / Runbooks / Technical articles

---

## 🛡️ Enterprise Engineering Checklist

### 1. Security & Secrets Hygiene
- [ ] No hardcoded passwords, IAM keys, or API tokens are present in diffs.
- [ ] All environment variables are documented in sanitized `.env.example` templates.
- [ ] EC2 security group rules follow principle of least privilege (no unbounded `0.0.0.0/0` SSH).

### 2. Code Quality & Modularity
- [ ] Code follows DRY principles with reusable components/modules.
- [ ] Functions and services include explanatory documentation comments.
- [ ] Multi-stage Dockerfiles leverage layer caching and non-root user execution.

### 3. Verification & Testing
- [ ] Local build verified (`npm run build` or `terraform validate`).
- [ ] Container build verified locally via Docker.
- [ ] End-to-end integration verified against local database.

### 4. Operational Readiness & Rollback
- [ ] Zero-downtime deployment compatibility verified.
- [ ] Rollback strategy defined: target container tag or state revert command specified below.

> **Rollback Plan:**
> In case of unexpected runtime failure, execute:
> `./deploy/scripts/rollback.sh <PREVIOUS_IMAGE_TAG>`
