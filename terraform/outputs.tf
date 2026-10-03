output "bucket_name" {
  value = aws_s3_bucket.archive.id
}

output "backup_user_access_key_id" {
  value = aws_iam_access_key.backup.id
}

output "backup_user_secret_access_key" {
  value     = aws_iam_access_key.backup.secret
  sensitive = true
  # Retrieve with: terraform output -raw backup_user_secret_access_key
  # Copy it into 1Password immediately, then never run this output again.
}

output "github_deploy_role_arn" {
  value       = aws_iam_role.github_deploy.arn
  description = "Put this in the AWS_DEPLOY_ROLE_ARN repo variable for the GitHub Actions workflows"
}
