# 0002. Unprivileged LXC with Docker's containerd overlayfs snapshotter

Date: 2026-09-17

## Status

Accepted

## Context

`asymptora/infra`'s own ADR 0002 sets LXC as the default workload unit
for this homelab, unprivileged unless justified otherwise. Running
Docker inside an LXC container specifically raises a further question:
Docker's preferred storage driver historically depends on kernel
capabilities (overlay filesystem support, and access to the kernel
keyring) that an unprivileged container does not expose by default.
Getting this wrong silently degrades Docker to a much slower,
copy-on-write-less storage driver (`vfs`) rather than failing loudly.

`infra`'s `roles/lxc_provision` role already set `nesting=1` for every
container it creates, needed for modern systemd to manage services
inside a container at all. It had no equivalent for `keyctl`, because
no workload provisioned through it had needed kernel keyring access
before this one.

## Decision

The Ghost LXC (CTID 105, `pve1`, internal `10.10.10.0/24` network) runs
unprivileged, with both `nesting=1` and `keyctl=1` set at creation.
`keyctl` was added to `lxc_provision` as an opt-in feature, defaulting
to `false` unlike `nesting`, since only a container running a
Docker-based workload needs it; turning it on for every container
provisioned by the role would widen kernel syscall surface for
containers that have no use for it.

Docker Engine 29.8.1, installed from the official Debian apt
repository, was verified with `docker info -f '{{ .DriverStatus }}'` to
report `driver-type: io.containerd.snapshotter.v1`, with `docker info`
itself reporting `Storage Driver: overlayfs`. This is the modern,
correct outcome. It is not the same string the original RFC's
contingency check named (`overlay2`): Docker Engine 29.0 changed the
default new-install storage backend to the containerd image store,
whose `overlayfs` snapshotter is the direct successor to the legacy
`overlay2` graph driver, described by Docker's own documentation as
functionally analogous to it. The actual failure signal this
contingency exists to catch is the storage driver falling back to
`vfs`, which did not happen. The privileged-LXC fallback documented as
a contingency was not needed.

Installing Docker itself inside the LXC is not automated as an Ansible
role in `infra`, unlike LXC provisioning itself. The Proxmox host has
no backup covering a reinstall or hardware replacement, which is why
its configuration needs to be fully reproducible from Ansible. The LXC
guest's internals, including whatever is installed inside it, are
already covered end to end by `vzdump`'s whole-container backup;
automating a one-time installation step that a full-container restore
already recovers adds process overhead without adding real recovery
capability.

## Consequences

Any future service LXC provisioned on hardware running a Docker Engine
at or beyond version 29 should expect to see `overlayfs`, not
`overlay2`, in `docker info`, and should treat `vfs` as the real
signal to investigate, not the absence of the exact string `overlay2`.
This corrects language in RFC-0001, which predates this discovery.

`lxc_provision`'s `keyctl` support is now available to any future
container that needs it, not just this one.
