# 0004. Database backup folded into the existing vzdump mechanism

Date: 2026-09-19

## Status

Accepted

## Context

The Ghost MySQL database needed to be recoverable independent of a
full container restore, without introducing a backup mechanism this
platform does not already operate. `asymptora/infra` already runs
`vzdump` nightly at 03:00 (America/Sao_Paulo) from `pve1`, retaining
five generations per container. A separate channel, for example
syncing a database dump to `pve2` over NFS the way other large or
high-churn data is handled, was considered and rejected: this
service's data volume is small, and a second system to operate and
monitor buys no real recovery capability that folding into `vzdump`
does not already provide.

## Decision

A `mysqldump` runs on a systemd timer inside the LXC, at 02:00, one
hour ahead of `pve1`'s 03:00 `vzdump` window, dumping the Ghost
database from inside the running `db` container
(`--single-transaction`, avoiding any table lock against the live
site) to a gzip file on the LXC's own filesystem. `vzdump` picks this
file up automatically as part of its normal whole-container backup;
no second backup channel exists.

Failure is signalled to the same `ntfy.sh` topic `infra` already uses
for its own backup failure notifications, so both land in one place
the operators already watch. The topic value itself crossed from
`infra`'s encrypted secrets into `blog-service`'s own, deliberately:
`blog-service` holds its own separate `age` key, so that a compromise
inside the Ghost LXC, the most exposed workload on this platform,
cannot lead to decrypting `infra`'s secrets. Only the topic value
moved, copied by hand once, never the key material.

As with Docker's own installation, this is not an Ansible role in
`infra`. The LXC guest's internals, this script included, are already
covered by `vzdump`'s whole-container backup; the reproducibility that
Ansible exists to guarantee for the Proxmox hosts themselves has no
equivalent gap to fill here.

## Consequences

Both the success and failure paths were verified by deliberately
causing each, not by reading the script and assuming it correct. Two
real bugs surfaced doing this, and both are worth recording as the
kind of failure that reading code does not catch:

- The encrypted `.env` was updated with the notification topic in its
  own pull request, but the running `.env` on the LXC was never
  redeployed afterward. The first deliberate failure test produced no
  notification at all, silently, because the value it depended on
  simply was not there yet.
- `notify_failure` itself aborted under the script's `set -u` when the
  notification topic was unset, failing on variable expansion before
  `curl` ever ran. The one function that exists to raise an alarm on
  failure could itself fail silently, which is the worst failure mode
  a notification path can have. It now checks explicitly and logs to
  stderr when the topic is missing, rather than crashing.

A restore was verified against a disposable, network-isolated MySQL
container, row counts and post content both confirmed identical to
production, documented as `docs/runbooks/restore-database.md` for
whoever needs to do this for real.
