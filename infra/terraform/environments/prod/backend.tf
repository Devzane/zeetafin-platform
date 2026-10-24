# ==============================================================================
# S3 Remote State Backend Configuration with DynamoDB State Locking
# ==============================================================================
# In production, state files must NEVER be stored locally or committed to Git.
# Run 'infra/terraform/bootstrap' first to create the state bucket and locking table.

terraform {
  backend "s3" {
    bucket         = "zeetafin-prod-tfstate"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "zeetafin-prod-tflock"
  }
}
