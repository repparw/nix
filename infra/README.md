# OCI infrastructure (OpenTofu)

This directory is the OpenTofu root module adopting Epsilon's existing Oracle
Cloud resources into declarative management. It covers cloud resources only:
the operating system, services, persistence, and backups remain owned by the
NixOS configuration in `modules/`.

| OpenTofu manages         | NixOS manages                |
| ------------------------ | ---------------------------- |
| OCI compute instance     | Operating system             |
| OCI networking           | Services and packages        |
| Cloud storage resources  | Impermanence and persistence |
| Cloud resource lifecycle | Backups and monitoring       |

## Managed resources

Everything lives in the tenancy root compartment of `repparw`
(region `sa-santiago-1`, availability domain `rTqj:SA-SANTIAGO-1-AD-1`); the
tenancy contains no other compartments or instances.

| Resource                              | Address                               | Notes                                                  |
| ------------------------------------- | ------------------------------------- | ------------------------------------------------------ |
| Compute instance `epsilon`            | `oci_core_instance.epsilon`           | `VM.Standard.A1.Flex`, 2 OCPU / 12 GB                  |
| Reserved public IP `epsilon-reserved` | `oci_core_public_ip.epsilon`          | `146.181.42.97`, attached to the primary VNIC          |
| VCN `vcn-20260128-1948`               | `oci_core_vcn.main`                   | 10.0.0.0/16                                            |
| Subnet                                | `oci_core_subnet.main`                | 10.0.0.0/24, public                                    |
| Internet gateway                      | `oci_core_internet_gateway.main`      | default gateway of the VCN                             |
| Default route table                   | `oci_core_default_route_table.main`   | 0.0.0.0/0 → internet gateway                           |
| Default security list                 | `oci_core_default_security_list.main` | SSH 22, HTTPS 443 (traefik edge), mosh 60002/udp, ICMP |
| Default DHCP options                  | `oci_core_default_dhcp_options.main`  | VCN resolver + search domain                           |

Intentionally unmanaged:

- **Boot volume** (`ocid1.bootvolume.oc1.sa-santiago-1.abzwgljromeycebcjj2nftl5zmo2glsg5akcjl27j4qjgucilwf6jxkjy44q`,
  200 GB, 10 VPUs/GB): `oci_core_boot_volume` requires a `source_details`
  block that the OCI API never reports for instance-launched boot volumes, so
  adopting it always plans a forced replacement
  ([oracle/terraform-provider-oci#2422](https://github.com/oracle/terraform-provider-oci/issues/2422)).
  Its size and performance are pinned by the instance's `source_details`
  (`boot_volume_size_in_gbs`, `boot_volume_vpus_per_gb`) instead. Revisit when
  the upstream issue is fixed.
- **Primary VNIC and its private IP**: part of the instance resource; the
  reserved public IP above covers the address assignment.
- The Ubuntu launch image: pinned by OCID in `compute.tf`. It is historical
  (NixOS was installed in place with nixos-infect) and following Oracle's
  image list would surface new images as forced replacements.

## Authentication

The provider authenticates through the local OCI CLI configuration:

- `~/.oci/config`, profile `DEFAULT` (override with `-var oci_profile=...`).
- The compartment OCID is supplied via `terraform.tfvars` (gitignored):

  ```hcl
  compartment_id = "ocid1.tenancy.oc1..<tenancy>"
  ```

No credentials live in this repository. State files, plan artifacts, and
local variable values are excluded via `.gitignore`.

## Usage

```sh
cd infra
tofu init            # installs the provider per .terraform.lock.hcl
tofu plan            # review drift and pending changes
tofu fmt             # format before committing
tofu validate        # static configuration checks
```

`tofu apply` is manual and deliberate. Nothing here runs automatically, and
CI only runs formatting and validation — never an apply.

## State

State is local (`terraform.tfstate`, gitignored). It contains OCIDs, IP
addresses, and the instance's SSH _public_ key — nothing secret, but it is
still excluded from Git. There is no remote backend: for a module this small,
state is fully re-derivable from the live infrastructure, and re-importing
(see below) is the recovery path. Keep a copy of the local state if you want
faster recovery, and treat any copy as sensitive.

## Recovering state

`imports.tf` records the import mapping and is inert once resources are in
state. To rebuild state from scratch (or after adding an account):

```sh
cd infra
tofu init
tofu import oci_core_instance.epsilon          ocid1.instance.oc1.<region>...
tofu import oci_core_public_ip.epsilon         ocid1.publicip.oc1.<region>...
tofu import oci_core_vcn.main                  ocid1.vcn.oc1.<region>...
tofu import oci_core_subnet.main               ocid1.subnet.oc1.<region>...
tofu import oci_core_internet_gateway.main     ocid1.internetgateway.oc1.<region>...
tofu import oci_core_default_route_table.main  ocid1.routetable.oc1.<region>...
tofu import oci_core_default_security_list.main ocid1.securitylist.oc1.<region>...
tofu import oci_core_default_dhcp_options.main ocid1.dhcpoptions.oc1.<region>...
tofu plan                                      # must end in "No changes"
```

Exact OCIDs are in `imports.tf`.

## Reviewing drift

Run `tofu plan` periodically. Because the configuration was generated from
the live resources, any diff means something changed outside OpenTofu —
typically console edits — or the provider changed behavior. Investigate the
diff before adopting or reverting it; do not refresh-and-apply blindly.

## Changing infrastructure safely

1. Edit the configuration, run `tofu fmt`, `tofu validate`, and read the full
   `tofu plan`.
2. Treat any `-/+ destroy and then create replacement` (or `- destroy`) line
   on a managed resource as a stop-the-world signal. Replacements of the
   instance, its boot volume, or the reserved public IP are effectively
   irreversible: see below.
3. Apply only after the plan is fully understood, and re-run `tofu plan`
   afterwards to confirm the result is clean.

## Why Epsilon must never be recreated casually

- Epsilon is an **Always Free** A1 instance. That capacity is perpetually
  oversubscribed; a terminated instance is rarely replaceable with the same
  shape, and the tenancy may never get the quota back.
- The boot volume holds the only NixOS installation. Restic covers service
  state, not the system itself.
- `146.181.42.97` is a **reserved** public IP. It can survive a rebuild only
  if the instance is rebuilt carefully around it; losing it means republishing
  DNS, Cloudflare, and firewall settings everywhere.

`lifecycle { prevent_destroy = true }` is set on the instance, the reserved
public IP (and would be on the boot volume if it were managed). This protects
against planned `tofu destroy`/replacement operations, **but not** against:

- deletion in the OCI console or CLI,
- deletion after removing the resource from the configuration and applying,
- or an operator bypassing the safeguard.

It is a seatbelt, not a guarantee. The real protection is reviewing every plan.

## Provider version

`terraform.required_providers` pins `~> 6.0`; `.terraform.lock.hcl` records
the exact tested version with hashes for `linux_amd64` (the platform used
locally and in CI). Contributors on other platforms should extend the lockfile:

```sh
tofu providers lock -platform=linux_amd64 -platform=linux_arm64 -platform=darwin_arm64
```
