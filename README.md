# Frozone

_Where's my Data Backup!_

A small, cheap disaster-recovery backup: sync a directory to AWS S3
Glacier Deep Archive, get notified when it succeeds or fails, and follow
a documented path back if you have a disaster.

It started as a one-off question, "how do I back up my Immich photo
library," and grew into a generic, config-driven tool with
Terraform-managed infrastructure, OIDC-authenticated CI, and Discord
notifications.

## Why this exists

I had finished migrating ~10,700 photos (about 81GB) off Google Photos
into a self-hosted [Immich](https://immich.app) instance. That left one
copy, on one disk, in one building. I wanted cheap insurance against
losing a decade of photos along with the server, and I don't expect to
browse the archive or restore part of it. I want all of it back, once, if
everything else is gone.

### Why Deep Archive

S3 Glacier Deep Archive fits this access pattern: write once, read almost
never, unless something has gone badly wrong. The pricing reflects that
trade:

|                         | Rate                                    | ~100GB / year |
| ----------------------- | --------------------------------------- | ------------- |
| Storage                 | $0.00099/GB-month                       | ~$1.20/year   |
| Upload                  | free (plus a few cents in PUT requests) | <$1           |
| Bulk restore (≈48h)     | $0.0025/GB                              | ~$0.25        |
| Standard restore (≈12h) | ~$0.02/GB                               | ~$2.00        |
| Download out of AWS     | ~$0.09/GB                               | ~$9.00        |

A full catastrophic-loss restore costs around **$10, once, in the worst
case.** Storage costs about a dollar a year. Given that asymmetry, I
optimized for storage cost and durability and ignored retrieval speed and
retrieval cost.

### Why rclone over zip-and-upload

My first instinct was to zip photos by year and upload the archives.
rclone removes that step: it syncs a directory incrementally, takes Deep
Archive as a `--s3-storage-class` flag, and pulls a whole prefix back
down with one command
(`rclone backend restore ... -o priority=Bulk`). The only restore
scenario here is "get everything back," so pre-bundling into yearly
archives buys nothing and adds a zipping step I would have to maintain
and re-run.

## Is this reinventing the wheel?

In part, by choice. Several existing tools cover pieces of this:

- **[GDAB](https://github.com/mrichtarsky/glacier_deep_archive_backup)**:
  closest in spirit (per-job config files, scoped IAM, encryption) but
  requires ZFS snapshots for consistency.
- **[ogive](https://pkg.go.dev/github.com/mgren/ogive)**: single-binary,
  client-side encrypted, scoped IAM, but ships as a CLI with no infra or
  CI.
- **[serac](https://pypi.org/project/serac/)**,
  **[s3duct](https://pypi.org/project/s3duct/)**: similar scope, same gap
  of no infra-as-code, no notifications, bring-your-own orchestration.
- **[Jeff Geerling's my-backup-plan](https://github.com/geerlingguy/my-backup-plan)**:
  the closest full analog, rclone + cron + Ansible in a public repo,
  reporting ~$4/month for 8TB in Deep Archive, which checks out against
  the per-GB math above. No Terraform, no CI, no chat notifications.

None of them combine Terraform-managed least-privilege infra, OIDC'd CI
with a plan/apply split, a dead-man's-switch health check, chat
notifications, and a source-agnostic config design. rclone does the hard
part: chunked multipart uploads, storage-class handling, restore
orchestration. This repo adds the deployment and operations layer around
it, gluing well-understood pieces together in a way documented enough to
still make sense in five years.

## Design decisions

**Generic core, not a plugin system.** The scripts don't know what Immich
is. Everything source-specific, meaning the path, the bucket prefix, and
an optional DB dump to include, lives in a `config/*.env` file. Backing
up a second thing takes a second config file, no new code. A plugin
architecture would solve a problem this project doesn't have: multiple
sources with different _logic_ rather than different paths.

**Terraform over a one-off `aws cli` script.** For a single bucket and
two IAM identities, a shell script would do the job. The point of this
project is that I don't have to remember what I clicked six months ago,
and Terraform's plan output gives me that: a living description of what
exists and why, that won't drift without telling me.

**No static AWS credentials in GitHub Actions.** CI assumes the deploy
role via OIDC for the duration of a run, so nothing long-lived sits in
GitHub. `terraform plan` runs on every push, which is safe because forked
PRs get no secrets in that context. `terraform apply` is
`workflow_dispatch`-only, gated behind a GitHub Environment with a
required reviewer. This repo avoids the `pull_request_target` trigger,
the footgun that lets a forked PR exfiltrate secrets from a public repo.
Avoiding it takes one line (`on: push` / `on: workflow_dispatch`), not a
framework.

**The backup job has its own separate static credential.** The GitHub
OIDC role manages infrastructure and nothing else. The homelab host that
runs rclone on a schedule uses a long-lived IAM access key, narrow by
design: `PutObject`, `GetObject`, `RestoreObject`, `ListBucket`, and no
`DeleteObject`. The key lives in 1Password and lands in the environment
at run time via the `op` CLI. An attacker who compromises the host can
fill the bucket but can't delete the existing archive.

**Discord DMs over a webhook.** The notifier reuses an existing bot
(token plus user ID, opens a DM channel, posts to it) instead of standing
up a second notification path. See `scripts/notify.sh`.

## Repo layout

```
.
├── terraform/            # S3 bucket, lifecycle → Deep Archive, both IAM identities
├── scripts/
│   ├── backup.sh         # rclone copy, Deep Archive, logs + notifies
│   ├── restore.sh        # request restore / check status / download
│   ├── verify.sh         # size-only check that remote matches source
│   └── notify.sh         # Discord DM + healthchecks.io helpers
├── config/
│   ├── example.env       # documents every variable
│   └── immich.env        # the one real backup source, so far
├── systemd/              # weekly backup timer, monthly verify timer
├── .github/workflows/    # plan on push, apply on manual dispatch only
└── RESTORE.md            # the file to read during an actual emergency
```

## Setup

1. **Bootstrap the GitHub OIDC provider**, if your AWS account doesn't
   already have one. Most accounts need this once, across every repo that
   uses OIDC, so check first. See AWS's
   [GitHub Actions OIDC docs](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services).

2. **Run the first apply from your own machine**, not CI, since the
   deploy role doesn't exist yet:

   ```
   cd terraform
   terraform init
   terraform apply -var bucket_name=<something-globally-unique> \
                    -var github_repo=<you>/frozone
   ```

   Copy `backup_user_access_key_id` and `backup_user_secret_access_key`
   into 1Password. Note `github_deploy_role_arn`.

3. **In the GitHub repo settings**, add repository variables:
   `AWS_DEPLOY_ROLE_ARN` (the role ARN from step 2) and `BUCKET_NAME`.
   Create a `production` Environment with yourself as a required reviewer
   for the apply workflow.

4. **On the homelab host**, install `rclone` and the 1Password CLI

   ```
   # rclone — does the actual S3 upload
   curl https://rclone.org/install.sh |    sudo bash

   # 1Password CLI (op) — reads secrets    out of your vault from a script
   curl -sS https://downloads.1password.   com/linux/debian/amd64/stable/   1password-cli-amd64-latest.deb -o op.   deb
   sudo dpkg -i op.deb
   ```

   configure the rclone S3 remote with the backup user's credentials `rclone config`, and
   drop an `EnvironmentFile` at `/etc/frozone.env` that pulls
   secrets via `op read`.

5. **Enable the timers**:

   ```
   systemctl enable --now frozone@immich.timer
   systemctl enable --now deep-archive-verify@immich.timer
   ```

6. **Read `RESTORE.md` once now**, while nothing is on fire, and keep a
   plaintext copy of it in 1Password.
