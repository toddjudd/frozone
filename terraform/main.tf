terraform {
  required_version = ">= 1.7" # `removed` blocks (iam.tf)
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

# Versioning closes the overwrite gap in the backup user's policy. That user
# has no s3:DeleteObject, but s3:PutObject alone can replace an existing key,
# and with versioning off the old bytes would be gone. A compromised host
# could then turn "can't delete the archive" into "can overwrite every object
# in it with junk". With versioning on, an overwrite only demotes the old copy
# to a noncurrent version, recoverable for 180 days (see the lifecycle rule
# below and RESTORE.md).
#
# The backup user must never be granted s3:PutBucketVersioning,
# s3:PutLifecycleConfiguration, s3:DeleteObjectVersion, or s3:PutBucketPolicy:
# any one of them undoes this protection.
resource "aws_s3_bucket_versioning" "archive" {
  bucket = aws_s3_bucket.archive.id
  versioning_configuration {
    status = "Enabled"
  }
}

# One lifecycle configuration per bucket: AWS stores a single document, so a
# second aws_s3_bucket_lifecycle_configuration would overwrite this one on
# every apply. Add new rules here.
resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id

  # Noncurrent-version rules are only valid once versioning is enabled.
  depends_on = [aws_s3_bucket_versioning.archive]

  rule {
    id     = "deep-archive-immediately"
    status = "Enabled"

    filter {} # applies to every object in the bucket

    transition {
      days          = 0
      storage_class = "DEEP_ARCHIVE"
    }
  }

  # Keep an overwritten or deleted object's old version for 180 days, then
  # drop it. Deep Archive bills every object for at least 180 days anyway, so
  # holding a replaced version that long costs about the same as the early-
  # deletion fee an unversioned overwrite would have charged.
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 180
    }

    # Once a key's only remaining "version" is a delete marker, remove the
    # marker too, so deleted keys don't linger in version listings forever.
    expiration {
      expired_object_delete_marker = true
    }
  }

  # The backup user has no s3:AbortMultipartUpload, so an interrupted
  # multipart upload (rclone killed mid-chunk, host reboot) leaves its parts
  # behind, billed but invisible to `rclone ls`. Clean them up.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
