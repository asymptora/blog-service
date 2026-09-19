# 0001. Docker Compose over Ghost-CLI for installation

Date: 2026-09-16

## Status

Accepted

## Context

Ghost supports two installation paths. Ghost-CLI is the mature, native
path: an npm-based tool that installs Ghost directly on the host,
manages the Node process via systemd, and has first-class support for
Ghost's hosted ActivityPub service. Docker Compose is an official but
explicitly preview path, maintained by Ghost as `TryGhost/ghost-docker`,
declaring Ghost, MySQL, and a reverse proxy together in one file.

This deployment needs three services running together: Ghost itself,
MySQL 8 (the only database Ghost supports in production), and a reverse
proxy handling two public domains. Ghost-CLI installs Ghost alone;
MySQL and the proxy would need to be provisioned and wired up
separately, by hand, with no single declared source of truth for how
the three relate. Ghost-CLI's specific advantage, native ActivityPub
support, does not apply here: ActivityPub is explicitly out of scope
for this deployment.

## Decision

The stack is installed via Docker Compose, based directly on the
official `TryGhost/ghost-docker` `compose.yml`, not written from
scratch. Two deliberate deviations from upstream:

- The ActivityPub and Tinybird Analytics services (`activitypub`,
  `activitypub-migrate`, `traffic-analytics`, `tinybird-login`,
  `tinybird-sync`, `tinybird-deploy`) are removed from the file
  entirely, not left in behind an unused Compose profile. Neither
  feature is in scope, and carrying dead service definitions forward
  risks them becoming stale before they are ever needed; re-enabling
  either requires pulling the relevant definitions fresh from upstream
  under a new RFC, not uncommenting something that has been sitting
  unmaintained.
- `GHOST_VERSION` is pinned to an exact tag (`6.64.0-alpine` at time of
  writing), never the floating `${GHOST_VERSION:-6-alpine}` default
  upstream ships. Caddy and MySQL are already pinned by exact digest in
  the upstream file and needed no change.

## Consequences

Being a preview installation path means the upstream tooling itself
could change shape between releases in ways a stable, non-preview
integration would not. This is mitigated, not eliminated, by never
pulling upstream changes automatically: version and configuration
changes land as their own deliberate, reviewed pull request.

Docker Compose brought its own real dependency: a correctly installed
Docker Engine with the Compose plugin. This is not automatic on
Debian. Neither `apt install docker.io` (Debian's own package) nor
plain `apt install docker-ce` from a hastily added repository reliably
includes the `docker compose` plugin; the official Docker apt
repository with `docker-compose-plugin` explicitly listed is what
actually provides it. This cost real time to discover on both the
control workstation and the service LXC before being recognized as a
one-time, repeatable installation step rather than a fact to
rediscover.
