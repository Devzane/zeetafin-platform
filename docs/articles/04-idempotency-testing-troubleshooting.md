---
title: "Production Verification: Ansible Idempotency Testing, Failure Recovery, and Infrastructure Auditing"
subtitle: "Part 4 of the Production DevOps Series: Proving Zero Configuration Drift, Hardening Release Automations, and Safe Teardown Patterns"
tags: ["devops", "ansible", "terraform", "idempotency", "site-reliability", "testing"]
series: "Hands-On Cloud DevOps Engineering: Zero to Production"
part: 4
canonical_url: ""
cover_image: ""
---

# Production Verification: Ansible Idempotency Testing, Failure Recovery, and Infrastructure Auditing

A deployment that works only once is not automation—it is a lucky script. In production Site Reliability Engineering (SRE), the ultimate mark of robust infrastructure automation is **idempotency**: the ability to apply an operation repeatedly with the guarantee that subsequent runs produce identical results without introducing side effects or unintended modifications.

In this concluding installment of Phase 1, we put our Terraform and Ansible implementations through rigorous production validation. We conduct second-pass idempotency testing, construct an automated verification pipeline, simulate real-world failure modes, and execute clean, zero-leak resource teardowns.

---

## 1. What Idempotency Means in Practice

In Ansible, every task declares a *desired state* rather than an imperative action:

```text
 ┌─────────────────────────────────────────────────────────────┐
 │ First Playbook Run (System in Raw State)                    │
 │  • GPG Key: Missing          ──► Downloaded (changed=1)     │
 │  • Docker Repo: Unregistered ──► Added      (changed=1)     │
 │  • Docker CE: Not Installed  ──► Installed  (changed=1)     │
 └──────────────────────────────┬──────────────────────────────┘
                                │
                                ▼
 ┌─────────────────────────────────────────────────────────────┐
 │ Second Playbook Run (System in Desired State)               │
 │  • GPG Key: Already exists   ──► Skipped    (changed=0, ok) │
 │  • Docker Repo: Already pres ──► Skipped    (changed=0, ok) │
 │  • Docker CE: Same version   ──► Skipped    (changed=0, ok) │
 └─────────────────────────────────────────────────────────────┘
```

If your configuration is truly idempotent, re-running the playbook against a converged host should report `changed=0` (excluding explicit verification commands that trigger external container runs). If a playbook repeatedly shows `changed > 0` on identical runs, your tasks suffer from **configuration drift**.

---

## 2. Conducting the Idempotency Test

Execute a back-to-back run of the Ansible playbook:

```bash
# Run 1: Converge the system to desired state
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/site.yml

# Run 2: Test for idempotency (Must yield changed=0 or changed=1 for smoke test only)
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/site.yml
```

### Inspecting Task-Level Drift

In our Docker role, notice how tasks specify `force: false` and `state: present`:

```yaml
# Idempotent: Skips download if file exists
- name: Download Docker official GPG key
  ansible.builtin.get_url:
    url: https://download.docker.com/linux/ubuntu/gpg
    dest: /etc/apt/keyrings/docker.asc
    mode: "0644"
    force: false

# Idempotent: Evaluates repository string and skips if already present
- name: Add Docker apt repository
  ansible.builtin.apt_repository:
    repo: "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu {{ ansible_distribution_release }} stable"
    state: present
    filename: docker
```

On the second run, Ansible checks the destination file and repository list, notices that the target state matches reality, and marks both tasks `ok` without modifying disk.

---

## 3. Building an Automated End-to-End Orchestrator

Rather than running disparate manual commands, wrap Phase 1 execution into a reproducible bash release script (`deploy-phase1.sh`):

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "======================================================"
echo " Starting Phase 1 Automated Infrastructure Pipeline"
echo "======================================================"

# 1. Terraform Initialization & Plan
echo "--> Initializing Terraform..."
terraform init -input=false

echo "--> Validating Terraform syntax..."
terraform validate

echo "--> Generating infrastructure plan..."
terraform plan -out=tfplan -input=false

# 2. Terraform Provisioning
echo "--> Applying infrastructure plan..."
terraform apply -input=false tfplan
rm -f tfplan

# 3. Export Provisioned Target
TARGET_IP=$(terraform output -raw public_ip)
echo "--> Compute host provisioned at IP: ${TARGET_IP}"

