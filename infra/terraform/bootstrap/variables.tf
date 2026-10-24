variable "aws_region" {
  description = "AWS region to deploy the state bucket into."
  type        = string
  default     = "us-east-1"
}

# No default — you must pass this. Keeps the bucket name unique and meaningful.
variable "project_name" {
  description = "Short slug for this project, e.g. 'portfolio-devops'. Used in bucket name."
  type        = string
}

variable "environment" {
  description = "Environment tag applied to all resources, e.g. 'dev'."
  type        = string
  default     = "dev"
}
