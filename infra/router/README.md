# Router infrastructure (OpenTofu)

This is a **separate OpenTofu root** adopting the TP-Link Archer AX23 v2's
DHCP reservations and port-forwarding rules into declarative management. It
is deliberately split from the OCI stack in the parent directory:

- **Separate state file** — a router mistake can never plan or destroy OCI
  resources, and an OCI apply can never touch the router.
- **Separate apply boundary** — `tofu plan`/`apply` here reads and manages
  only `192.168.0.1`.
- Different risk profile: the OCI stack manages cloud resources; this root
  manages the device that provides the LAN everyone else lives on.

Provider: [`repparw/terraform-provider-tplink`](https://github.com/repparw/terraform-provider-tplink)
(native Go implementation of the SG-hardened TP-Link API; protocol and
verification history in
[`docs/research/archer-ax23-api-opentofu.md`](../../docs/research/archer-ax23-api-opentofu.md)).

## What is managed

| Resource                 | Address                           | Identity (import ID) |
| ------------------------ | --------------------------------- | -------------------- |
| Static DHCP reservations | `tplink_dhcp_reservation.entries` | MAC address          |
| Port-forwarding rules    | `tplink_port_forward.rules`       | rule name            |

Everything else on the router (Wi-Fi, DHCP server settings, WAN, firewall,
admin credentials, reboot) is **deliberately unmanaged** — the provider
implements no write path for it, so no plan can ever alter management
access, wireless, or the LAN's DHCP server configuration.

Both managed resources carry `lifecycle { prevent_destroy = true }`: a
`tofu destroy`, or any plan that would delete a row, fails at plan time.

## Inventory

`inventory.auto.tfvars` and `imports.tf` are **generated** from the live
router by the provider's `tfinventory` tool and are gitignored — they
contain the LAN device inventory (MACs, hostnames). Only the `.example`
files are committed.

Regenerate after deliberate out-of-band router changes:

```sh
TPLINK_PASSWORD=... go run ./cmd/tfinventory -dir ~/Projects/nix/infra/router
```

## Setup

The provider is not published to a registry yet; install it as a local
plugin (OpenTofu picks up `~/.tofu.d/plugins` automatically for
`-plugin-dir` runs):

```sh
git clone https://github.com/repparw/terraform-provider-tplink
cd terraform-provider-tplink
go build -ldflags "-X main.version=0.1.0" -o terraform-provider-tplink .
mkdir -p ~/.tofu.d/plugins/registry.opentofu.org/repparw/tplink/0.1.0/linux_amd64
cp terraform-provider-tplink ~/.tofu.d/plugins/registry.opentofu.org/repparw/tplink/0.1.0/linux_amd64/
```

## Adopting the current configuration

```sh
cd ~/Projects/nix/infra/router
# one-time: generate inventory.auto.tfvars + imports.tf (see Inventory)
export TF_VAR_router_password="..."
tofu init -plugin-dir=~/.tofu.d/plugins
tofu plan     # must read "Plan: N to import, 0 to add, 0 to change, 0 to destroy"
tofu apply    # performs the imports; reads only — no router writes
tofu plan     # must end in "No changes"
```

The import apply touches the router with read operations only (login +
reservation/forward loads); it changes no router state. State is written
locally.

## Destructive-operation audit

What a plan/apply here can and cannot do:

- **Cannot** delete a reservation or port forward: `prevent_destroy` fails
  any plan containing a destroy on these resources, including `tofu
destroy`.
- **Cannot** change Wi-Fi, DHCP server settings, DNS, WAN, admin password,
  or reboot: the provider has no write implementation for those forms, and
  no resource in this root references them.
- **Cannot** interrupt management access: the worst case is evicting an
  interactive web-UI session (the router allows exactly one admin login).
  Roughly 12 failed logins trigger a ~2 h lockout — the provider never
  retries failed logins.
- **Can** update a reservation or forward in place (IP, ports, protocol,
  enabled, hostname). Updates are verified by read-back after the write.
- **Can** replace a row if its identity changes (MAC for reservations, name
  for forwards are force-replaced): the old row is deleted and the new one
  created. Until the replacement apply completes, the old mapping is gone —
  for reservations this means a device could pick a pool address on its
  next renewal if the apply fails midway. Review such plans in full.

Deliberate removal of a managed row is a two-step, on purpose:

1. Remove the entry from `inventory.auto.tfvars`, apply — the plan will
   fail with `prevent_destroy`.
2. Temporarily comment the `lifecycle { prevent_destroy = true }` block in
   `router.tf`, apply, restore the block, commit. This friction is the
   point: row deletion should never be an accident.

## State

Local state (`terraform.tfstate`, gitignored, 0600 via umask of the tool).
It contains MACs, hostnames, and LAN IP addresses — device inventory, no
credentials (the password lives only in `TF_VAR_router_password`). The
alpha home-state backup stages `Projects/nix/**` before the daily encrypted
offsite upload; after any apply or import, capture a fresh backup as with
the OCI stack (see the
[fleet operations runbook](../../docs/runbooks/fleet-operations.md)) and
confirm the new `infra/router/terraform.tfstate` path appears in the staged
generation. Re-running `tfinventory` + imports is the state-recovery
fallback, with the usual caveat: it silently adopts out-of-band drift.

## Reviewing drift

`tofu plan` re-reads the router. Because the inventory was generated from
the live rows, any diff means someone changed the router out of band (web
UI, Tether app, firmware upgrade) or the provider changed behavior.
Investigate before adopting: console edits that you want to keep go into
`inventory.auto.tfvars` (regenerate), console edits that were mistakes get
reverted on the router.

## Firmware upgrades

TP-Link has changed the router API's auth scheme between firmware
generations before (classic → SG-hardened → simplified). After any firmware
upgrade, run `tofu plan` and expect possible provider breakage; the
provider fails with a clear authentication error rather than retrying
(lockout safety). Update `terraform-provider-tplink` first, plan, and only
then consider apply.
