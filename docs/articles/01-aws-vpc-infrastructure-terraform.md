---
title: "Building an Isolated AWS VPC and Network Foundation with Terraform"
subtitle: "Part 1 of the Production DevOps Series: Provisioning VPCs, Subnets, Gateways, and Hardened Security Groups with Infrastructure as Code"
tags: ["aws", "terraform", "devops", "cloud", "infrastructure-as-code", "security"]
series: "Hands-On Cloud DevOps Engineering: Zero to Production"
part: 1
canonical_url: ""
cover_image: ""
---

# Building an Isolated AWS VPC and Network Foundation with Terraform

When deploying production infrastructure to the cloud, manual provisioning through the AWS Management Console—colloquially called "ClickOps"—introduces drift, untracked changes, and inconsistent network policies.

In this first part of our end-to-end cloud engineering series, we establish the network foundation for an enterprise financial platform (**ZeetaFin ERP**). We use **HashiCorp Terraform** to build an isolated Amazon Virtual Private Cloud (VPC), configure routing through an Internet Gateway, and construct strict, least-privilege security groups locked down to your operational IP address.

---

## 1. Architectural Blueprint & Traffic Flow

The goal is to build an isolated, reproducible network perimeter in AWS region `us-east-1`.

```text
                               AWS Cloud (us-east-1)
  ┌────────────────────────────────────────────────────────────────────────┐
  │ VPC: 10.0.0.0/16                                                       │
  │                                                                        │
  │   Internet Gateway (igw) ◄───► Internet Route Table (0.0.0.0/0)        │
  │                                     │                                  │
  │                                     ▼                                  │
  │   Public Subnet: 10.0.1.0/24 (AZ: us-east-1a)                          │
  │   ┌──────────────────────────────────────────────────────────────────┐ │
  │   │ Security Group (zeetafin-sg)                                     │ │
  │   │   - Ingress Port 22   (SSH)          <-- Operator IP/32 only     │ │
  │   │   - Ingress Port 3000 (Next.js Web)  <-- Operator IP/32 only     │ │
  │   │   - Ingress Port 3001 (NestJS API)   <-- Operator IP/32 only     │ │
  │   │   - Egress  All Ports (0.0.0.0/0)    --> Outbound Packages/APIs  │ │
  │   └──────────────────────────────────────────────────────────────────┘ │
  └────────────────────────────────────────────────────────────────────────┘
```

### Key Architectural Decisions

1. **Deterministic CIDR Blocks:** We assign `10.0.0.0/16` for the VPC (65,536 addresses) and carve out `10.0.1.0/24` for our initial public compute subnet (251 usable AWS host addresses).
2. **Explicit Routing Over Defaults:** Instead of relying on the default AWS VPC where subnets have open default rules, every routing table entry and internet gateway attachment is explicitly codified.
3. **Least-Privilege Security Perimeter:** Security groups act as stateful firewalls. We restrict ingress for management (SSH port 22) and application traffic (ports 3000 and 3001) strictly to the administrator's `/32` IP address. Zero ports are exposed to the open internet (`0.0.0.0/0`).

---

## 2. Prerequisites & Local Environment Setup

Before executing Terraform, ensure your local workstation has the following tools installed and verified:

```bash
# Verify Terraform installation (v1.5+ required)
terraform -version

# Verify AWS CLI installation (v2.x required)
aws --version

# Verify AWS credentials and caller identity
aws sts get-caller-identity
```

Ensure your IAM user or role has permissions to create VPCs, Subnets, Internet Gateways, Route Tables, and Security Groups.

---

## 3. Project Directory Structure

Organize your Terraform codebase with clean separation of concerns:

```text
phase1/
├── versions.tf          # Provider requirements and version constraints
├── variables.tf         # Input variable definitions and validation
├── main.tf              # VPC, Subnet, Gateway, and SG resources
├── outputs.tf           # Exported infrastructure values (IDs, ARNs)
└── terraform.tfvars     # Local variable assignments (gitignored)
```

---

## 4. Step-by-Step Terraform Implementation

### Step 1: Provider and Version Locking (`versions.tf`)

Pin both the Terraform core version and the AWS provider version to prevent breaking syntax shifts during automated CI/CD runs.

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ZeetaFin"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
```

### Step 2: Defining Input Variables (`variables.tf`)

Make network ranges, region selection, and administrator IPs configurable through variables with sensible defaults:

```hcl
variable "aws_region" {
  type        = string
  description = "The target AWS region for deployment"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Deployment environment name"
  default     = "production"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the custom VPC"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR block for the public compute subnet"
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  type        = string
  description = "AWS Availability Zone for compute placement"
  default     = "us-east-1a"
}

