# 🛠️ Engineering Knowledge Base & Build-in-Public Journal

> A living, chronological record of technical discoveries, architecture decisions, troubleshooting investigations, and practical lessons from my journey transitioning from Mechatronics Engineering into Cloud, DevOps, and Platform Engineering.

---

## 🧭 About This Repository & My Engineering Direction

I am a **Mechatronics Engineering student** transitioning into **Cloud Engineering, DevOps, Platform Engineering, and Software Systems Architecture**. 

Coming from a multidisciplinary background combining mechanical systems, electronics, and low-level firmware, I approach cloud and software infrastructure with an emphasis on **first principles, systems-level debugging, operational resilience, and verifiable truth**.

### The Core Philosophy of This Journal
Most portfolio showcases only present finished, polished projects where everything works seamlessly. Real engineering is the opposite: it involves architectural compromises, edge-case failures, reading through terminal traces, and debugging unhandled environmental boundaries.

This central knowledge base serves as my **single source of truth** and public build log:
- **What I am actively building** across distributed systems, cloud infrastructure, and software delivery pipelines.
- **What actually failed and why**, documenting the exact mechanisms behind bugs and configuration breakdowns.
- **How I investigate problems**, tracking my hypotheses, tests, failed attempts, and working resolutions.
- **Architectural decisions & trade-offs**, recording the exact justifications for why one approach was chosen over another.
- **True, unmanufactured progress**, strictly separating activity (like reading documentation) from tangible engineering achievement (like verifying an automated deployment).

---

## 📑 Table of Contents

