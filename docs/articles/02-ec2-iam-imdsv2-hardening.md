---
title: "Hardening Cloud Compute: EC2 Provisioning, IAM Roles, and IMDSv2 Enforcement with Terraform"
subtitle: "Part 2 of the Production DevOps Series: Provisioning Ubuntu 24.04 LTS, Eliminating Hardcoded Credentials, and Securing Metadata Services"
tags: ["aws", "ec2", "terraform", "devops", "security", "iam"]
series: "Hands-On Cloud DevOps Engineering: Zero to Production"
part: 2
canonical_url: ""
cover_image: ""
---

# Hardening Cloud Compute: EC2 Provisioning, IAM Roles, and IMDSv2 Enforcement with Terraform

Provisioning a cloud virtual machine is easy. Provisioning an enterprise-grade, hardened compute instance that resists SSRF exploits, prevents credential leaks, and automatically bridges into downstream configuration management tools requires deliberate architectural rigor.

In Part 2 of our DevOps series, we provision an **Ubuntu 24.04 LTS** EC2 host on AWS using Terraform. We integrate a zero-trust IAM instance profile, enforce **Instance Metadata Service Version 2 (IMDSv2)**, encrypt block storage with `gp3`, and dynamically generate our Ansible inventory file.

---

## 1. Architectural Overview & Security Defense

```text
 ┌────────────────────────────────────────────────────────────────────────┐
 │                      AWS EC2 Host (Ubuntu 24.04 LTS)                   │
 │                                                                        │
 │  ┌───────────────────────┐         ┌────────────────────────────────┐  │
 │  │ IAM Instance Profile  │         │ Encrypted Root Volume (gp3)    │  │
 │  │ - Service: ec2        │         │ - KMS Default Encrypted (AES)  │  │
 │  │ - Extensible for ECR  │         │ - Size: 20 GB / delete on term │  │
 │  └───────────────────────┘         └────────────────────────────────┘  │
 │                                                                        │
 │  ┌──────────────────────────────────────────────────────────────────┐  │
 │  │ IMDSv2 Hardening (Metadata Service)                              │  │
 │  │  • http_tokens = "required" (Session token mandatory via PUT)    │  │
 │  │  • http_put_response_hop_limit = 1 (Prevents container SSRF)     │  │
 │  └──────────────────────────────────────────────────────────────────┘  │
 └────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
       Terraform Output ──► Dynamic local_file (ansible/inventory/hosts.ini)
```

### Why IMDSv2 Matters in Modern Cloud Security

In traditional AWS environments (IMDSv1), any software running on an EC2 instance that could trigger an HTTP request to `http://169.254.169.254/latest/meta-data/` could immediately exfiltrate temporary IAM role credentials. This vulnerability pattern (Server-Side Request Forgery, or SSRF) was the entry point in high-profile cloud data breaches.

**IMDSv2 fixes this by enforcing session-oriented requests:**
1. A client must issue an HTTP `PUT` request with a special header (`X-aws-ec2-metadata-token-ttl-seconds`) to generate a secret session token.
2. Subsequent `GET` requests must include this token in the `X-aws-ec2-metadata-token` header.
3. Most SSRF vulnerabilities can only send `GET` or `POST` requests and cannot supply custom `PUT` headers.
4. Setting `http_put_response_hop_limit = 1` prevents network packets from traversing Docker bridge interfaces or reverse proxies, isolating the metadata endpoint strictly to the root host network.

---

## 2. Key Pair & Security Prerequisites

Generate an Ed25519 or RSA-4096 SSH key pair on your local operator machine. Never check private keys into version control.

```bash
# Generate a dedicated SSH keypair (RSA 4096-bit or Ed25519)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/zeetafin-key -C "admin@zeetafin"

# Restrict private key permissions strictly to current user
chmod 400 ~/.ssh/zeetafin-key
```

Verify that the public key file (`~/.ssh/zeetafin-key.pub`) exists on disk. Terraform reads this file at plan time using `file()`.

---

## 3. Terraform Implementation

### Step 1: Dynamic Ubuntu 24.04 LTS AMI Resolution

Hardcoding AMI IDs (such as `ami-0c7217cdde317cfec`) leads to regional failures and outdated kernels. Instead, use an AWS AMI data source to dynamically resolve Canonical's official, verified Ubuntu 24.04 LTS image:

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS Account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
```

### Step 2: Key Pair and IAM Instance Profile

We attach an IAM role to the EC2 instance using an Instance Profile. In Phase 1, no long-lived AWS credentials exist inside the OS. When the instance later pulls images from Amazon ECR in Phase 3, this role seamlessly authorizes the host without access keys.

```hcl
# AWS Key Pair resource
resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-${var.environment}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = {
    Name = "${var.project_name}-${var.environment}-key"
  }
}

