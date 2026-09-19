# 0003. Flat admin subdomain, plain HTTP behind the Cloudflare Tunnel

Date: 2026-09-17

## Status

Accepted

## Context

The public site and Ghost Admin needed to be reachable on separate
domains, per Ghost's own guidance on the privilege-escalation surface
of sharing one domain between public and administrative interfaces,
without opening any inbound port on the network, consistent with how
every other service on this platform is exposed.

RFC-0001 originally specified a nested admin subdomain,
`admin.blog.asymptora.com`. Adding the corresponding route in
Cloudflare's dashboard failed the TLS handshake at the edge
(`SSL routines::sslv3 alert handshake failure`), while the equivalent
route for the flat `blog.asymptora.com` succeeded immediately.
Cloudflare's own documentation confirms the cause: the free Universal
SSL certificate covers a zone's root domain and exactly one level of
subdomain, not two. Extending coverage to a second level requires
Cloudflare's Advanced Certificate Manager, a paid add-on billed per
domain per month.

## Decision

Caddy, inside the Compose stack, is configured for plain HTTP only, no
local certificate issuance. Both the public site and Ghost Admin proxy
to the same Ghost origin (`ghost:2368`), distinguished by the `Host`
header Caddy already receives; `X-Forwarded-Proto: https` is forced
toward Ghost so it generates correct absolute URLs despite the
Caddy-to-Ghost hop itself being plain HTTP. TLS terminates entirely at
Cloudflare's edge, reached through the existing outbound-only tunnel
already operated by `asymptora/infra`, the same tunnel every other
service on this platform uses.

The admin domain is flat, `blog-admin.asymptora.com`, not nested, to
stay within Cloudflare's free certificate coverage. This was chosen
over paying for Advanced Certificate Manager, consistent with this
project's general preference for a free option that is functionally
equivalent over a paid one purely for naming aesthetics: the same
reasoning that chose an outbound tunnel over port forwarding, and the
existing Zoho mailbox over introducing a new transactional email
provider.

## Consequences

Any future service's admin subdomain on this platform should default
to the same flat pattern (for example, `api-x-admin.asymptora.com`,
not `admin.api-x.asymptora.com`) unless a future RFC deliberately
budgets for Advanced Certificate Manager. This reverses the nested
naming convention RFC-0001 originally proposed as a scalable pattern
for future services; that reasoning did not account for this
certificate limit at the time it was written.

The domain flattening also surfaced an unrelated process gap, worth
recording here since it shaped how the fix was verified rather than
just applied: an early attempt to update `ADMIN_DOMAIN` in the
encrypted `.env` did not actually persist the edit before
re-encrypting, so the value committed and even redeployed still read
the old domain. It was caught only by checking the environment inside
the running container directly (`docker exec ghost-1 env`) rather than
trusting that the external route responding meant the internal
configuration had changed. That check is now the standard way this
kind of change is verified, not an incidental one.