1. [Core Areas of Focus](#-core-areas-of-focus)
2. [A. Daily Engineering Journal](#a-daily-engineering-journal)
3. [B. Technical Insights & Discoveries](#b-technical-insights--discoveries)
4. [C. Challenges & Troubleshooting Log](#c-challenges--troubleshooting-log)
5. [D. Engineering Decision Records (EDRs)](#d-engineering-decision-records-edrs)
6. [E. Daily Achievements Tracker](#e-daily-achievements-tracker)
7. [F. Lessons & Engineering Reflections](#f-lessons--engineering-reflections)
8. [G. Build-in-Public Content Archive](#g-build-in-public-content-archive)
9. [Standardized Templates](#-standardized-templates)
   - [Daily Journal Entry Template](#1-daily-journal-entry-template)
   - [Technical Insight Template](#2-technical-insight-template)
   - [Troubleshooting Log Template](#3-troubleshooting-log-template)
   - [Engineering Decision Record Template](#4-engineering-decision-record-template)
   - [Single-Topic X (Twitter) Post Template](#5-single-topic-x-twitter-post-template)
   - [Single-Topic LinkedIn Post Template](#6-single-topic-linkedin-post-template)
10. [Repository Scaling & Maintenance Guidelines](#-repository-scaling--maintenance-guidelines)

---

## 🎯 Core Areas of Focus

```text
┌────────────────────────────────────────────────────────────────────────┐
│                      Primary Engineering Competencies                  │
├──────────────────────┬────────────────────────┬────────────────────────┤
│ ☁️ Cloud & IaC       │ 📦 Containers & Linux  │ 🔄 CI/CD & Delivery   │
│ • AWS (VPC, EC2, SG) │ • Docker & Compose     │ • GitHub Actions       │
│ • Terraform (Remote) │ • Multi-Stage Alpine   │ • Just-in-Time Access  │
│ • Ansible Automation │ • IMDSv2 Hardening     │ • Zero-Downtime Swaps  │
│ • FinOps Architecture│ • Linux Process Models │ • Automated Rollbacks  │
└──────────────────────┴────────────────────────┴────────────────────────┘
```

---

## A. Daily Engineering Journal

### Session: 2026-11-02 — ZeetaFin AWS Cloud Infrastructure & Automated CI/CD Engine

* **Project**: ZeetaFin Platform (Cloud-Native Enterprise Financial ERP)
* **Specific Tasks Undertaken**:
  1. Resolved GitHub Actions Language Server rate-limiting / action resolution warnings on `docker/build-push-action`.
  2. Evaluated perimeter security trade-offs for SSH access vs. AWS Systems Manager (SSM) vs. Dynamic Ephemeral Security Group Whitelisting.
  3. Corrected Terraform module path traversal bugs for generated Ansible inventory templates.
  4. Configured production S3 remote state backend with native S3 state locking.
  5. Refactored hardcoded lab slug naming conventions across Terraform, Ansible, and Runbooks to standard enterprise naming (`zeetafin-prod-*`).
  6. Provisioned live AWS VPC, Subnet, Route Table, Security Group, Key Pair, and EC2 instance via Terraform.
  7. Debugged non-interactive SSH key authentication failures (`Permission denied (publickey)`) during automated deployment rollout.
  8. Resolved Docker Compose image resolution bugs (`invalid reference format`) in remote SSH rollout scripts.
* **What Was Actually Accomplished**:
  - Successfully provisioned complete AWS networking and compute infrastructure via Terraform into `us-east-1`.
  - Upgraded build pipeline to `docker/build-push-action@v6`.
  - Engineered an automated Just-In-Time (JIT) runner IP whitelisting mechanism in GitHub Actions that temporarily opens port 22 only to the runner's `/32` IP and guarantees revocation via `if: always()`.
  - Standardized all infrastructure naming from legacy placeholders to `zeetafin-prod-*`.
  - Identified and resolved a passphrase-protected SSH key deadlock in non-interactive CI/CD runners.
  - Hardened Docker Compose deployment pipeline with dynamic AWS STS Account ID resolution and direct runner-to-host ECR authentication piping.
* **Technologies & Tools Used**: `Terraform 1.10+`, `AWS EC2`, `AWS VPC`, `Amazon ECR`, `AWS Security Groups`, `AWS IAM`, `GitHub Actions`, `Docker`, `Docker Compose`, `Bash`, `PowerShell`, `OpenSSH`, `WSL (Ubuntu)`.
* **Important Discoveries**:
  - Non-interactive SSH clients (like GitHub Actions runners) cannot prompt for key passphrases; they silently reject passphrase-encrypted private keys with `Permission denied (publickey)`.
  - Passing secrets or variables inside unquoted bash here-docs (`<< EOF`) allows runner-side variable interpolation before sending commands to the remote server, whereas quoted here-docs (`<< 'EOF'`) prevent it.
  - Windows clipboard / text handling often introduces carriage returns (`\r\n`) into multiline GitHub Secrets, which breaks OpenSSH parsing on Linux runners unless stripped with `tr -d '\r'`.
* **Problems Encountered & How They Were Approached**:
  - *Problem 1*: Port 22 security exposure vs. dynamic GitHub Actions IP addresses. Approached by analyzing three architectural options (0.0.0.0/0, SSM Session Manager, and Ephemeral Whitelisting), selecting ephemeral whitelisting for minimal friction and robust security.
  - *Problem 2*: Relative path depth mismatch in Terraform `templatefile` function (`../../ansible` vs `../../../ansible`). Traced directory tree depth from `infra/terraform/environments/prod` back to `infra/` to fix the reference.
  - *Problem 3*: SSH Public Key denial in CI/CD. Discovered the private key was generated inside WSL with a passphrase, making it inaccessible from pure Windows and unusable in automated runners. Removed passphrase via `ssh-keygen -p` and sanitized secret storage.
  - *Problem 4*: Docker `invalid reference format` during `docker compose pull`. Root-caused to an empty `ECR_REGISTRY` variable resulting in `/zeetafin-backend`. Solved by computing the registry host dynamically via AWS STS on the runner.
* **Current Status**: Infrastructure provisioned; CI/CD pipeline hardened with dynamic JIT whitelisting and dynamic ECR authentication piping.
* **Incomplete / Next Steps**:
  - Run initial end-to-end container rollout verification across backend, frontend, and PostgreSQL services.
  - Verify container health check probe responses on external ports 3000 and 3001.
  - Capture deployment evidence screenshots for documentation portfolio.

---

## B. Technical Insights & Discoveries

### Insight 01: Ephemeral Just-in-Time (JIT) IP Whitelisting for Non-Static CI/CD Runners
* **Problem / Context**: Public cloud virtual machines (EC2) require administrative access for software rollouts, but leaving SSH (port 22) open to the internet (`0.0.0.0/0`) exposes the machine to continuous brute-force attacks and port scanning. Conversely, GitHub-hosted runners (`ubuntu-latest`) use dynamic IP pools that change on every run, preventing static IP whitelisting.
* **Technical Explanation**:
  Rather than keeping port 22 open or setting up a full VPN/Bastion host for a small-scale workload, the CI/CD runner can self-authorize its ephemeral IP at the beginning of the deployment job and revoke it immediately upon completion.
* **Practical Implementation**:
  ```yaml
  # 1. Discover dynamic runner IP and authorize in AWS Security Group
  - name: "Authorize GitHub Runner IP in Security Group"
    id: ip-whitelist
    run: |
      RUNNER_IP=$(curl -s https://api.ipify.org)
      echo "runner_ip=${RUNNER_IP}" >> "$GITHUB_OUTPUT"
      aws ec2 authorize-security-group-ingress \
        --group-id "${{ secrets.EC2_SG_ID }}" \
        --protocol tcp \
        --port 22 \
        --cidr "${RUNNER_IP}/32"

  # 2. Deploy over SSH ...

  # 3. Guaranteed teardown step (runs even if deployment crashes or is cancelled)
  - name: "Revoke GitHub Runner IP from Security Group"
    if: always()
    run: |
      if [ -n "${{ steps.ip-whitelist.outputs.runner_ip }}" ]; then
        aws ec2 revoke-security-group-ingress \
          --group-id "${{ secrets.EC2_SG_ID }}" \
          --protocol tcp \
          --port 22 \
          --cidr "${{ steps.ip-whitelist.outputs.runner_ip }}/32" || true
      fi
  ```
* **Why This Matters**: Provides least-privilege network access to public cloud infrastructure without requiring dedicated private network tunnels, NAT gateways, or persistent attack surfaces.

---

### Insight 02: Non-Interactive SSH Authentication & Key Passphrase Deadlocks
* **Problem / Context**: A developer can connect to a server via SSH from their local terminal without errors, but the exact same private key copied into GitHub Secrets fails with `Permission denied (publickey)` in CI/CD.
* **Technical Explanation**:
  SSH keys encrypted with a passphrase require a TTY (interactive terminal session) to prompt the user to decrypt the key with the passphrase. Automated CI/CD runners execute in non-interactive batch mode (`BatchMode=yes` or without an allocated pseudo-terminal). When OpenSSH encounters an encrypted key without an active TTY or SSH agent, it cannot prompt for a passphrase and immediately discards the identity file, causing authentication to fail.
* **How to Inspect and Fix**:
  Check if a key is encrypted:
  ```bash
  head -n 2 ~/.ssh/id_rsa
  # If it contains "Proc-Type: 4,ENCRYPTED" or was created with a passphrase, it is encrypted.
  ```
  Remove the passphrase in place without altering the public key:
  ```bash
  ssh-keygen -p -f ~/.ssh/zeetafin-deployer
  # Enter old passphrase, then press Enter twice for empty new passphrase.
  ```
* **Why This Matters**: Machine-to-machine automation requires unencrypted private keys protected by the CI/CD secret manager (e.g., GitHub Encrypted Secrets, AWS Secrets Manager), rather than user passphrases.

---

### Insight 03: Runner-to-Host ECR Token Piping (Decoupling Host Credentials)
* **Problem / Context**: When deploying Docker containers to an EC2 instance from private Amazon ECR, the host needs credentials to run `docker pull`. Storing long-lived AWS IAM access keys on the EC2 host introduces credential theft risks, while requiring AWS CLI on the host adds extra operational dependencies.
* **Technical Explanation**:
  The GitHub Actions runner already holds short-lived AWS credentials. The runner can invoke the AWS API to generate an ephemeral 12-hour Docker login token via `aws ecr get-login-password`, and pipe that token directly into `docker login` on the EC2 host over the SSH connection.
* **Practical Implementation**:
  ```bash
  # Executed on the runner:
  ECR_TOKEN=$(aws ecr get-login-password --region "$AWS_REGION")

  # Piped over SSH directly into the remote Docker daemon:
  ssh -i ~/.ssh/deploy_key ubuntu@$EC2_HOST << EOF
    echo "${ECR_TOKEN}" | docker login --username AWS --password-stdin "${ECR_REGISTRY}"
    docker compose pull
    docker compose up -d
  EOF
  ```
* **Why This Matters**: Eliminates the need to install the AWS CLI on the EC2 host, prevents saving long-lived credentials in `/home/ubuntu/.aws/credentials`, and centralizes authentication inside the CI/CD pipeline.

---

## C. Challenges & Troubleshooting Log

### Log Entry 01: SSH Non-Interactive Authentication Failure (`Permission denied (publickey)`)
* **Context**: GitHub Actions executing Job 2 (`deploy-to-ec2`) attempting to run `ssh -i ~/.ssh/deploy_key ubuntu@$EC2_HOST` to deploy updated Docker manifests.
* **Symptoms & Observations**:
  ```text
  Syncing production compose manifests and deployment scripts...
  ubuntu@100.56.254.58: Permission denied (publickey).
  Error: Process completed with exit code 255.
  ```
* **Initial Hypotheses**:
  1. The Security Group was blocking port 22.
  2. The public key on AWS EC2 (`~/.ssh/authorized_keys`) did not match the private key in GitHub Secrets.
  3. The secret had Windows CRLF line-ending corruption.
* **Investigations Performed**:
  - Checked Security Group logs: Port 22 whitelisting succeeded (the connection was accepted, not timed out).
  - Attempted to test the key locally via PowerShell: Got `Warning: Identity file not accessible: No such file or directory`.
  - Tested inside WSL: Connection succeeded immediately, but prompted for a passphrase!
* **Failed Approaches**:
  - Pasting raw key directly in PowerShell terminal (failed due to hidden CRLF and path resolution differences between Windows and WSL).
* **Root Cause**:
  The private key on the local machine was generated inside WSL with a passphrase. In WSL, the user typed the passphrase interactively. In GitHub Actions, the runner is non-interactive; unable to prompt for a passphrase, SSH discarded the key and reported `Permission denied (publickey)`.
* **Working Solution**:
  1. Removed the passphrase using `ssh-keygen -p -f ~/.ssh/zeetafin-deployer` (leaving the public key intact).
  2. Extracted the unencrypted private key from WSL: `cat ~/.ssh/zeetafin-deployer`.
  3. Sanitized the GitHub Actions write step using `tr -d '\r'` to eliminate Windows carriage returns:
     ```yaml
     echo "$SSH_PRIVATE_KEY" | tr -d '\r' > ~/.ssh/deploy_key
     ```
* **Lessons Learned**:
  Always verify whether private keys intended for CI/CD automation carry a passphrase. Non-interactive environments will not prompt; they fail immediately.

---

### Log Entry 02: Docker Pull Rejection (`invalid reference format`)
* **Context**: Executing `deploy.sh` on EC2 host via remote SSH session.
* **Symptoms & Observations**:
  ```text
  [INFO] Pulling updated Docker container images (tag: 26676b16874c02ff95b7431007f4900407fbe5cd)...
  Image /zeetafin-frontend:26676b16874c02ff95b7431007f4900407fbe5cd Pulling 
  Image /zeetafin-backend:26676b16874c02ff95b7431007f4900407fbe5cd Pulling 
  invalid reference format
  ```
* **Initial Hypotheses**:
  The Docker tag or image name contained illegal characters.
* **Investigations Performed**:
  Inspected the log line carefully: `Image /zeetafin-frontend:...`
  Noticed the missing registry host before the leading slash. In `docker-compose.prod.yml`, the image is declared as `${ECR_REGISTRY}/zeetafin-backend:${IMAGE_TAG}`. When `${ECR_REGISTRY}` is empty, the string collapses to `/zeetafin-backend:...`. Docker parser considers a repository name starting with a slash invalid.
* **Root Cause**:
  The upstream job output `${{ needs.build-and-push.outputs.ecr_registry }}` was not being passed or evaluated correctly into the SSH here-doc script, leaving the `ECR_REGISTRY` variable blank.
* **Working Solution**:
  1. Updated the GitHub Actions step to resolve the Account ID directly from AWS STS on the runner:
     ```bash
     ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
     ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
     ```
  2. Changed the SSH here-doc delimiter from quoted `'EOF'` to unquoted `EOF` so the local runner variables (`$ECR_REGISTRY`, `$IMAGE_TAG`) interpolate into the remote execution stream.
  3. Added assertion guards in `deploy.sh` to exit with a descriptive error if `ECR_REGISTRY` is empty.

---

## D. Engineering Decision Records (EDRs)

### EDR 01: Ingress Security — Ephemeral Security Group Whitelisting vs. AWS SSM vs. Open 0.0.0.0/0

* **Status**: Accepted
* **Context**:
  The ZeetaFin application stack runs on an Amazon EC2 instance that needs to receive updated deployment manifests and compose configurations from GitHub Actions runners on every release.
* **Options Considered**:
  1. *Leave Port 22 Open to 0.0.0.0/0*: Protect only with SSH key authentication.
  2. *AWS Systems Manager (SSM) Session Manager*: Eliminate port 22 completely and dispatch commands via `aws ssm send-command`.
  3. *Ephemeral Security Group Whitelisting (JIT Access)*: Restrict port 22 to the developer's personal IP by default; allow the GitHub runner to authorize its `/32` IP dynamically and revoke it immediately via `if: always()`.
* **Decision**:
  Option 3 (Ephemeral Security Group Whitelisting).
* **Justification**:
  - Option 1 is unacceptable for enterprise security posture because automated port scanners continually hammer open SSH ports.
  - Option 2 is architecturally clean, but SSM lacks a native `scp` file transfer mechanism. Copying `docker-compose.prod.yml` and deployment scripts over SSM requires pushing files to an intermediate S3 bucket or executing Git checkouts directly on the EC2 host.
  - Option 3 delivers strong security (zero persistent public exposure) while retaining the simplicity of native `scp` and `ssh` execution without adding external infrastructure dependencies.
* **Trade-offs & Limitations**:
  - If a runner process is abruptly terminated by GitHub infrastructure before the `if: always()` step executes, a single `/32` IP could remain whitelisted until the next deploy.
  - Requires the CI bot IAM user to possess `ec2:AuthorizeSecurityGroupIngress` and `ec2:RevokeSecurityGroupIngress` permissions.

---

### EDR 02: Remote State Locking — Native S3 Conditional Writes vs. DynamoDB Table

* **Status**: Accepted
* **Context**:
  Terraform state must be stored remotely in Amazon S3 to enable team collaboration and prevent local state loss. State locking is necessary to prevent simultaneous execution races.
* **Options Considered**:
  1. *S3 Bucket + DynamoDB Table*: The traditional Terraform approach on AWS.
  2. *Native S3 State Locking (`use_lockfile = true`)*: Terraform 1.10+ native capability using S3 conditional writes (`PutObject` with condition).
* **Decision**:
  Option 2 (Native S3 State Locking).
* **Justification**:
  Terraform 1.10 introduced support for native S3 conditional writes. This eliminates the need to provision, manage, and pay for an auxiliary AWS DynamoDB table solely for state lock records, reducing IaC complexity and AWS resource sprawl.
* **Trade-offs**:
  Requires Terraform CLI version `>= 1.10.0`. Older versions will fail to parse `use_lockfile = true`.

---

## E. Daily Achievements Tracker

```text
Taxonomy:
[COMPLETED]   - Verified and working in production/staging with supporting evidence.
[IN PROGRESS] - Actively being implemented or tested.
[FAILED/BLOCKED] - Attempted but hit a technical obstacle (documented in Troubleshooting).
[PLANNED]     - Scheduled for upcoming sessions.
```

### Milestone Log: November 2, 2026
* [COMPLETED] Upgraded GitHub Actions container compilation workflow from `docker/build-push-action@v5` to `@v6`.
* [COMPLETED] Configured remote S3 backend state storage with native locking (`use_lockfile = true`) for production Terraform root.
* [COMPLETED] Implemented dynamic Just-in-Time Security Group ingress rule management in GitHub Actions.
* [COMPLETED] Resolved relative path depth bug in Terraform `templatefile` function for dynamic Ansible inventory generation.
* [COMPLETED] Provisioned live AWS VPC, Subnet, Route Table, Security Group, Key Pair, and EC2 instance in `us-east-1`.
* [COMPLETED] Root-caused and resolved SSH passphrase deadlock in non-interactive CI runner.
* [COMPLETED] Resolved Docker image registry prefix collapse bug in EC2 deployment scripts.
* [IN PROGRESS] End-to-end container stack live health verification on EC2 host (`100.56.254.58`).
* [PLANNED] Configure AWS CloudWatch CPU and disk utilization alert alarms via Terraform.

---

## F. Lessons & Engineering Reflections

1. **Non-Interactive Environments Amplify Silent Assumptions**:
   On your local workstation, your environment carries state: an SSH agent, a decrypted keychain, environment variables, and cached DNS. CI/CD runners start completely empty. If an automation script depends on an interactive prompt (such as an SSH key passphrase), it will fail without giving you an obvious visual clue unless you understand non-interactive TTY limitations.

2. **Always Compute Derived Infrastructure Variables**:
   Relying on cross-job output forwarding for variables that can be derived directly from the AWS caller identity (like Amazon ECR repository URLs) introduces unnecessary coupling. Deriving the registry URL dynamically from `aws sts get-caller-identity` makes deployment scripts resilient against empty output parameters.

3. **Path Math in Monorepos Must Be Counted From File Roots**:
   When referencing templates or inventories across sibling directories (`infra/terraform/environments/prod` to `infra/ansible`), never guess directory depths. Count the directory levels back up to the common ancestor explicitly.

---

## G. Build-in-Public Content Archive

### Rule of Engagement: **ONE POST = ONE IDEA**
Every post must explain **only one** concrete achievement, discovery, or debugging lesson. Never combine unrelated activities into a generic list.

---

### Content Piece 01: The SSH Key Passphrase Trap in CI/CD

#### 𝕏 (Twitter) Post Draft
```text
If your SSH deployment works perfectly on your local machine but fails with "Permission denied (publickey)" in GitHub Actions, check if your private key has a passphrase.

On your laptop, SSH pauses and asks for your passphrase in the terminal.

In a CI/CD runner, there is no interactive screen (no TTY). 

When OpenSSH encounters an encrypted key without a human to type the passphrase, it cannot prompt you. It immediately abandons the key and fails with Permission Denied.

For automated machine-to-machine CI/CD, the deployment key must have its passphrase removed:

ssh-keygen -p -f ~/.ssh/deploy_key

The public key remains identical, your server config doesn't need to change, and your automated pipeline stops hanging silently.

Machine automation requires unencrypted keys secured by your vault, not human passwords.
```

#### LinkedIn Post Draft
```text
One of the most deceptive errors in CI/CD pipeline automation is the dreaded:
"ubuntu@<ip>: Permission denied (publickey)"

During a deployment rollout today on AWS, I ran into a scenario every platform engineer eventually hits:
The SSH handshake succeeded 100% of the time from my terminal, but failed consistently inside GitHub Actions.

The Security Group was open.
The key pair matched.
Permissions on ~/.ssh/deploy_key were set to 600.

So why did it fail?

The root cause was interactive vs. non-interactive runtime execution.

When connecting locally, SSH pauses execution and opens a TTY prompt: "Enter passphrase for key...". You enter it, the key is decrypted in memory, and you authenticate.

In an automated CI/CD runner, there is no interactive terminal. When OpenSSH encounters an encrypted private key and detects no active TTY or SSH agent, it cannot prompt for input. It silently drops the key and reports authentication failure.

The fix:
Automated service deployment keys cannot carry passphrases. You can strip the passphrase from an existing OpenSSH key in place:
$ ssh-keygen -p -f ~/.ssh/deploy_key
(Enter existing passphrase, then press Enter twice for empty).

The key fingerprint and public key remain identical—requiring zero changes on the cloud server—while enabling clean, non-interactive execution.

Security in CI/CD doesn't come from human passphrases on disk; it comes from storing unencrypted keys inside encrypted secrets vaults (like GitHub Secrets or AWS Secrets Manager) and applying strict least-privilege scoping.

#DevOps #CloudEngineering #AWSSecurity #CI_CD #Linux #Automation
```

---

### Content Piece 02: Dynamic Just-In-Time Security Group Ingress

#### 𝕏 (Twitter) Post Draft
```text
Leaving Port 22 open to 0.0.0.0/0 on AWS EC2 is an invitation for endless automated bot attacks.

But if you deploy using GitHub-hosted runners, how do you whitelist them when their public IPs change on every single run?

Here is the Just-in-Time (JIT) pattern I implemented today:

1. The runner queries its own IP at runtime:
RUNNER_IP=$(curl -s https://api.ipify.org)

2. The runner uses temporary AWS credentials to authorize only its /32 IP in the Security Group:
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr ${RUNNER_IP}/32

3. Deploy manifests over SSH/SCP.

4. Guaranteed teardown: In a post-step with `if: always()`, the runner revokes its own IP:
aws ec2 revoke-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr ${RUNNER_IP}/32

Port 22 stays closed to the entire public internet 99.9% of the time, opens only for 45 seconds during a deployment, and locks itself right back down.
```

#### LinkedIn Post Draft
```text
Securing administrative ingress on cloud compute instances often creates an operational dilemma:

If you restrict port 22 to your office IP, your automated CI/CD runners can't connect.
If you open port 22 to 0.0.0.0/0 to let GitHub Actions through, your instance gets bombarded by port scans and brute-force attempts 24/7.

Setting up a dedicated VPN or Bastion host is great, but often introduces unnecessary architectural overhead for lean, single-node workloads.

Today while engineering the delivery pipeline for the ZeetaFin platform on AWS, I implemented Ephemeral Just-in-Time (JIT) Security Group Ingress.

Here is how the lifecycle works:

1. Dynamic Discovery: The ephemeral GitHub runner queries its public IP via curl at runtime.
2. Scoped Authorization: Using least-privilege IAM bot credentials, the runner executes `aws ec2 authorize-security-group-ingress`, opening port 22 strictly for its own `${RUNNER_IP}/32`.
3. Execution: Manifests and Docker Compose files sync over SSH, and the rolling container swap runs.
4. Guaranteed Revocation: Using GitHub Actions' `if: always()` condition, the runner executes `aws ec2 revoke-security-group-ingress` when the job finishes—even if the deployment fails or crashes.

The result:
- Zero persistent open SSH ingress to the public internet.
- Zero VPN or Bastion host management overhead.
- Port 22 is open only for the ~40 seconds required to execute the container rollout, scoped strictly to a single IP.

Small architectural patterns like this enforce least-privilege defense without adding complexity to the developer experience.

#CloudSecurity #DevOps #AWS #Terraform #GitHubActions #CyberSecurity
```

---

## 📋 Standardized Templates

### 1. Daily Journal Entry Template

```markdown
### Session: YYYY-MM-DD — [Brief Title of the Focus Area]

* **Project**: [Name of Project or Repository]
* **Specific Tasks Undertaken**:
  1. [Task 1]
  2. [Task 2]
* **What Was Actually Accomplished**:
  - [Tangible outcome 1]
  - [Tangible outcome 2]
* **Technologies & Tools Used**: `[Tool1]`, `[Tool2]`, `[Tool3]`
* **Important Discoveries**:
  - [Discovery 1]
* **Problems Encountered & How They Were Approached**:
  - *Problem*: [Description]
  - *Investigation*: [What did you try?]
  - *Resolution*: [What worked?]
* **Current Status**: [Working / Blocked / Testing]
* **Incomplete / Next Steps**:
  - [Next actionable step]
```

---

### 2. Technical Insight Template

```markdown
### Insight [XX]: [Concise Title of the Discovery]
* **Problem / Question**: [What sparked this inquiry?]
* **Technical Explanation**: [First-principles explanation of how it works]
* **Practical Implementation**:
  ```[language]
  # Code or command example
  ```
* **Why This Matters**: [Practical benefit: security, cost, performance, reliability]
```

---

### 3. Troubleshooting Log Template

```markdown
### Log Entry [XX]: [Error Message or Symptom Summary]
* **Context**: [Which service/step was running?]
* **Symptoms & Observations**:
  ```text
  [Terminal error log output]
  ```
* **Initial Hypotheses**: [What did you first think was broken?]
* **Investigations Performed**: [What did you test?]
* **Approaches That Failed**: [What didn't work and why?]
* **Root Cause**: [The actual underlying technical reason]
* **Working Solution**: [The precise fix implemented]
* **Lessons Learned**: [How to avoid or diagnose this faster in the future]
```

---

### 4. Engineering Decision Record Template

```markdown
### EDR [XX]: [Title of Architectural Decision]
* **Status**: [Proposed | Accepted | Deprecated | Superseded]
* **Context**: [The problem or requirement driving the decision]
* **Options Considered**:
  1. *[Option A]*: [Pros / Cons]
  2. *[Option B]*: [Pros / Cons]
* **Decision**: [The chosen option]
* **Justification**: [Why this choice wins in this specific context]
* **Trade-offs & Limitations**: [What compromises were accepted?]
```

---

### 5. Single-Topic 𝕏 (Twitter) Post Template

```text
[Direct hook stating the technical problem or counter-intuitive discovery]

[Explain the exact mechanism of why it happens in 2-3 short sentences]

[Provide the exact command, code snippet, or configuration that solves it]

[One concluding sentence highlighting the engineering principle or takeaway]
```

---

### 6. Single-Topic LinkedIn Post Template

```text
[Hook: State the technical challenge or trade-off without corporate buzzwords]

[Context: What were you building or deploying, and what symptom appeared?]

[Investigation: Why did the obvious or initial approach fail? Explain the technical mechanism]

[The Solution: Walk through the architectural or technical fix with code/commands]

[Key Engineering Takeaway: What is the broader principle other teams can apply?]

#[RelevantTag1] #[RelevantTag2] #[RelevantTag3]
```

---

## 🗂️ Repository Scaling & Maintenance Guidelines

As your engineering journey progresses over months and years, a single `README.md` will eventually become too long to navigate easily.

### Recommended Modular Directory Structure

When this file exceeds ~1,000 lines, migrate the sections into modular Markdown files linked back to this central index:

```text
knowledge-base/
├── README.md                      # Central index & high-level journey overview
│
├── journal/                       # Chronological working logs
│   ├── 2026-Q4.md                 # Daily entries grouped by quarter
│   └── 2027-Q1.md
│
├── insights/                      # Deep-dive technical knowledge
│   ├── cloud-networking.md        # VPC, Subnets, JIT Ingress, DNS
│   ├── container-runtimes.md      # Docker internals, Alpine, cgroups
│   └── cicd-security.md           # IAM bots, secret hygiene, SSH
│
├── troubleshooting/               # Post-mortems and debugging records
│   ├── ssh-authentication-bugs.md
│   └── docker-reference-formatting.md
│
├── decisions/                     # Architecture Decision Records (ADRs)
│   ├── 001-ephemeral-sg-ingress.md
│   └── 002-native-s3-state-locking.md
│
└── content/                       # Build-in-public social media drafts
    ├── twitter-threads.md
    └── linkedin-articles.md
```

### 3 Golden Rules of Maintenance:
1. **Never Retrospectively Alter Failures**: When a previous technical hypothesis turns out to be wrong, do not delete the original entry. Add an `Update (Date)` note explaining why the hypothesis was flawed and what the real solution was.
2. **One Post Per Concept**: Never bundle multiple milestones into a single social media update. Depth on a single bug or decision demonstrates far higher competence than a surface-level bulleted list.
3. **Evidence Precedes Claims**: If an entry states a feature or pipeline is complete, it must be accompanied by supporting logs, commands, or code references.

