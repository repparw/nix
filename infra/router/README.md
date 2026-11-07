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
(released Python/Pyvider implementation of the SG-hardened TP-Link API). Protocol
information and hardware verification are maintained with the provider in
[its protocol reference](https://github.com/repparw/terraform-provider-tplink/blob/main/PROTOCOL.md).

## What is managed

| Resource                 | Address                           | Identity (import ID) |
| ------------------------ | --------------------------------- | -------------------- |
| Static DHCP reservations | `tplink_dhcp_reservation.entries` | MAC address          |
| Port-forwarding rules    | `tplink_port_forward.rules`       | rule name            |

Everything else on the router (Wi-Fi, DHCP server settings, WAN, firewall,
admin credentials, reboot) is **deliberately unmanaged** — the provider
implements no write path for it, so no plan can ever alter management
access, wireless, or the LAN's DHCP server configuration.

Both managed resources carry `lifecycle { prevent_destroy = true }`.
This blocks planned destruction while their resource blocks remain configured.
Removing an entire resource block also removes this protection, so inspect
every plan before approval.

## Inventory

The commands below that use `python -m tplink_py.inventory` must be run from the
pinned provider checkout described in **Setup**, not from this OpenTofu root.

`inventory.auto.tfvars` and `imports.tf` are **generated** from the live
router by the provider's Python inventory tool and are gitignored — they
contain the LAN device inventory (MACs, hostnames). Only the `.example`
files are committed.

Keep the existing private inventory and state during a provider change.
An existing, already-adopted state needs a read-only plan, not regenerated
imports or inventory.

For a deliberate inventory reconciliation, first verify both RSA keys on a
trusted LAN connection with the source checkout and environment described in
**Setup**:

```sh
python -m tplink_py.keyprobe --host http://192.168.0.1
```

Compare both reported SHA-256 SPKI fingerprints with independent trusted
evidence. The probe reads public keys without logging in. Set
`TPLINK_PASSWORD`, `TPLINK_PASSWORD_KEY_PIN`, and `TPLINK_AUTH_KEY_PIN`
locally through the approved credential source before proceeding. The
inventory utility uses `TPLINK_*` names, not `TF_VAR_*`.

Generate into a *private staging directory*, never directly over the live
`inventory.auto.tfvars` or `imports.tf`:

```sh
umask 077
stage="$(mktemp -d)"
python -m tplink_py.inventory --dry-run --dir "$stage"
python -m tplink_py.inventory --dir "$stage"
diff -u ~/Projects/nix/infra/router/inventory.auto.tfvars "$stage/inventory.auto.tfvars" || true
diff -u ~/Projects/nix/infra/router/imports.tf "$stage/imports.tf" || true
# Inspect every change; copy approved files manually, then remove the stage.
```

Inventory generation logs into the router for read operations. A `--dry-run`
prevents file writes but still requires verified keys and authentication.
Do not treat missing private files as permission for implicit initial
adoption. Stage and separately review any desired-configuration change,
including out-of-band edits.

## Setup

The provider is pinned to release `0.1.0` from the
[OpenTofu registry](https://search.opentofu.org/provider/repparw/tplink/latest).
Run `tofu init` to download it and verify its signed checksums using the
committed `.terraform.lock.hcl`. No local plugin build is needed.

The release supports Linux amd64, macOS arm64, and Windows amd64;
Linux arm64 is not supported. On NixOS the frozen Linux executable needs
`programs.nix-ld.enable = true`.

Existing state uses the same provider address, so no `state replace-provider`
is needed. The old Go build was also labelled `0.1.0`, but predates the
released Python implementation. Remove custom CLI `dev_overrides` or filesystem
mirrors for this provider and the old root-local `.terraform/` cache. Replace
any old local-build lockfile with the committed release lockfile, then run
`tofu init`. Review `tofu plan` before applying the implementation change.

For this OpenTofu root, both independently enrolled RSA key fingerprints are
required even though the public provider exposes optional pin attributes.
Supply `TF_VAR_password_key_pin` and `TF_VAR_auth_key_pin` alongside
`TF_VAR_router_password` through local secret inputs; never commit their
values. Pin validation rejects null, empty and malformed fingerprints.
Verify both keys with `tplink_py.keyprobe` on the trusted LAN before the
first provider login. OpenTofu and the Python inventory utility use
different environment variable names.

Only key enrollment and inventory generation require a source checkout and
Python environment:

```sh
git clone https://github.com/repparw/terraform-provider-tplink
cd terraform-provider-tplink
git checkout v0.1.0
python -m venv .venv
. .venv/bin/activate
pip install ./python
```

## Read-only validation and future imports

For an existing, already-adopted state, take a local backup of
`terraform.tfstate` and `inventory.auto.tfvars` using Alpha's documented
procedure. Remove any obsolete local Go provider override or cache, then
initialize the released provider and require a zero-change plan:

```sh
cd ~/Projects/nix/infra/router
# Supply the router password and both enrolled TF_VAR_*_key_pin values.
tofu init
tofu providers schema -json > /dev/null
tofu plan -detailed-exitcode
```

Exit code 0 means no changes; 1 means an error; 2 means proposed changes.
Do not apply a nonzero plan, replace state addresses, or regenerate the
private inventory as part of provider validation. Confirm the signed registry
provider is selected, not an old local Go executable.

A *separate, explicitly approved* import of new router entries may follow
later. Stage and inspect inventory first, then create and inspect a saved
plan rather than running an unreviewed `tofu apply`:

```sh
cd ~/Projects/nix/infra/router
tofu plan -out=import-review.tfplan
tofu show import-review.tfplan
tofu show -json import-review.tfplan | jq -e '
  all(.resource_changes[]?;
    .mode != "managed" or
    (.change.actions == ["no-op"] and .previous_address == null)
  )
'
# STOP unless only the intended imports appear, with no managed resource writes.
# Only after separate approval to update the local state:
# tofu apply import-review.tfplan
```

The machine-readable check rejects creates, updates, deletes, replacements,
and moves of managed resources. It is a guard, not authorization: inspect
the import identities and the entire plan. An approved import reads router
configuration and updates local OpenTofu state. It must not create or
modify router rows. Apply the exact reviewed plan, not a new implicit plan.
Saved plans can contain sensitive data and are gitignored (`*.tfplan`).

## Destructive-operation audit

What a plan/apply here can and cannot do:

- **Cannot normally** delete an existing reservation or port forward
  while its `prevent_destroy` resource block remains configured.
  Removing the entire block removes that safeguard; inspect the plan.
- **Cannot** change Wi-Fi, DHCP server settings, DNS, WAN, admin password,
  or reboot: the provider has no write implementation for those forms, and
  no resource in this root references them.
- **Can** evict an interactive web-UI session when logging in (the router
  allows exactly one admin login).
  Roughly 12 failed logins trigger a ~2 h lockout — the provider never
  retries failed logins.
- **Can** update a reservation or forward in place (IP, ports, protocol,
  enabled, hostname — see the device-name caveat below). Updates are
  verified by read-back after the write.
- **Cannot** replace a row while `prevent_destroy` is in force: changing a
  reservation MAC or a forward's name requires a replacement with a destroy
  step, so the plan fails. To authorize such a replacement, explicitly remove
  the safeguard and review the full plan. Once protection is removed, the old
  mapping may be deleted before its replacement succeeds; a failed apply could
  leave the device without its reserved IP or the forward unavailable.

Deliberate removal or identity replacement is an explicit three-step process:

1. Remove the entry from `inventory.auto.tfvars`, then run `tofu plan` —
   it must fail with `prevent_destroy`.
2. Only for the specifically approved operation, temporarily remove the
   applicable `prevent_destroy` safeguard from `router.tf`. Save a plan
   with `tofu plan -out=reviewed.tfplan` and inspect the full output with
   `tofu show reviewed.tfplan`. Verify the exact rows and all actions.
3. Only after separate explicit authorization, run
   `tofu apply reviewed.tfplan`, then restore `prevent_destroy` at once.
   Do not replan with a plain `tofu apply` after reviewing a saved plan.

## State

Local state (`terraform.tfstate`, gitignored, 0600 via umask of the tool)
contains MACs, hostnames, and LAN IP addresses — device inventory, no
credentials (the password lives only in `TF_VAR_router_password`).

Alpha's home-state backup stages both `terraform.tfstate` and the gitignored
`inventory.auto.tfvars` for the HDD mirror and daily encrypted offsite upload.
`imports.tf` and provider caches remain excluded. The inventory is desired
configuration, so backing it up preserves edits not yet applied to the router;
it is not committed to Git. The backup stages an inventory file when present
but does not require it to exist. After any apply, import, or inventory edit,
capture fresh backups as with the OCI stack (see the
[fleet operations runbook](../../docs/runbooks/fleet-operations.md)) and
confirm both `infra/router/terraform.tfstate` and
`infra/router/inventory.auto.tfvars` appear in the staged generation.
Re-running the Python inventory generator and imports is a recovery fallback,
not an automatic migration step. It can silently adopt out-of-band drift, so
stage and compare results against the last trusted inventory first.

## Reservation device names are client-controlled

The AX23 v2 derives a reservation's device-name fields (`hostname` and
`comment`) from the connected client's DHCP hostname. For an online device,
both insert and update read back with the device-reported name, so a custom
label in `inventory.auto.tfvars` never reaches the router: the apply fails
with the provider's "inconsistent result after apply" guard (the MAC→IP
mapping itself is written and stays correct; the failed resource may need
`tofu untaint`). To rename a device, change the DHCP hostname the device
itself reports and let it reconnect — the router row, tofu state, and a
subsequent plan converge without a write. Rows created for offline or
unknown devices keep the name they were created with.

## Reviewing drift

`tofu plan` re-reads the router. Because the inventory was generated from
the live rows, any diff means someone changed the router out of band (web
UI, Tether app, firmware upgrade) or the provider changed behavior.
Investigate before adopting: approved console edits should first be
regenerated into a private staging directory, reviewed against
`inventory.auto.tfvars`, and copied manually; mistaken console edits should
be reverted on the router.

## Firmware upgrades

TP-Link has changed the router API's auth scheme between firmware
generations before (classic → SG-hardened → simplified). After any firmware
upgrade, run `tofu plan` and expect possible provider breakage; the
provider fails with a clear authentication error rather than retrying
(lockout safety). Update `terraform-provider-tplink` first, plan, and only
then consider apply.
