# --- Backup identity: used by rclone on the homelab host -------------------
# Long-lived access key, intentionally scoped with NO delete permission —
# if the host is ever compromised, the attacker can fill the bucket but
# cannot destroy the existing archive.
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
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.archive.arn]
      },
      {
        Sid    = "ReadWriteRestoreObjects"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:RestoreObject"
        ]
        Resource = ["${aws_s3_bucket.archive.arn}/*"]
      }
      # Deliberately no s3:DeleteObject, s3:DeleteBucket, or IAM actions here.
    ]
  })
}

# No GitHub deploy role lives here. State is local, so CI can't run a
# meaningful plan or apply; it only runs fmt/validate and never touches AWS.
# Adding one back means adding a remote backend first — see README.
