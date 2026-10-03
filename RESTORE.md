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
- rclone remote configured with those credentials (`rclone config`,
  provider = AWS S3, or copy an existing `rclone.conf` from a working host)

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

## If something doesn't match

Run `./scripts/verify.sh config/<name>.env` against the _old_ source
location, if any of it survived, to see what diverged. Otherwise take the
remote copy as authoritative. Deep Archive's durability is why this repo
exists.
