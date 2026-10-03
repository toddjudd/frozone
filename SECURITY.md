# Security Policy

I maintain this homelab project by myself. I have no SLA and no security
team, and I still want to hear about a problem you find.

## Reporting a vulnerability

**Don't open a public issue.** Use GitHub's
[private vulnerability reporting](https://github.com/toddjudd/frozone/security/advisories/new),
which keeps your report confidential until I fix it.

Tell me what an attacker can do and which file and line lets them do it.
A proof of concept helps.

Expect a reply within a couple of weeks. If someone is exploiting it
right now, say so in the title.

## Scope

In scope:

- Anything that leaks the AWS credentials, the 1Password service account
  token, or the Discord bot token.
- Anything that lets a fork's pull request run code with elevated
  permissions in this repo's Actions.
- IAM policies in [terraform/](terraform/) that grant more than their
  comments claim.
- Command injection or path traversal in [scripts/](scripts/) that you
  can reach from a config file or a filename in the backed-up directory.

Out of scope:

- Anything that requires root on the backup host. That host holds the
  backup credential by design. The protection is that the credential
  can't delete objects.
- Missing hardening on resources you deploy in your own AWS account.
- No client-side encryption before upload. The README explains that
  trade-off.

## Known design trade-offs

I chose these:

- **The backup host holds a long-lived AWS access key.** I scoped it to
  `PutObject`, `GetObject`, `RestoreObject`, and `ListBucket` on one
  bucket, with no delete permission, so whoever compromises the host can
  fill the bucket but can't destroy the archive.
- **Terraform state stays on my machine and out of git.** Nothing
  encrypts it beyond whatever your disk does. Treat the machine that runs
  `terraform apply` as sensitive.
- **CI has no AWS access.** The workflow runs `fmt` and `validate`, so a
  malicious pull request has nothing to steal.
