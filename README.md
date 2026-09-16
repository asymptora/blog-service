# blog-service

This repository holds the Ghost application stack that runs the Asymptora
blog: the Docker Compose definition, Ghost and Caddy configuration, and the
database backup script. It also holds this project's own RFCs, architecture
decision records, and runbooks.

This is the service, not the content. No blog posts or other editorial
material live here.

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

- `docs/rfcs/`: proposals not yet decided.
- `docs/architecture/adr/`: decisions already implemented and verified.
- `docs/runbooks/`: operational procedures for known situations.
