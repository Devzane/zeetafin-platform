variable "project_name" {
  description = "Project slug. Combined with environment to name every resource."
  type        = string
}

variable "environment" {
  description = "Deployment environment, e.g. 'dev', 'staging'."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC, e.g. '10.0.0.0/16'."
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR block for the single public subnet. Must be within vpc_cidr."
  type        = string
}

# Explicit AZ avoids random placement. Matters if you ever add EBS volumes,
# which are AZ-scoped and must match the instance.
variable "availability_zone" {
  description = "AZ to place the public subnet in, e.g. 'us-east-1a'."
  type        = string
}
