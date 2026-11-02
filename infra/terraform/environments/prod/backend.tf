# ==============================================================================
# S3 Remote State Backend Configuration with S3 Native State Locking
# ==============================================================================
# In production, state files must NEVER be stored locally or committed to Git.
# Bootstrap created state bucket: prod-dev-tfstate-672061768969

terraform {
  backend "s3" {
    bucket       = "prod-dev-tfstate-672061768969"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