# 4. Ansible Configuration
echo "--> Waiting for instance connectivity..."
ansible -i ansible/inventory/hosts.ini -m ping docker_hosts

echo "--> Executing Ansible Docker host configuration..."
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/site.yml

# 5. Remote Smoke Verification
echo "--> Running post-deployment health check..."
ssh -i ~/.ssh/zeetafin-key -o StrictHostKeyChecking=no ubuntu@"${TARGET_IP}" \
  "docker info --format '{{.ServerVersion}}' && echo 'Docker Daemon is Healthy!'"

echo "======================================================"
echo " Phase 1 Infrastructure Successfully Provisioned & Verified"
echo "======================================================"
```

Make the script executable:

```bash
chmod +x deploy-phase1.sh
```

---

## 4. Triage Guide: Common Production Failure Modes

During automated infrastructure provisioning, real-world networks fail in predictable ways. Here is how to diagnose and recover:

### 1. The dpkg Lock Freeze

* **Symptom:** Ansible hangs on `apt` tasks for 10+ minutes or throws:
  ```text
  Could not get lock /var/lib/dpkg/lock-frontend
  ```
* **Root Cause:** AWS Ubuntu images execute `unattended-upgrades` on first boot.
* **Resolution:** Ensure your playbook checks `cloud-init status --wait` and queries `fuser` before invoking `ansible.builtin.apt`:
  ```bash
  ssh ubuntu@<IP> "sudo ps aux | grep -i apt"
  ```

### 2. The SSH Handshake Timeout

* **Symptom:** `ansible.builtin.wait_for_connection` times out after 300 seconds.
* **Triage Steps:**
  1. Check the AWS Security Group: Is your public IP allowed on port 22?
  2. Inspect the Route Table: Does the public subnet have `0.0.0.0/0 -> igw-xxxx`?
  3. Verify Key Permissions: Run `chmod 400 ~/.ssh/zeetafin-key`.

### 3. Terraform State Locks

* **Symptom:**
  ```text
  Error: Error acquiring the state lock: ConditionalCheckFailedException
  ```
* **Root Cause:** A prior run was killed abnormally (e.g., terminal closed during apply).
* **Resolution:** Inspect running processes. If confirmed dead, release the lock cleanly using the Lock ID:
  ```bash
  terraform force-unlock <LOCK_ID>
  ```

---

## 5. Controlled Teardown & Drift Auditing

Cloud hygiene requires that non-production environments be torn down cleanly to prevent orphaned cloud resources, bill leakage, and state drift.

### Auditing Before Teardown

Before destroying infrastructure, verify that no unmanaged resources (such as manually created EBS snapshots, custom security group rules, or dangling volumes) were attached outside Terraform:

```bash
# Check if Terraform detects any out-of-band state changes
terraform plan -detailed-exitcode || true
```

### Executing Safe Teardown

```bash
# 1. Preview resources marked for deletion
terraform plan -destroy -out=destroy.tfplan

# 2. Execute deletion
terraform apply destroy.tfplan
rm -f destroy.tfplan

# 3. Clean local dynamic inventory to prevent stale connections
rm -f ansible/inventory/hosts.ini
```

---

## 6. Senior Engineering Architectural Review

Before transitioning to containerization in Phase 2, review the core architectural decisions implemented in Phase 1:

| Domain | Architecture Choice | Trade-Off / Justification |
| :--- | :--- | :--- |
| **Networking** | Custom `/16` VPC + single `/24` AZ Subnet | Simple network topology for single-host setup; easily scales to multi-AZ private subnets with NAT gateways. |
| **Compute** | Dynamic Canonical AMI filter | Prevents manual AMI lookups; guarantees latest verified kernel and LTS security patches. |
| **Security** | IMDSv2 mandatory (`hop_limit = 1`) | Hardens host against SSRF credential compromise without requiring network-level proxies. |
| **Configuration** | Dynamic Inventory via Terraform | Eliminates manual copy-pasting of IP addresses between provisioning and configuration tiers. |
| **Packaging** | Official Docker CE Upstream Repo | Provides modern Docker plugins (`buildx`, `compose-plugin`) not packaged in Ubuntu's base repos. |

---

## Phase 1 Complete!

You now possess a completely codified, repeatable, secure cloud compute foundation.

👉 **Continue to Phase 2:** [Part 5: Enterprise Application Architecture: Multi-Tier Containerization Strategy](../../phase2/articles/01-enterprise-app-architecture-docker-overview.md)
