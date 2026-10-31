# ZeetaFin Enterprise Cloud Architecture & Engineering Specifications

This directory contains the visual system architecture blueprints, network diagrams, and infrastructure verification artifacts for the ZeetaFin Cloud Platform.

---

## 1. Cloud & Network Topology

![System Architecture](architecture.png)

### Key Architectural Characteristics
* **Virtual Private Cloud (VPC)**: Isolated network space partitioned into deterministic public and private CIDR blocks.
* **Security Isolation**: Security Groups configured with strict ingress rules (SSH restricted to admin IP, HTTP/HTTPS for application traffic).
* **Compute Layer**: Hardened Ubuntu 24.04 LTS EC2 instance with IMDSv2 strictly enforced (tokens required, hop-limit=1) preventing SSRF token exfiltration.
* **Identity & Access Management (IAM)**: EC2 Instance Profile with dedicated least-privilege IAM roles for Amazon ECR image authorization.

---

## 2. CI/CD Delivery Pipeline Flow

```text
[Developer Push / PR]
        │
        ▼
[GitHub Actions CI] ───► [Linting & Tests] ───► [Terraform Validate]
        │
     (Merge)
        ▼
[GitHub Actions CD] ───► [Docker Buildx (Multi-Stage)]
        │
        ▼
[Amazon ECR] ──────────► [Encrypted OCI Image Repository]
        │
    (SSH Deploy)
        ▼
[AWS EC2 Host] ────────► [deploy.sh Runner] ──► [Zero-Downtime Container Swap] ──► [Healthcheck Probe]
```

---

## 3. Infrastructure & Automation Verification Evidence

* **Terraform Provisioning**: [`terraform-apply.png`](terraform-apply.png)
* **EC2 Host Summary**: [`ec2-instance-summary.png`](ec2-instance-summary.png)
* **SSH Connectivity**: [`ssh-login.png`](ssh-login.png)
* **Ansible Configuration**: [`ansible-playbook-run.png`](ansible-playbook-run.png)
* **Ansible Idempotency Verification**: [`ansible-idempotency.png`](ansible-idempotency.png)
* **Docker Engine Readiness**: [`docker-verify.png`](docker-verify.png)

---

## 4. FinOps & Cloud Cost Optimization Analysis

* 💰 [**FinOps & Cost Optimization Breakdown**](cost-optimization-analysis.md): Complete engineering analysis detailing the architectural trade-offs, Zero-NAT Gateway topology, and gp3 storage strategy that reduced baseline cloud expenditure by **91.8%** ($347.45/mo to $28.48/mo).
