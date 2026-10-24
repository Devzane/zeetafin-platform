---
title: "End-to-End Pipeline Verification, Health Probes, and Failure Recovery"
subtitle: "Part 12 of the Production DevOps Series: External Smoke Tests, Container Health Probes, Rollback Playbooks, and Production Retrospective"
tags: ["devops", "observability", "troubleshooting", "site-reliability", "cicd", "cloud"]
series: "Hands-On Cloud DevOps Engineering: Zero to Production"
part: 12
canonical_url: ""
cover_image: ""
---

# End-to-End Pipeline Verification, Health Probes, and Failure Recovery

A green checkmark in a GitHub Actions workflow does not guarantee your users are experiencing a working application. A container may report "running" while throwing uncaught exceptions on HTTP requests, or a security group may block traffic from the internet while allowing loopback curl tests to succeed.

In this twelfth and final part of our DevOps engineering series, we establish comprehensive verification across both internal and external vantage points for **ZeetaFin ERP**. We simulate real-world production outages, document emergency rollback protocols, and conclude with an architectural review of our complete multi-phase cloud pipeline.

---

## 1. Multi-Tier Verification Architecture

True continuous verification requires testing from two distinct network perspectives:

```text
 [ Vantage 1: Internal Host Probes (deploy.sh & healthcheck.sh) ]
   • Executed directly on EC2 host via loopback interface (127.0.0.1)
   • Probes:
     - PostgreSQL socket: pg_isready -U postgres -d zeetafin
     - Backend Swagger API: http://127.0.0.1:3001/api/docs
     - Frontend SSR: http://127.0.0.1:3000/
   • Purpose: Verifies processes are running and listening on local ports.
                            │
                            ▼
 [ Vantage 2: External Public Probes (GitHub Actions Runner) ]
   • Executed from external runner over the public internet
   • Probes:
     - External Web UI: http://${EC2_HOST}:3000
   • Purpose: Verifies AWS Internet Gateways, Route Tables, and Security Groups.
```

---

## 2. Implementing the Dedicated Health Prober (`scripts/healthcheck.sh`)

Create a modular prober script on the EC2 host to validate endpoint HTTP status codes:

```bash
#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-127.0.0.1}"
BACKEND_URL="http://${HOST}:3001/api/docs"
FRONTEND_URL="http://${HOST}:3000/"

echo "Probing ZeetaFin ERP endpoints on host: ${HOST}..."

# 1. Test Backend REST API Gateway
echo -n "Checking Backend (${BACKEND_URL})... "
HTTP_CODE_BACKEND=$(curl -s -o /dev/null -w "%{http_code}" "${BACKEND_URL}" || echo "000")
if [ "${HTTP_CODE_BACKEND}" -eq 200 ] || [ "${HTTP_CODE_BACKEND}" -eq 301 ] || [ "${HTTP_CODE_BACKEND}" -eq 302 ]; then
  echo "OK (HTTP ${HTTP_CODE_BACKEND})"
else
  echo "FAILED (HTTP ${HTTP_CODE_BACKEND})"
  exit 1
fi

# 2. Test Frontend Next.js SSR Web UI
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
```

---

## 3. External Smoke Testing in GitHub Actions

In `.github/workflows/deploy.yml`, Job 2 concludes by executing an external smoke check directly from the GitHub runner:

```yaml
- name: Automated External Availability Smoke Check
  run: |
    echo "Performing external health check against deployed application..."
    MAX_RETRIES=15
    WAIT_TIME=5
    SUCCESS=0

    for i in $(seq 1 $MAX_RETRIES); do
      echo "Attempt $i: Checking http://${{ secrets.EC2_HOST }}:3000..."
      if curl -s -f -m 10 "http://${{ secrets.EC2_HOST }}:3000" > /dev/null; then
        echo "Frontend is responding successfully on http://${{ secrets.EC2_HOST }}:3000!"
        SUCCESS=1
        break
      fi
      echo "Frontend not ready yet, sleeping ${WAIT_TIME}s..."
      sleep $WAIT_TIME
    done

    if [ $SUCCESS -ne 1 ]; then
      echo "Frontend probe failed. Verify Security Group ingress rule for port 3000."
      exit 1
    fi
```

If the web page does not respond over the public internet, the pipeline marks the deployment failed, preventing broken releases from going unnoticed.

---

## 4. Production Triage: The 5 Most Common Failure Modes

When automated deployments fail in production, use this triage matrix to diagnose and resolve:

