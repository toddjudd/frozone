# --- Backup identity: used by rclone on the homelab host -------------------
# Long-lived access key, intentionally scoped with NO delete permission —
# if the host is ever compromised, the attacker can fill the bucket but
# cannot destroy the existing archive. PutObject can still overwrite a key;
# bucket versioning (main.tf) keeps the overwritten copy recoverable.
#
# The access key is deliberately NOT managed here: Terraform would hold the
# secret in plaintext in state forever. Mint it once by hand and paste it
# straight into 1Password:
#
#   aws iam create-access-key --user-name frozone

resource "aws_iam_user" "backup" {
  name = "frozone"
}

resource "aws_iam_user_policy" "backup" {
  name = "frozone-scoped"
  user = aws_iam_user.backup.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBucket"
        Effect = "Allow"
        # ListBucketVersions is read-only. It lets RESTORE.md's "restore a
        # previous version" path run with these same credentials.
        Action   = ["s3:ListBucket", "s3:ListBucketVersions"]
        Resource = [aws_s3_bucket.archive.arn]
      },
      {
        Sid    = "ReadWriteRestoreObjects"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion", # read-only: download/inspect an older version
          "s3:RestoreObject"
        ]
        Resource = ["${aws_s3_bucket.archive.arn}/*"]
      }
      # Deliberately absent, because each would let a compromised host destroy
      # or un-protect the archive:
      #   s3:DeleteObject, s3:DeleteObjectVersion, s3:DeleteBucket,
      #   s3:PutBucketVersioning, s3:PutLifecycleConfiguration,
      #   s3:PutBucketPolicy, s3:PutObjectRetention, s3:BypassGovernanceRetention,
      #   and any iam:* action.
    ]
  })
}

# Earlier revisions managed the backup user's access key and a GitHub OIDC
# deploy role here. Those resources still exist in AWS, and the key is the one
# the backup host actually uses. These blocks make Terraform forget them
# without destroying them. Forgetting the key also drops its plaintext secret
# from local state. Once every state file has applied them, they can go.
removed {
  from = aws_iam_access_key.backup
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_role_policy.github_deploy
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_role.github_deploy
  lifecycle {
    destroy = false
  }
}

# No GitHub deploy role lives here. State is local, so CI can't run a
# meaningful plan or apply; it only runs fmt/validate and never touches AWS.
# Adding one back means adding a remote backend first — see README.
