# SRE Runbook: Enterprise Secret & Credential Rotation

## 1. Overview & Policy
Regular credential rotation protects production environments against token exfiltration, employee offboarding exposure, and compliance audits (SOC2 / ISO 27001).

---

## 2. CI/CD IAM Bot Key Rotation (`zeetafin-ci-cd-bot`)

Rotate the programmatic deployment bot access keys every 90 days or immediately upon suspected compromise:

### Step 1: Create a Secondary Access Key in AWS IAM
```bash
aws iam create-access-key --user-name zeetafin-ci-cd-bot --output json > new_bot_credentials.json
```

### Step 2: Update GitHub Actions Secrets
Navigate to **GitHub Repository $\rightarrow$ Settings $\rightarrow$ Secrets and variables $\rightarrow$ Actions** and update:
1. `AWS_ACCESS_KEY_ID` with the new `AccessKeyId`.
2. `AWS_SECRET_ACCESS_KEY` with the new `SecretAccessKey`.

### Step 3: Trigger Verification Pipeline
Run a manual workflow dispatch on `.github/workflows/cd-deploy.yml` to verify authentication against Amazon ECR and EC2 deployment.

### Step 4: Deactivate and Delete the Old Key
```bash
# Deactivate old access key
aws iam update-access-key --user-name zeetafin-ci-cd-bot --access-key-id <OLD_KEY_ID> --status Inactive

# Delete old access key after verifying successful deployment
aws iam delete-access-key --user-name zeetafin-ci-cd-bot --access-key-id <OLD_KEY_ID>

rm new_bot_credentials.json
```

---

## 3. Production PostgreSQL Password Rotation

### Step 1: Generate Cryptographically Secure Password
```bash
NEW_DB_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9!@#%^&*' | head -c 24)
```

### Step 2: Update Password Inside PostgreSQL Engine
```bash
ssh -i ~/.ssh/phase1-key ubuntu@<EC2_PUBLIC_IP>

# Execute ALTER USER command within running database container
docker exec -it zeetafin-db-prod psql -U postgres -d zeetafin -c "ALTER USER postgres WITH PASSWORD '${NEW_DB_PASS}';"
```

### Step 3: Update `.env` Configuration File
```bash
cd /home/ubuntu/zeetafin-app
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${NEW_DB_PASS}|" .env
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${NEW_DB_PASS}|" .env
```

### Step 4: Recreate Containers
```bash
docker compose -f docker-compose.prod.yml up -d --force-recreate backend
./scripts/healthcheck.sh 127.0.0.1
```

---

## 4. JWT Authentication Secret Key Rotation

### Step 1: Generate New 256-bit Secret
```bash
NEW_JWT_SECRET=$(openssl rand -hex 32)
```

### Step 2: Apply to EC2 Environment
```bash
ssh -i ~/.ssh/phase1-key ubuntu@<EC2_PUBLIC_IP>
cd /home/ubuntu/zeetafin-app
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${NEW_JWT_SECRET}|" .env
```

### Step 3: Gracefully Restart Backend
```bash
docker compose -f docker-compose.prod.yml up -d --force-recreate backend
```
*Note: Rotating `JWT_SECRET` invalidates existing user session tokens and prompts active users to re-authenticate on next request.*
