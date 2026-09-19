# blog-service

[![CI](https://github.com/asymptora/blog-service/actions/workflows/ci.yml/badge.svg)](https://github.com/asymptora/blog-service/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This repository holds the Ghost application stack that runs the Asymptora
blog: the Docker Compose definition, Ghost and Caddy configuration, and the
database backup script. It also holds this project's own RFC, architecture
decision records, and runbooks.

This is the service, not the content. No blog posts or other editorial
material live here.

**Live:** [blog.asymptora.com](https://blog.asymptora.com)

## Architecture

```
Internet
   |
   v
Cloudflare edge (TLS terminates here)
   |
   v  outbound tunnel only, no inbound port exposed
Caddy (plain HTTP)
   |
   +-- blog.asymptora.com       --> Ghost
   +-- blog-admin.asymptora.com --> Ghost (Admin)
                                      |
                                      v
                                    MySQL 8
```

Ghost, Caddy, and MySQL run as a pinned Docker Compose stack on a dedicated
LXC. The stack has no inbound network exposure of its own: every request
arrives through an outbound-only Cloudflare Tunnel operated by the
platform's infrastructure repository, and TLS terminates at Cloudflare's
edge rather than inside this stack.

## Engineering practices

- **CI required before merge.** Four checks, all required by a branch
  ruleset with no bypass, including for the repository owner: secret
  scanning (gitleaks), a guard against ever committing a plaintext `.env`,
  `yamllint`, and `docker compose config` validation.
- **Merge commits, not squash.** The ruleset allows only merge commits, so
  the atomic, Conventional Commit history built inside each pull request
  survives on `main`, rather than being collapsed into one commit per PR.
- **Secrets encrypted with an isolated key.** Credentials are SOPS-encrypted
  with `age`, using a key generated specifically for this repository rather
  than reusing the platform's own key: this is the most externally exposed
  service on the platform, so a compromise here cannot be used to decrypt
  anything belonging to the infrastructure repository.
- **Backup verified both ways, not assumed.** A nightly `mysqldump` feeds
  the platform's existing container-level backup. Both the success path and
  the failure-notification path were proven by deliberately breaking the
  database credential and confirming the alert actually arrived, not by
  reading the script and trusting it. A full restore was verified against a
  disposable, network-isolated database, row counts and content compared
  against production, and documented as a runbook.
- **RFC before build, ADR after verification.** Every decision below was
  proposed in the RFC before any implementation started, and recorded as an
  ADR only once implemented and verified, never in advance of it.

## Scope

In scope:

- The Compose stack that brings up Ghost, Caddy, and MySQL.
- Ghost, Caddy, and MySQL configuration for this deployment.
- Backup scripts and their scheduling.
- Documentation of decisions made about this service specifically, under
  `docs/`.

Out of scope: LXC provisioning and the public route on the Cloudflare
Tunnel that fronts this service. Both are owned by a separate
infrastructure repository, and any change to either is proposed there, not
here.

## Documentation

- [`docs/rfcs/0001-ghost-blog-production-deployment.md`](docs/rfcs/0001-ghost-blog-production-deployment.md):
  the accepted RFC covering installation method, container runtime,
  ingress, secrets, and backup strategy, including a later addendum
  recording why the admin domain changed shape after acceptance.
- `docs/architecture/adr/`: one ADR per decision above, written only after
  it was implemented and verified.
  - [0001](docs/architecture/adr/0001-docker-compose-over-ghost-cli.md):
    Docker Compose over Ghost-CLI.
  - [0002](docs/architecture/adr/0002-unprivileged-lxc-with-containerd-overlayfs.md):
    unprivileged LXC runtime.
  - [0003](docs/architecture/adr/0003-flat-admin-domain-behind-cloudflare-tunnel.md):
    ingress and the admin domain.
  - [0004](docs/architecture/adr/0004-mysqldump-folded-into-vzdump.md):
    backup strategy.
- `docs/runbooks/`: operational procedures for known situations, including
  [restoring the database from backup](docs/runbooks/restore-database.md).
