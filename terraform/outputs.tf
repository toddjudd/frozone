output "bucket_name" {
  value = aws_s3_bucket.archive.id
}

output "backup_user_name" {
  value       = aws_iam_user.backup.name
  description = "Mint this user's access key with: aws iam create-access-key --user-name <name>"
}
