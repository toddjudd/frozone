terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # State is NOT kept in this repo (it can contain the backup user's access
  # key ID). Use a local backend on a machine you control, or configure a
  # private S3 backend of your own here before running this in anger.
  # backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

resource "aws_s3_bucket" "archive" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "archive" {
  bucket                  = aws_s3_bucket.archive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "archive" {
  bucket = aws_s3_bucket.archive.id
  versioning_configuration {
    status = "Disabled" # a disaster-recovery archive; we don't need version history
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id

  rule {
    id     = "deep-archive-immediately"
    status = "Enabled"

    filter {} # applies to every object in the bucket

    transition {
      days          = 0
      storage_class = "DEEP_ARCHIVE"
    }
  }
}
