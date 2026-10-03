# --- Backup identity: used by rclone on the homelab host -------------------
# Long-lived access key, intentionally scoped with NO delete permission —
# if the host is ever compromised, the attacker can fill the bucket but
# cannot destroy the existing archive. The access key itself is generated
# here but should be copied into 1Password immediately and never committed
# or left in Terraform state you don't control tightly.

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

resource "aws_iam_access_key" "backup" {
  user = aws_iam_user.backup.name
}

# --- Deploy identity: used by GitHub Actions via OIDC -----------------------
# Actions assumes this role for the duration of a run.
# Scoped to this one bucket/IAM user, not account-wide.

data "aws_iam_openid_connect_provider" "github" {
  # Assumes the GitHub OIDC provider already exists in the account.
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_deploy" {
  name = "frozone-github-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = data.aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_deploy" {
  name = "frozone-deploy-scoped"
  role = aws_iam_role.github_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:*",
        "iam:*"
      ]
      Resource = [
        aws_s3_bucket.archive.arn,
        "${aws_s3_bucket.archive.arn}/*",
        aws_iam_user.backup.arn,
        aws_iam_role.github_deploy.arn
      ]
    }]
  })
}
