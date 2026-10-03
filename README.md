# Frozone

_Where's my Data Backup!_

A small, cheap disaster-recovery backup: sync a directory to AWS S3
Glacier Deep Archive, get notified when it succeeds or fails, and follow
a documented path back if you have a disaster.

It started as a one-off question, "how do I back up my Immich photo
library," and grew into a generic, config-driven tool with
Terraform-managed infrastructure and Discord notifications.

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

None of them combine Terraform-managed least-privilege infra, a
dead-man's-switch health check, chat notifications, and a source-agnostic
config design. rclone does the hard part: chunked multipart uploads,
storage-class handling, restore orchestration. This repo adds the
deployment and operations layer around it, gluing well-understood pieces
together in a way documented enough to still make sense in five years.

## Design decisions

**Generic core, not a plugin system.** The scripts don't know what Immich
is. Everything source-specific, meaning the path, the bucket prefix, and
an optional DB dump to include, lives in a `config/*.env` file. Backing
up a second thing takes a second config file, no new code. A plugin
architecture would solve a problem this project doesn't have: multiple
sources with different _logic_ rather than different paths.

**Terraform over a one-off `aws cli` script.** For a single bucket and
one IAM user, a shell script would do the job. The point of this
project is that I don't have to remember what I clicked six months ago,
and Terraform's plan output gives me that: a living description of what
exists and why, that won't drift without telling me.

**I gave GitHub Actions no AWS credentials.** CI runs `terraform fmt` and
`terraform validate`. Terraform state sits on my laptop, so on each push
I'd read the same CI plan: create every resource, from an empty state.
`apply` needs that same state. Move the state into a private S3 backend
and both become useful, and the OIDC role comes back with it. I also keep
the workflow off the `pull_request_target` trigger, which hands fork code
the base repo's secrets.

**I create the backup host's access key by hand.** The homelab host runs
rclone on a schedule with a long-lived IAM key, scoped to `PutObject`,
`GetObject`, `RestoreObject`, and `ListBucket` on one bucket, with no
`DeleteObject`. An attacker who compromises the host can fill the bucket
but can't delete the existing archive. Terraform creates the user and its
policy but not the key, because an `aws_iam_access_key` resource writes
the secret into state in plaintext. One `aws iam create-access-key` keeps
it out of state, and the `op` CLI feeds it to the scripts at run time.

**Discord DMs over a webhook.** The notifier reuses an existing bot
(token plus user ID, opens a DM channel, posts to it) instead of standing
up a second notification path. See `scripts/notify.sh`.

## Repo layout

```
.
├── terraform/            # S3 bucket, lifecycle → Deep Archive, backup IAM user
├── scripts/
│   ├── backup.sh         # rclone copy, Deep Archive, logs + notifies
│   ├── restore.sh        # request restore / check status / download
│   ├── verify.sh         # size-only check that remote matches source
│   ├── validate.sh       # fail-fast config checks shared by the above
│   ├── deploy.sh         # copy this checkout to /opt/frozone, reload units
│   └── notify.sh         # Discord DM + healthchecks.io helpers
├── config/
│   ├── example.env       # documents every variable
│   └── immich.env        # the one real backup source, so far (gitignored)
├── systemd/              # weekly backup timer, monthly verify timer
├── .github/workflows/    # terraform fmt + validate, no AWS access
└── RESTORE.md            # the file to read during an actual emergency
```

## Setup

1. **Create the infrastructure from your own machine.** No CI job runs
   `apply`, and the state file stays with you.

   ```
   cd terraform
   terraform init
   terraform apply -var bucket_name=<something-globally-unique>
   ```

   Back up `terraform.tfstate`. Git ignores it, and it holds the only
   record of what Terraform manages.

2. **Create the backup user's access key** and paste it into 1Password as
   the `frozone` item (`access_key` / `secret_key`):

   ```
   aws iam create-access-key --user-name frozone
   ```

   AWS shows you the secret once.

3. **On the homelab host**, install `rclone` and the 1Password CLI

   ```
   # rclone — does the actual S3 upload
   curl https://rclone.org/install.sh |    sudo bash

   # 1Password CLI (op) — reads secrets    out of your vault from a script
   curl -sS https://downloads.1password.   com/linux/debian/amd64/stable/   1password-cli-amd64-latest.deb -o op.   deb
   sudo dpkg -i op.deb
   ```

   Skip `rclone config`. The `RCLONE_CONFIG_*` variables in
   `config/<name>.env` define the remote and carry `op://` references to the
   access key, so your credentials stay in 1Password and the root service
   runs without an `rclone.conf`.

   Then create a 1Password **service account**, grant it read access to the
   vault holding the `frozone` and `discord-bot` items, and put its token in
   `/etc/frozone.env`:

   ```
   OP_SERVICE_ACCOUNT_TOKEN=ops_eyJzaWduSW...
   ```

   ```
   sudo chown root:root /etc/frozone.env && sudo chmod 600 /etc/frozone.env
   ```

   That file is the *only* real secret on the host. systemd reads it
   literally — it is not a shell, so `$(op read ...)` would be passed
   through as a meaningless string. Instead, each `config/<name>.env`
   carries `op://vault/item/field` references alongside its plain config
   values, and the units invoke
   `op run --env-file=config/%i.env -- scripts/backup.sh %i`.
   `op run` resolves the references, passes plain values through untouched,
   and masks resolved secrets in stdout/stderr. `backup.sh` and `verify.sh`
   read their config from the environment, not from the file — the trailing
   `%i` is just a label for logs and Discord messages.

   Check it resolves before enabling the timers:

   ```
   op run --env-file=config/immich.env -- env | grep DISCORD
   ```

4. **Install the repo to `/opt/frozone`**. The units hardcode that path as
   their `WorkingDirectory` and resolve `config/<name>.env` and
   `scripts/*.sh` beneath it, so a checkout anywhere else will not be found.

   ```
   sudo ./scripts/deploy.sh
   ```

5. **Enable the timers**:

   ```
   sudo cp systemd/frozone-*.service systemd/frozone-*.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now frozone-backup@immich.timer
   sudo systemctl enable --now frozone-verify@immich.timer
   ```

6. **Read `RESTORE.md` once now**, while nothing is on fire, and keep a
   plaintext copy of it in 1Password.

## Updating a deployed host

`/opt/frozone` holds a copy of this repo. The systemd units resolve every
path beneath it, so edits in your working tree do nothing until you redeploy.
Change `config/immich.env` here, skip the redeploy, and the timer keeps
running against the old value as though your edit never saved.

After any change to `scripts/`, `config/`, or `systemd/`:

```
sudo ./scripts/deploy.sh
```

The script rsyncs the checkout over `/opt/frozone` with `--delete`, so
removals propagate. It resets ownership and permissions, reinstalls the unit
files into `/etc/systemd/system`, then runs `daemon-reload`. Leave the timers
alone: `daemon-reload` covers a changed unit, and the enablement symlinks
still point at the templates.

### Testing a change without a full upload

`systemd-run` hands you the unit's environment: same `EnvironmentFile`, same
`HOME`, same working directory. Most breakage here comes from the environment
rather than the scripts, so reproduce it instead of calling the scripts by
hand:

```
sudo systemd-run --wait --collect --pipe --quiet --working-directory=/opt/frozone \
  -p EnvironmentFile=/etc/frozone.env -p Environment=HOME=/root \
  /usr/bin/op run --env-file=/opt/frozone/config/immich.env -- \
  rclone size s3personal:t482-homeserver-frozone/immich/
```

Swap `rclone size` for `rclone copy <source> <remote> --dry-run` to see what
a real run would upload.
