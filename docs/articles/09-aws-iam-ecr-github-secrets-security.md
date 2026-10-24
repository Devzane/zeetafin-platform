---
title: "Zero-Trust CI/CD Security: Least-Privilege IAM, Amazon ECR, and Hardened GitHub Secrets"
subtitle: "Part 9 of the Production DevOps Series: Locking Down Automated Deployment Pipelines without Exposing Master Credentials"
tags: ["aws", "iam", "github-actions", "security", "devops", "cloud"]
series: "Hands-On Cloud DevOps Engineering: Zero to Production"
part: 9
canonical_url: ""
cover_image: ""
---

# Zero-Trust CI/CD Security: Least-Privilege IAM, Amazon ECR, and Hardened GitHub Secrets

In automated CI/CD pipelines, security is often treated as an afterthought. Teams frequently generate an AWS administrator access key with `AdministratorAccess` and paste it into GitHub Secrets. If those credentials leak through an unpinned third-party Action or build log artifact, an attacker has total administrative compromise over the entire AWS account.

In Part 9 of our DevOps series, we establish the security foundation for **Phase 3: Automated CI/CD**. We configure a least-privilege IAM bot user scoped strictly to Amazon ECR, set up encrypted GitHub Secrets, and eliminate hardcoded keys and IP addresses from source control.

---

## 1. Threat Model & Zero-Trust Authentication Architecture

A production continuous delivery pipeline must assume the runner environment is ephemeral and potentially subject to compromise:

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      GitHub Repository Environment                     │
 │                                                                        │
 │  Protected Secrets (Encrypted at rest with libsodium / Curve25519)     │
 │   • AWS_ACCESS_KEY_ID      ──► Scoped strictly to ECR push operations  │
 │   • AWS_SECRET_ACCESS_KEY  ──► No console access, no IAM edit rights   │
 │   • AWS_REGION             ──► us-east-1                               │
 │   • EC2_HOST               ──► Elastic IP / Public IP                  │
 │   • EC2_SSH_KEY            ──► Private key with strict user scoping    │
 └───────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      AWS Cloud Perimeter (us-east-1)                   │
 │                                                                        │
 │  IAM User: zeetafin-ci-cd-bot                                          │
 │  Policy: ECR-Limited-Push-Pull                                         │
 │   • Action: ecr:GetAuthorizationToken (Resource: *)                    │
 │   • Action: ecr:BatchCheckLayerAvailability, ecr:PutImage, etc.        │
 │     Resource: arn:aws:ecr:*:*:repository/zeetafin-*                   │
 │   • EXPLICIT DENY: All EC2 modify, IAM, S3, RDS, Billing permissions  │
 └────────────────────────────────────────────────────────────────────────┘
```

### Security Controls Enforced

1. **Dedicated Service Identity:** CI/CD runners never share credentials with human developers.
2. **Resource Scoping:** Push and write actions are restricted to repositories matching `zeetafin-*`.
3. **Zero Secrets in Code:** Workflow files (`deploy.yml`) contain only parameter references (`${{ secrets.AWS_ACCESS_KEY_ID }}`).
4. **Log Masking:** GitHub Actions automatically redacts values matching registered secrets in job logs.

---

## 2. Configuring the Least-Privilege IAM Bot User

We create an IAM user (`zeetafin-ci-cd-bot`) with programmatic access only (no AWS Management Console password).

### Step 1: Create the IAM Policy Document

Save the following least-privilege policy as `ecr-ci-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowECRAuthToken",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowScopedImagePushPull",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": [
        "arn:aws:ecr:us-east-1:*:repository/zeetafin-backend",
        "arn:aws:ecr:us-east-1:*:repository/zeetafin-frontend"
      ]
    }
  ]
}
```

> **Why `ecr:GetAuthorizationToken` requires `Resource: "*"`:** The AWS API does not allow restricting `GetAuthorizationToken` to a specific repository ARN because authorization tokens authenticate the client against the entire regional registry endpoint. However, subsequent push and pull actions are strictly scoped to `zeetafin-*`.

### Step 2: Provision User & Keys via AWS CLI

Run the following commands from your administrator workstation:

```bash
# 1. Create the IAM User
aws iam create-user --user-name zeetafin-ci-cd-bot