| Error Symptom | Root Cause | Resolution |
| :--- | :--- | :--- |
| **`Permission denied (publickey)` over SSH** | Ephemeral runner key does not match `~/.ssh/authorized_keys` on EC2, or file permissions on `~/.ssh/deploy_key` are too open. | Ensure the key stored in `EC2_SSH_KEY` matches the public key in `aws_key_pair.main`. Verify `chmod 600 ~/.ssh/deploy_key`. |
| **`Error response from daemon: login attempt to https://... failed with status: 400 Bad Request`** | Amazon ECR authorization token expired. Tokens issued by `aws ecr get-login-password` expire after 12 hours. | Re-run `aws ecr get-login-password` immediately before the pull step in `deploy.sh`. |
| **`bind: address already in use`** | A previously crashed container or unmanaged process is occupying port `3000`, `3001`, or `5432`. | Run `docker compose -f docker-compose.prod.yml down` and check `sudo lsof -i :3000` on the EC2 host. |
| **`Container exited with code 137` (OOMKilled)** | Node.js process exceeded available memory on smaller EC2 instances (`t2.micro` or `t3.micro`). | Upgrade compute instance type to `t3.medium`, or enable swap space on the host. |
| **Database connection refused during startup** | NestJS attempted queries before PostgreSQL finished socket initialization. | Verify `depends_on: db: condition: service_healthy` is present in `docker-compose.prod.yml`. |

---

## 5. Emergency Rollback Playbook

When an unexpected regression slips past CI and impacts production, follow this rapid rollback procedure:

### Option A: Immediate GitHub Actions UI Rollback

1. Navigate to **Actions ➔ ZeetaFin CI/CD Pipeline ➔ Run workflow**.
2. Under **Optional container image tag override**, enter the Git commit SHA of the last known healthy release (e.g. `e4f5a6b`).
3. Click **Run workflow**. The pipeline pulls the verified older image and redeploys it within 60 seconds without altering the database volume.

### Option B: Terminal Direct Rollback on Host

If GitHub Actions is unreachable or degraded, connect directly to the host:

```bash
ssh -i ~/.ssh/zeetafin-key ubuntu@<EC2_IP>

cd /home/ubuntu/zeetafin-app

# 1. Update the image tag in .env to the previous SHA
sed -i 's/^IMAGE_TAG=.*/IMAGE_TAG=e4f5a6b/' .env

# 2. Re-pull and recreate containers
docker compose -f docker-compose.prod.yml pull
docker compose -f docker-compose.prod.yml up -d --remove-orphans --force-recreate

# 3. Verify health
./scripts/healthcheck.sh
```

---

## 6. Complete Series Architectural Retrospective

Over this 12-part technical journey, we have designed, provisioned, hardened, containerized, and automated an enterprise-grade cloud deployment:

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      The Complete DevOps Stack                         │
 ├────────────────────────────────────────────────────────────────────────┤
 │ Phase 1: Infrastructure as Code & Host Configuration                   │
 │   • Modular Terraform (VPC, Subnet, Route Tables, Internet Gateway)    │
 │   • Hardened Ubuntu 24.04 LTS with IMDSv2 (SSRF protection)           │
 │   • Modular Ansible Role automating Docker CE & Systemd configuration  │
 │   • Zero-Drift Idempotency Verification                                │
 ├────────────────────────────────────────────────────────────────────────┤
 │ Phase 2: Application Containerization & Registry Distribution          │
 │   • Multi-stage Docker build for NestJS API (369 MB, non-root user)    │
 │   • Standalone Docker build for Next.js 14 Frontend (224 MB)           │
 │   • Local 3-tier orchestration with PostgreSQL 16 & health probes      │
 │   • Amazon ECR distribution with vulnerability scanning on push        │
 ├────────────────────────────────────────────────────────────────────────┤
 │ Phase 3: Continuous Integration & Automated Continuous Deployment      │
 │   • Least-privilege IAM bot user & encrypted GitHub Secrets            │
 │   • Declarative GitHub Actions CI/CD with Buildx layer caching         │
 │   • Remote EC2 deployment engine with zero-collision container swap    │
 │   • Multi-tier health probing and rapid rollback playbooks             │
 └────────────────────────────────────────────────────────────────────────┘
```

By adhering to infrastructure as code, non-root container isolation, least-privilege cloud IAM, and automated verification, you have built a production-grade cloud platform capable of safely supporting real-world enterprise applications.

---

## Series Navigation

* ⏪ [Part 1: Building an Isolated AWS VPC and Network Foundation with Terraform](../../phase1/articles/01-aws-vpc-infrastructure-terraform.md)
* ⏪ [Part 5: Multi-Tier Application Architecture: Designing a Production Containerization Strategy](../../phase2/articles/01-enterprise-app-architecture-docker-overview.md)
* ⏪ [Part 9: Zero-Trust CI/CD Security: Least-Privilege IAM, Amazon ECR, and Hardened GitHub Secrets](./01-aws-iam-ecr-github-secrets-security.md)
* ⏪ [Part 11: Production Deployment Automation: Remote EC2 Orchestration and Zero-Downtime Rollouts](./03-ec2-remote-deployment-engine-automation.md)
* 📑 [Master Series Index & Publication Roadmap](../../SERIES-ROADMAP.md)