# IAM Assume Role Policy Document
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAM Role
resource "aws_iam_role" "ec2" {
  name               = "${var.project_name}-${var.environment}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-role"
  }
}

# IAM Instance Profile (The wrapper required by EC2)
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name
}
```

### Step 3: Hardened EC2 Instance Resource

Here is the compute specification incorporating IMDSv2, encrypted storage, and network attachment:

```hcl
resource "aws_instance" "main" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type # e.g. t3.medium
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = aws_key_pair.main.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  # Security Hardening: Enforce IMDSv2 and restrict hop count
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Rejects IMDSv1 calls with HTTP 401
    http_put_response_hop_limit = 1          # Prevents packets crossing bridge networks
  }

  # Storage: Encrypted gp3 block device
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-server"
  }
}
```

### Step 4: Bridging to Configuration Management (Dynamic Inventory)

Never copy-paste public IP addresses into configuration files manually. Use Terraform's `local_file` resource alongside `templatefile()` to automatically render an Ansible inventory whenever the instance is provisioned:

Create the template `ansible/inventory/hosts.ini.tpl`:

```ini
[docker_hosts]
${public_ip} ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/zeetafin-key

[docker_hosts:vars]
project_name=${project_name}
environment=${environment}
```

Declare the resource in `main.tf`:

```hcl
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/ansible/inventory/hosts.ini.tpl", {
    public_ip    = aws_instance.main.public_ip
    project_name = var.project_name
    environment  = var.environment
  })
  filename        = "${path.module}/ansible/inventory/hosts.ini"
  file_permission = "0644"
}
```

---

## 4. Execution & Verification

Run the plan and apply workflow:

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

### Verifying the Compute Instance and IMDSv2

Once provisioning finishes, extract the public IP and connect over SSH:

```bash
# Capture the provisioned IP
SERVER_IP=$(terraform output -raw public_ip)
echo "Target Host IP: ${SERVER_IP}"

# Test SSH connection with your private key
ssh -i ~/.ssh/zeetafin-key -o StrictHostKeyChecking=accept-new ubuntu@${SERVER_IP} "uname -a"
```

Once connected to the instance, test the IMDSv2 protection directly from the terminal:

```bash
# Test 1: Direct IMDSv1 GET request (MUST FAIL with HTTP 401 Unauthorized)
curl -s -o /dev/null -w "%{http_code}\n" http://169.254.169.254/latest/meta-data/
# Output: 401

# Test 2: Valid IMDSv2 flow (MUST SUCCEED)
# Step 2a: Acquire token via PUT
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

# Step 2b: Use token to query metadata
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id
# Output: i-0abc123def456789a
```

Verify that the Ansible inventory was generated automatically:

```bash
cat ansible/inventory/hosts.ini
```

---

## 5. Common Pitfalls & Troubleshooting

| Symptom | Root Cause | Fix |
| :--- | :--- | :--- |
| **`Permission denied (publickey)`** | Private key permissions too open or key mismatch. | Run `chmod 400 ~/.ssh/zeetafin-key` and confirm `ssh_public_key_path` matches the corresponding `.pub` file. |
| **SSH hangs indefinitely** | Security group ingress rule does not allow port 22 from your current public IP. | Inspect `aws_security_group.ec2` ingress and ensure your current IP is properly allowed. |
| **`local_file` template errors** | Variables referenced in `hosts.ini.tpl` do not match keys passed to `templatefile()`. | Check the interpolation keys in both files. |

---

## 6. Production Takeaways

1. **AMIs Should Be Dynamic, Not Hardcoded:** Using official owner IDs and version wildcards ensures instances launch with active security patches and official kernel updates.
2. **Never Put Secret Access Keys on Virtual Machines:** Leverage IAM Roles and Instance Profiles. The AWS SDK and CLI discover credentials automatically via the secure metadata service.
3. **IMDSv2 is Non-Negotiable:** Setting `http_tokens = "required"` and `http_put_response_hop_limit = 1` eliminates an entire class of cloud credential compromise attacks.

---

## Next Steps

Now that we have a secure, running Ubuntu host with dynamic inventory integration, we can configure our runtime dependencies without manual intervention.

👉 **Next in Series:** [Part 3: Immutable Host Configuration: Automating Docker CE Engine Setup with Ansible](./03-ansible-automation-docker.md)