# 2. Create the Customer Managed Policy
POLICY_ARN=$(aws iam create-policy \
  --policy-name ZeetaFin-ECR-CI-Policy \
  --policy-document file://ecr-ci-policy.json \
  --query 'Policy.Arn' --output text)

# 3. Attach Policy to User
aws iam attach-user-policy \
  --user-name zeetafin-ci-cd-bot \
  --policy-arn "${POLICY_ARN}"

# 4. Generate Programmatic Access Keys
aws iam create-access-key --user-name zeetafin-ci-cd-bot > bot-creds.json
```

Extract the generated `AccessKeyId` and `SecretAccessKey` from `bot-creds.json`, then delete the file immediately:

```bash
cat bot-creds.json
rm -f bot-creds.json ecr-ci-policy.json
```

---

## 3. Configuring Encrypted GitHub Secrets

Navigate to your GitHub repository in your browser:
**Settings ➔ Secrets and variables ➔ Actions ➔ New repository secret**

Configure the required secrets:

| Secret Name | Description | Example / Source |
| :--- | :--- | :--- |
| `AWS_ACCESS_KEY_ID` | Access key for `zeetafin-ci-cd-bot` | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | Secret access key for `zeetafin-ci-cd-bot` | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `AWS_REGION` | Target AWS region | `us-east-1` |
| `EC2_HOST` | Public IP or Elastic IP of the host | Output of `terraform output -raw public_ip` |
| `EC2_SSH_KEY` | Private SSH key generated in Phase 1 | Contents of `~/.ssh/zeetafin-key` |

```bash
# Command to copy your private key directly to clipboard (macOS / Linux / Windows Git Bash):
cat ~/.ssh/zeetafin-key
```

> **Security Tip on SSH Keys:** Never commit the private key to git. When pasting `EC2_SSH_KEY` into GitHub Secrets, include the complete key including `-----BEGIN OPENSSH PRIVATE KEY-----` and `-----END OPENSSH PRIVATE KEY-----`.

---

## 4. Verification & Defense Testing

Test that the bot credentials work for ECR, but are blocked from unauthorized AWS services:

```bash
# Export the newly created bot keys locally for testing
export AWS_ACCESS_KEY_ID="<BOT_KEY>"
export AWS_SECRET_ACCESS_KEY="<BOT_SECRET>"
export AWS_DEFAULT_REGION="us-east-1"

# 1. Verify ECR Login Token succeeds
aws ecr get-authorization-token --output text > /dev/null && echo "ECR Auth: SUCCESS"

# 2. Verify Unauthorized Action is BLOCKED (Must return AccessDenied)
aws ec2 describe-instances || echo "EC2 Access: SAFELY DENIED"
aws s3 ls || echo "S3 Access: SAFELY DENIED"
aws iam list-users || echo "IAM Access: SAFELY DENIED"
```

The output confirms that the bot user cannot read EC2 instances, S3 buckets, or IAM users. Its authority is limited to our container registry.

---

## 5. Production Takeaways

1. **Principle of Least Privilege:** A CI/CD bot needs write access only to its specific artifact repository, not to broad cloud services.
2. **Avoid Long-Lived Keys When Possible:** For advanced enterprise deployments, consider using **OpenID Connect (OIDC)** between GitHub Actions and AWS IAM roles (`aws-actions/configure-aws-credentials` with `role-to-assume`), which issues short-lived temporary tokens without storing any static AWS keys in GitHub.
3. **Audit Key Usage:** Monitor AWS CloudTrail to track all API requests made by `zeetafin-ci-cd-bot` and set up alarms for any unauthorized API calls.

---

## Next Steps

With credentials secured and scoped, we build our automated GitHub Actions workflow.

👉 **Next in Series:** [Part 10: Declarative CI/CD Pipelines: Architecting GitHub Actions for Container Builds and ECR](./02-github-actions-ci-cd-workflow-architecture.md)
