# SRE Runbook: Disaster Recovery & Infrastructure Reconstruction

## 1. Overview & Service Level Objectives
This runbook defines the operational procedures to recover the ZeetaFin Cloud Platform in the event of complete compute node failure, availability zone disruption, or volume corruption.

* **Recovery Time Objective (RTO)**: < 15 minutes (Total automated rebuild)
* **Recovery Point Objective (RPO)**: < 1 hour (Database snapshot cadence)

---

## 2. Infrastructure Reconstruction (Terraform)

If the EC2 compute instance or underlying AWS hardware is destroyed:

### Step 1: Initialize Terraform with Remote S3 State
Navigate to the production Terraform environment:
```bash
cd infra/terraform/environments/prod
terraform init
```

### Step 2: Validate Target Infrastructure Plan
```bash
terraform plan -out=dr-recovery.tfplan
```

### Step 3: Apply Infrastructure Provisioning
```bash
terraform apply dr-recovery.tfplan
```
*Terraform will recreate the VPC resources (if needed), re-provision the EC2 host with strict IMDSv2 tokens, and generate an updated Ansible inventory at `infra/ansible/inventory/hosts.ini`.*

---

## 3. Host Hardening & Container Runtime Setup (Ansible)

Once the EC2 host is running, configure Docker and host security:

```bash
cd infra/ansible
ansible-playbook -i inventory/hosts.ini site.yml
```
*Ansible waits for cloud-init to release apt locks, installs Docker CE and official compose plugins, creates the Docker system group, and verifies runtime functionality.*

---

## 4. Persistent Volume & Database State Restoration

If restoring PostgreSQL data from an encrypted S3 database backup:

### Step 1: Create the Named Volume on EC2
```bash
ssh -i ~/.ssh/phase1-key ubuntu@<EC2_PUBLIC_IP>
docker volume create zeetafin_prod_pgdata
```

### Step 2: Extract Database Snapshot into Volume
```bash
# Pull latest backup archive from secure S3 backup bucket
aws s3 cp s3://zeetafin-prod-backups/latest-db-snapshot.tar.gz ./db_snapshot.tar.gz

# Populate volume via temporary alpine container
docker run --rm -v zeetafin_prod_pgdata:/data -v $(pwd):/backup alpine \
  sh -c "tar -xzf /backup/db_snapshot.tar.gz -C /data"

rm db_snapshot.tar.gz
```

---

## 5. Application Stack Rollout & Verification

Deploy the application containers using the deployment runner:

```bash
cd /home/ubuntu/zeetafin-app
./scripts/deploy.sh latest
```

Verify service availability:
```bash
./scripts/healthcheck.sh 127.0.0.1
```
*Expected output: `All services healthy and responsive! (HTTP 200)`*
