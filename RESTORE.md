# RESTORE.md: read this during an emergency

I wrote this file for 2am-during-a-disaster reading. Keep a plaintext
copy of this file alone as a secure note in 1Password, in case you can't
reach GitHub when you need it.

## What you need

- Bucket name: see the 1Password item `frozone` → `bucket_name`
  (or run `terraform output bucket_name` if you have the repo and state)
- Backup user credentials: 1Password item `frozone` →
  `access_key` / `secret_key`
- rclone installed on the machine you're restoring to

Everything below runs on bash and rclone alone. Skip `rclone config`: the
`RCLONE_CONFIG_*` lines in `config/<name>.env` already describe the remote,
leaving only the two credentials for you to supply. Read those off 1Password
(web, phone, or emergency kit) and export them, substituting the remote name
from `S3_REMOTE` in uppercase:

```
export RCLONE_CONFIG_S3PERSONAL_ACCESS_KEY_ID=AKIA...
export RCLONE_CONFIG_S3PERSONAL_SECRET_ACCESS_KEY=...
```

`restore.sh` skips the `op://` lines when it reads the config, so your
exported values survive. A working `op` stays optional.

## Step 1: request the restore, then wait

```
./scripts/restore.sh config/<name>.env --request --priority Bulk
```

- `Bulk` = cheapest, ~48 hours
- `Standard` = ~12 hours, costs more per GB
- A Discord DM confirms the request went through.
- Check status any time with:
  ```
  ./scripts/restore.sh config/<name>.env --status
  ```

## Step 2: once thawed, download it

```
./scripts/restore.sh config/<name>.env --download /path/to/restore-target
```

Expect hours rather than minutes. 100GB over a typical home downstream
connection takes a few hours.

## Restoring a previous version (the archive was overwritten)

Use this section if the current objects are junk: ransomware or a
compromised host uploaded over existing names, or a bad backup run
replaced good files. The backup user can't delete, but it can overwrite.
The bucket is versioned, so every overwritten copy survives as a
_noncurrent version_ for **180 days** after the overwrite. Then a
lifecycle rule removes it. If you suspect an overwrite, act within that
window.

**0. If the backup host is the suspect, rotate its key first.** Otherwise
the next Sunday run (or the attacker) keeps writing. Using an admin login:

```
aws iam list-access-keys --user-name frozone
aws iam update-access-key --user-name frozone --access-key-id <old> --status Inactive
aws iam create-access-key --user-name frozone   # paste into 1Password `frozone`
```

**1. Find when the damage started.** List every version of a file you
know was hit. rclone shows older versions with their timestamp in the
name (`photo-v2026-11-15-031502-000.jpg`):

```
rclone lsl --s3-versions <remote>:<bucket>/<prefix>path/to/known-file.jpg
```

Or with the AWS CLI:

```
aws s3api list-object-versions --bucket <bucket> --prefix <prefix>path/to/known-file.jpg
```

Pick a timestamp _before_ the first bad version.

**2. Run the normal restore against that point in time.** rclone reads
`--s3-version-at` from the `RCLONE_S3_VERSION_AT` environment variable.
With it set, rclone treats the bucket as it looked at that moment, and
the usual three steps work unchanged:

```
export RCLONE_S3_VERSION_AT="2026-11-14 00:00:00"   # UTC
./scripts/restore.sh config/<name>.env --request --priority Bulk
./scripts/restore.sh config/<name>.env --status
./scripts/restore.sh config/<name>.env --download /path/to/restore-target
unset RCLONE_S3_VERSION_AT
```

The restore request and the download both target the specific old
version of each object, not the current junk. Files first uploaded
_after_ that timestamp don't appear in this view. Fetch those separately
without the variable once you've checked they aren't junk too.

Version-at mode is read-only, so rclone refuses to write or delete while
the variable is set. The backup user's policy includes
`s3:ListBucketVersions` and `s3:GetObjectVersion` for this, so the
`frozone` credentials (freshly rotated) are enough.

**Single file, AWS CLI only:**

```
aws s3api restore-object --bucket <bucket> --key <prefix>path/file.jpg \
  --version-id <VersionId> --restore-request '{"Days":7,"GlacierJobParameters":{"Tier":"Bulk"}}'
# ...wait ~48h...
aws s3api get-object --bucket <bucket> --key <prefix>path/file.jpg \
  --version-id <VersionId> file.jpg
```

Don't "fix" the bucket by deleting the bad versions. The backup user
can't, and the next backup overwrites them with the good local copy
anyway. Once that happens the junk becomes noncurrent and expires on its
own.

## If something doesn't match

Run `./scripts/verify.sh config/<name>.env` against the _old_ source
location, if any of it survived, to see what diverged. Otherwise take the
remote copy as authoritative. Deep Archive's durability is why this repo
exists.