variable "my_ip" {
  type        = string
  description = "Public IP address of the administrator workstation (CIDR /32)"
}
```

### Step 3: Determining Your External IP

To avoid locking yourself out or accidentally opening ports to the entire internet, retrieve your current public IP address:

```bash
# On Linux / macOS / Git Bash:
curl -s https://checkip.amazonaws.com

# Output example:
# 203.0.113.45
```

Create `terraform.tfvars` (ensure this file is added to `.gitignore`):

```hcl
aws_region = "us-east-1"
environment = "production"
my_ip       = "203.0.113.45/32"
```

### Step 4: Provisioning Network Resources (`main.tf`)

Now write the core infrastructure declarations:

```hcl
# 1. Custom VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "zeetafin-vpc-${var.environment}"
  }
}

# 2. Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "zeetafin-igw-${var.environment}"
  }
}

# 3. Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = "zeetafin-public-subnet-${var.environment}"
  }
}

# 4. Route Table & Internet Route
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "zeetafin-public-rt-${var.environment}"
  }
}

# 5. Route Table Association
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# 6. Hardened Security Group
resource "aws_security_group" "app_sg" {
  name        = "zeetafin-host-sg-${var.environment}"
  description = "Restricted ingress for SSH and application endpoints"
  vpc_id      = aws_vpc.main.id

  # SSH Management Access
  ingress {
    description = "SSH access from administrator IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # Next.js Frontend Access
  ingress {
    description = "Next.js Web UI from administrator IP"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # NestJS REST API Access
  ingress {
    description = "NestJS API from administrator IP"
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  # Outbound Internet Access (Package managers, ECR, APT)
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "zeetafin-sg-${var.environment}"
  }
}
```

### Step 5: Exposing Key Outputs (`outputs.tf`)

Export infrastructure IDs so downstream modules and automation scripts can reference them:

```hcl
output "vpc_id" {
  description = "The ID of the provisioned VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "The ID of the public subnet"
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "The ID of the host security group"
  value       = aws_security_group.app_sg.id
}
```

---

## 5. Execution Workflow & Verification

Run the standard Terraform workflow from your terminal:

```bash
# 1. Initialize backend and download the AWS provider
terraform init

# 2. Validate syntax and resource arguments
terraform validate

# 3. Generate and inspect the execution plan
terraform plan -out=tfplan

# 4. Apply the planned changes
terraform apply tfplan
```

### Validating Resources via AWS CLI

Once Terraform outputs the created IDs, confirm network connectivity and routing using the AWS CLI:

```bash
# Verify VPC state is 'available'
aws ec2 describe-vpcs --vpc-ids $(terraform output -raw vpc_id) \
  --query "Vpcs[0].State" --output text

# Verify route table has the 0.0.0.0/0 -> igw route
aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
  --query "RouteTables[0].Routes" --output table
```

---

## 6. Common Pitfalls & Troubleshooting

| Issue | Root Cause | Solution |
| :--- | :--- | :--- |
| **`UnauthorizedOperation` during `terraform apply`** | AWS credentials lack EC2 networking privileges. | Attach an IAM policy granting `ec2:CreateVpc`, `ec2:CreateSubnet`, `ec2:CreateSecurityGroup`, etc. |
| **Dynamic IP shifts lock out SSH** | Home/office ISP rotated your public IP address. | Re-run `curl -s https://checkip.amazonaws.com`, update `my_ip` in `terraform.tfvars`, and run `terraform apply`. |
| **Route table missing default route** | Subnet provisioned without an active route to the Internet Gateway. | Verify that `aws_route_table_association` links the subnet to the table containing `gateway_id = aws_internet_gateway.gw.id`. |

---

## 7. Production Takeaways

1. **Never use the Default VPC for real workloads:** Default VPCs have subnets in every AZ mapped with public IP assignment and wide-open default security groups.
2. **Strict `/32` Ingress:** By bounding SSH and application ports to `your_ip/32`, automated vulnerability bots scanning AWS public IPv4 ranges cannot reach your listening ports.
3. **State Management:** For team environments, always configure remote state storage using Amazon S3 with server-side encryption and state locking via DynamoDB.

---

## Next Steps

With our isolated VPC and hardened security groups in place, we are ready for compute provisioning.

👉 **Next in Series:** [Part 2: Hardening Cloud Compute: EC2 Provisioning, IAM Roles, and IMDSv2 Enforcement](./02-ec2-iam-imdsv2-hardening.md)
