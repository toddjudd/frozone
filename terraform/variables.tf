variable "bucket_name" {
  description = "Globally-unique S3 bucket name for the archive"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the deploy role via OIDC, in 'owner/repo' form"
  type        = string
}
