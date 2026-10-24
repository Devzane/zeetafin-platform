output "state_bucket_name" {
  description = "Copy this value into the 'bucket' field in environments/dev/versions.tf."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_bucket_arn" {
  description = "ARN of the state bucket — useful if you add explicit IAM policies later."
  value       = aws_s3_bucket.terraform_state.arn
}

output "aws_account_id" {
  description = "Confirms which AWS account you applied into."
  value       = data.aws_caller_identity.current.account_id
}
