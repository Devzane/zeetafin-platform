variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI named profile to use for authentication."
  type        = string
  default     = "phase1"
}

variable "project_name" {
  description = "Short project slug used in resource names and tags."
  type        = string
  default     = "phase1"
}

variable "environment" {
  description = "Deployment environment label, e.g. dev, staging."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block, e.g. '10.0.0.0/16'."
  }
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet. Must be a subset of vpc_cidr."
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "AZ to place the subnet and instance in. Must exist in aws_region."
  type        = string
  default     = "us-east-1a"
}

variable "instance_type" {
  description = "EC2 instance type. Defaults to t3.micro (free-tier eligible)."
  type        = string
  default     = "t3.micro"

  validation {
    condition     = contains(["t2.micro", "t3.micro", "t3.small", "t3.medium"], var.instance_type)
    error_message = "Choose an instance type from the allowed list."
  }
}

# No default — you must supply this. Prevents accidentally allowing SSH from 0.0.0.0/0.
variable "my_ip" {
  description = "Your current public IP in CIDR notation, e.g. '1.2.3.4/32'. Run: curl -s ifconfig.me"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.my_ip))
    error_message = "my_ip must be a valid CIDR, e.g. '203.0.113.5/32'."
  }
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file to register as an EC2 key pair."
  type        = string
  default     = "~/.ssh/phase1-key.pub"
}

variable "ansible_inventory_path" {
  description = "File path where Terraform writes the generated Ansible inventory."
  type        = string
  default     = "../../ansible/inventory/hosts.ini"
}
