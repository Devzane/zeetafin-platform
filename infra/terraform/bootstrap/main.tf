# Pull the account ID at plan time so the bucket name is globally unique
# without you having to hardcode your account number in the repo.
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "terraform_state" {
  # Account ID suffix guarantees global uniqueness (S3 names are global).
  bucket = "${var.project_name}-${var.environment}-tfstate-${data.aws_caller_identity.current.account_id}"

  # Prevent 'terraform destroy' from deleting the bucket that holds all state.
  # You must remove this lifecycle block manually before you can destroy the bucket.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform-bootstrap"
  }
}

# Keep every version of the state file. Lets you roll back a bad apply.
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state at rest with the AWS-managed S3 key (no KMS charge on free tier).
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Hard block — even if someone adds a bucket ACL later, public access stays off.
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# The bucket policy enforces TLS-only access. Plain HTTP requests are denied.
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  # Depends on the public-access block being in place first, otherwise the
  # policy apply can race with the block and fail.
  depends_on = [aws_s3_bucket_public_access_block.terraform_state]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLS"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.terraform_state.arn,
          "${aws_s3_bucket.terraform_state.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
