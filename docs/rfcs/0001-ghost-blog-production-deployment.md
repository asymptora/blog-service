# RFC 0001: Ghost Blog Production Deployment

**Status:** Accepted
**Repository:** asymptora/blog-service
**Authors:** Higor Cazuza, Janaína Cazuza
**Proposed:** 2026-09-16
**Accepted:** 2026-09-16

## Summary

This RFC proposes the production deployment of Ghost as the engine behind the
Asymptora blog, self-hosted on the Asymptora homelab and installed through
Ghost's official Docker Compose tooling. It defines the repository's scope,
the technical decisions required to run Ghost reliably on a two-node Proxmox
homelab with a constrained network link, and the delivery process this
repository will follow.

## Motivation

The Asymptora platform hosts services built by the engineers who operate it.
Ghost is the first of these. It needs a home that is separate from the
platform repository, since platform concerns (node configuration, network
topology, container provisioning, the ingress tunnel) and application
concerns (the blog's own runtime configuration and operational documentation)
have different audiences, different release cadences, and different
ownership.

This RFC exists to settle every open technical question before implementation
starts, so that the work that follows can be broken into milestones and
issues without needing to revisit foundational decisions mid-flight.

## Goals

- A production Ghost instance, reachable at a public domain, backed by
  MySQL 8, running as a set of Docker containers inside a dedicated LXC on
  the homelab.
- Two staff accounts with full editorial and administrative capability.
- A repository structure, CI pipeline, and branch policy consistent with the
  standard already established for `asymptora/infra`.
- A deployment that a technical reviewer can inspect end to end: RFC, the
  resulting implementation, and the ADRs that record what was actually
  built.

## Non-Goals

- **ActivityPub / Social Web.** Not enabled, hosted or self-hosted. Not
  planned for revisit unless a future RFC changes this.
- **Web Analytics (Tinybird).** Not enabled. Traffic insight is not a
  requirement for this deployment.
- **Newsletter and bulk email to readers.** Out of scope entirely. No
  Mailgun or equivalent bulk-mail provider is introduced by this RFC.
- **Ghost Members.** Disabled. See "Reader features" below.

## Scope and Repository Boundaries

This repository owns the Ghost application stack: the Docker Compose
definition, Ghost and Caddy configuration, the database backup script, and
this project's own documentation (RFCs, ADRs, runbooks).

It does **not** own LXC provisioning or the public route on the ingress
tunnel. Both remain the responsibility of `asymptora/infra`, consistent with
that repository's stated platform boundary. Any change to either is
requested there, through a pull request in that repository, regardless of
where this RFC or its implementation lives.

## Detailed Design

### Installation method

Ghost is installed using its official Docker Compose tooling rather than
Ghost-CLI. Docker Compose is still a preview installation path upstream, but
it is the only path that keeps the stack (Ghost, Caddy, MySQL) declared in
one place and reproducible from a clean checkout, which matters more here
than the maturity gap. Ghost-CLI's advantage, native support for the
hosted ActivityPub service, is not relevant given the non-goals above.

### Database

MySQL 8 is the only database Ghost supports in production. This is a
platform constraint, not a choice among alternatives: SQLite is
development-only, and MariaDB is explicitly discouraged upstream. MySQL runs
as its own container in the same Compose stack, with a dedicated data
volume. No other service shares this database instance.

### Compute

A dedicated LXC on `pve1`, sized at 2 vCPU (shared), 2GB RAM, 512MB to 1GB
swap, and 20GB of disk. This sizing accounts for Ghost, MySQL's default
memory footprint (the dominant consumer on a small host), Caddy, and normal
Ubuntu baseline overhead, with headroom for image churn across updates.
Provisioning this LXC is out of scope for this repository; it is requested
through a pull request in `asymptora/infra`, which owns the provisioning
automation.

### Container runtime

The LXC runs unprivileged, with `nesting=1,keyctl=1` enabled, targeting the
`overlay2` storage driver. The homelab's storage backend for LXC root disks
is LVM-thin, which supports `overlay2` natively without the `fuse-overlayfs`
fallback that is known to break Proxmox backups.

If `docker info` does not report `overlay2` as the storage driver at
implementation time, the documented contingency is to convert the LXC to
privileged rather than debug `fuse-overlayfs` in place. This is a
deliberate fallback, decided here, not an improvisation to make during
installation.

### Image versioning

Container images are pinned to an exact tag (for example
`ghost:6.<minor>.<patch>-alpine`), never a floating tag such as `ghost:6`.
Version bumps are a deliberate pull request, reviewed like any other change,
not a side effect of a routine `docker compose pull`.

### Networking and domains

The public site is served at `blog.asymptora.com`. Ghost Admin is served at
a nested subdomain, `admin.blog.asymptora.com`, kept separate from the
public site per Ghost's own guidance on privilege-escalation surface when
admin and front-end share a domain. Both routes go through the Cloudflare
Tunnel already operated by `asymptora/infra`; the new public routes are
requested there via pull request, per that repository's ownership of tunnel
routes.

Caddy, included in the official Compose stack, handles Host-based routing
between the two domains and speaks plain HTTP internally. TLS terminates at
Cloudflare's edge; Caddy is not configured to attempt certificate issuance
of its own, since the tunnel's outbound-only model gives it no way to
complete an HTTP-01 challenge.

### Transactional email

SMTP is provided by Zoho Mail, using the domain's existing mailbox and an
application-specific password (2FA is already enabled on that account, so
the account's primary password is never used by Ghost). This covers Ghost's
transactional mail only: staff invitations and password resets. No
dedicated transactional email provider is introduced, since Members is
disabled and the only recipients of transactional mail are the two staff
accounts below.

### Reader features

Ghost's Members feature is turned off. The blog is read-only: no public
sign-up form, no member accounts, no native comments tied to member
identity. This is a deliberate configuration change, not merely the absence
of a newsletter, and is called out explicitly so it is verifiable in the
running configuration rather than inferred from what wasn't built.

### Staff accounts

Two staff accounts, both with full access:

- **Owner:** Higor Cazuza, as the engineer accountable for the platform and
  this deployment.
- **Administrator:** Janaína Cazuza, with the same level of access as the
  Owner. She owns the frontend and the site's visual integration, including
  linking the blog into the broader site she is building, and needs
  unrestricted access to theme, settings, and content to do that work
  without depending on the Owner for day-to-day changes.

### Backups

The database is dumped locally (`mysqldump`) to a path inside the LXC's own
filesystem on a schedule that runs before the nightly `vzdump` window. This
keeps the blog under the same backup mechanism already used for every other
container on the homelab (asynchronous `vzdump` from `pve1` to `pve2`, five
generations retained), rather than introducing a second, blog-specific
backup channel. A full-container snapshot and a logical database dump
together cover both a total-loss restore and a content-only restore,
without adding new infrastructure to maintain.

### Secrets management

All credentials (database passwords, the Zoho application password) are
held in a single `.env` file, encrypted at rest with SOPS and age, and
decrypted only on the target host. No plaintext secret is ever committed.
Database credentials, once the database is initialized, are never changed
without a full reinitialization, since Ghost's Docker tooling does not
support rotating them in place.

## Repository and Delivery Process

- **Visibility:** public repository and public GitHub Project, consistent
  with `asymptora/infra`.
- **License:** MIT, matching `asymptora/infra`.
- **Layout:** `docs/rfcs/`, `docs/architecture/adr/`, `docs/runbooks/`
  (following the same `RUNBOOK-TEMPLATE.md` structure as `asymptora/infra`),
  plus a `rfc-work-item` issue template.
- **Branch policy:** a ruleset on `main` requiring an open pull request,
  passing status checks, squash-only merges, and signed commits, with no
  bypass. This mirrors the ruleset already in place on `asymptora/infra`.
- **CI:** secret scanning with the gitleaks CLI (not the GitHub Action),
  `docker compose config` validated against a checked-in `.env.example`
  with placeholder values, `yamllint` over the Compose file and workflow
  definitions, and a dedicated check that fails the build if `.env` is ever
  tracked by git, as a second layer of protection alongside secret
  scanning and `.gitignore`.

## Alternatives Considered

- **Ghost-CLI native install.** Rejected in favor of Docker Compose; see
  "Installation method" above.
- **Self-hosted ActivityPub and Web Analytics.** Rejected; both add
  services and memory pressure to a 2GB LXC for capability that is out of
  scope. Revisiting either requires a new RFC, not a configuration toggle.
- **A dedicated backup channel over NFS to `pve2`**, mirroring how other
  large or high-churn data is handled on the homelab. Rejected for this
  service: Ghost's data volume is small, and folding it into the existing
  `vzdump` mechanism avoids a second system to operate and monitor.

## Rollout Plan

This RFC does not create milestones or issues; those are derived from it
once accepted. At a high level, the resulting work is expected to fall into
three phases:

1. **Container stack.** LXC provisioned in `infra`, Docker installed and
   verified against the `overlay2` contingency above, Compose stack brought
   up locally with a placeholder domain.
2. **Ingress and admin domain.** Tunnel routes added in `infra` for both
   domains, Caddy routing verified, SMTP verified end to end with a real
   staff invite.
3. **Backup and hardening.** `mysqldump` scheduling in place and verified
   against a real restore, CI and branch ruleset active, ADRs written for
   every decision above once it is actually implemented and verified, not
   before.

## Open Questions

None outstanding at the time of writing. Every question raised during the
planning of this RFC has a decision recorded above.

## Future Work (Deferred)

- **Organization-wide ruleset.** Not adopted now; requires a paid GitHub
  plan and only pays off once more repositories exist under the
  organization. The per-repository ruleset can be exported and reused as a
  JSON file in the meantime.
- **ActivityPub, Web Analytics, Members, newsletter.** All explicitly out
  of scope (see Non-Goals). Any future interest in one of these requires a
  new RFC, evaluated against the LXC's resource budget at that time.

## References

- Ghost documentation: https://docs.ghost.org
- Ghost Docker Compose tooling: https://github.com/TryGhost/ghost-docker
