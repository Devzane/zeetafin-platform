# ─── Data Sources ─────────────────────────────────────────────────────────────

# Ubuntu 24.04 LTS (Noble Numbat) — latest AMI from Canonical's official account.
# VERIFY: Run `aws ec2 describe-images --owners 099720109477 --filters
#   "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
#   --query 'sort_by(Images,&CreationDate)[-1].[Name,ImageId]' --region us-east-1`
# to confirm the name pattern still matches current Canonical releases.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# ─── Networking ───────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # required for hostname resolution inside the VPC
  enable_dns_hostnames = true # required for EC2 public DNS names

  tags = { Name = "${var.project_name}-${var.environment}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project_name}-${var.environment}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true # assigns a public IP automatically; avoids needing an EIP

  tags = { Name = "${var.project_name}-${var.environment}-public-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-${var.environment}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ─── Security Group ───────────────────────────────────────────────────────────

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-${var.environment}-ec2-sg"
  description = "Security group for ZeetaFin app with SSH and web ingress"
  vpc_id      = aws_vpc.main.id

  # SSH Access: Required for GitHub Actions deployment runner
  ingress {
    description = "SSH for administration and CI/CD"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Or keep [var.my_ip] if using a self-hosted runner
  }

  # Next.js Web Frontend
  ingress {
    description = "ZeetaFin Frontend UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # NestJS REST API
  ingress {
    description = "ZeetaFin Backend REST API"
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic so Docker can pull images & OS can run apt
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-${var.environment}-ec2-sg" }
}


# ─── Key Pair ─────────────────────────────────────────────────────────────────

resource "aws_key_pair" "main" {
  key_name = "${var.project_name}-${var.environment}-key"
  # file() reads the public key from disk at plan time. pathexpand() resolves ~.
  # The private key never leaves your machine and is never in this config.
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = { Name = "${var.project_name}-${var.environment}-key" }
}

# ─── IAM Instance Role ────────────────────────────────────────────────────────

# Phase 1: the app makes no AWS API calls, so the role has zero policies attached.
# The role still exists so Phase 2 (ECR pull) can add permissions without
# replacing the instance.
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

resource "aws_iam_role" "ec2" {
  name               = "${var.project_name}-${var.environment}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = { Name = "${var.project_name}-${var.environment}-ec2-role" }
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ─── EC2 Instance ─────────────────────────────────────────────────────────────

resource "aws_instance" "main" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = aws_key_pair.main.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  # IMDSv2 enforced: any code trying the old IMDSv1 endpoint gets a 401.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = "${var.project_name}-${var.environment}-server" }
}

# ─── Ansible Inventory (generated, never hand-edited) ─────────────────────────

resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/../../ansible/inventory/hosts.ini.tpl", {
    public_ip    = aws_instance.main.public_ip
    project_name = var.project_name
    environment  = var.environment
  })
  filename        = "${path.module}/${var.ansible_inventory_path}"
  file_permission = "0644"
}
