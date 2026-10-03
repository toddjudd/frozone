# Contributing

Fork it. I probably won't merge your pull request.

I run this as a personal homelab project and published it because the
design notes and the Terraform might save you a weekend. I built it
around my server and one backup source.

## If you do open a PR

Keep it small, explain the problem before the solution, and run the
checks first:

```
terraform fmt -check -diff   # from terraform/
terraform validate
shellcheck scripts/*.sh
```

I don't ask for a CLA.
