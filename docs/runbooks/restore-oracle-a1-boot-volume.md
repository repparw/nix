---
type: Runbook
title: Restore the Oracle A1 boot volume from backup
description: Recovery paths for epsilon (arm-always-free) if nixos-infect or a later change leaves the Oracle Cloud ARM instance unbootable.
when: Read when epsilon does not come back after an infect, upgrade, or reboot.
resource: modules/hosts/epsilon.nix
tags: [runbook, oracle, oci, epsilon, restore, backup]
---

# Restore the Oracle A1 boot volume from backup

The safety net is the FULL boot-volume backup taken at each milestone:

- Backup name: `nixos-flake-initial` (epsilon on its first flake-managed
  generation, taken 2026-08-25 after deploy + reboot test)
- Backup OCID: `ocid1.bootvolumebackup.oc1.sa-santiago-1.abzwgljrofyjftdlfgu477ibebtzvqwtjnr2ipfexfdjo5rxrhl4ys3ks75a`
- Boot volume OCID: `ocid1.bootvolume.oc1.sa-santiago-1.abzwgljromeycebcjj2nftl5zmo2glsg5akcjl27j4qjgucilwf6jxkjy44q`
- Instance OCID: `ocid1.instance.oc1.sa-santiago-1.anzwgljrrfvlrqqc7uwir4tkxbggoerat4q7v2worqd5edufawxibxszcnfq`
- Subnet OCID: `ocid1.subnet.oc1.sa-santiago-1.aaaaaaaadbfa2i2gbxqqz4h3xyfnzoe6qppk63a67rdkywjgzoc2vq3crz3a`
- AD: `rTqj:SA-SANTIAGO-1-AD-1`, compartment = tenancy root
- Shape: VM.Standard.A1.Flex, 2 OCPU / 12 GB

The pre-infect Ubuntu backup was dropped deliberately: that system state is
reproducible by re-running nixos-infect, while this one captures the proven
boot layout plus the SSH host key that unlocks sops secrets.

List current backups:

```sh
oci bv boot-volume-backup list -c "$TEN" --all
```

## Path A: swap the boot volume on the same instance

Keeps the instance identity and its reserved public IP `146.181.42.97`
(the VNIC stays attached, so the address survives).

```sh
TEN=ocid1.tenancy.oc1..aaaaaaaawlqqlvgxn5ptkg65wwt5vdsgkjrpjqjnsjfdkyoociiguaybrq7a
BVID=ocid1.bootvolume.oc1.sa-santiago-1.abzwgljromeycebcjj2nftl5zmo2glsg5akcjl27j4qjgucilwf6jxkjy44q
IID=ocid1.instance.oc1.sa-santiago-1.anzwgljrrfvlrqqc7uwir4tkxbggoerat4q7v2worqd5edufawxibxszcnfq
BKUP=ocid1.bootvolumebackup.oc1.sa-santiago-1.abzwgljrdrvxounk63p4donzzi4qnxb4lhnpjgnof7saoeky33zunzuyndia
AD="rTqj:SA-SANTIAGO-1-AD-1"

# 1. Stop the instance
oci compute instance action --instance-id "$IID" --action SOFTSTOP --wait-for-state STOPPED
oci compute instance action --instance-id "$IID" --action RESET   # only if SOFTSTOP hangs

# 2. Find and detach the current boot volume attachment
ATT=$(oci compute boot-volume-attachment list -c "$TEN" --availability-domain "$AD" \
  --instance-id "$IID" | jq -r '.data[0].id')
oci compute boot-volume-attachment detach --boot-volume-attachment-id "$ATT" --wait-for-state DETACHED

# 3. Create a new boot volume from the backup (needs free quota: total-storage-gb
#    clamp is 400 GB, live volume uses 200)
oci bv boot-volume create \
  --availability-domain "$AD" -c "$TEN" \
  --source-boot-volume-backup-id "$BKUP" \
  --display-name arm-restored --size-in-gbs 200 \
  --wait-for-state AVAILABLE

NEWBV=$(oci bv volume list -c "$TEN" --availability-domain "$AD" \
  --display-name arm-restored | jq -r '.data[0].id')

# 4. Attach restored volume as boot volume, start the instance
oci compute boot-volume-attach --instance-id "$IID" --boot-volume-id "$NEWBV"
oci compute instance action --instance-id "$IID" --action START --wait-for-state RUNNING
```

## Path B: launch a fresh instance from the backup

Use if Path A cannot attach (attachment stuck, instance unrepairable):

```sh
oci compute instance launch \
  -c "$TEN" --availability-domain "$AD" \
  --shape "VM.Standard.A1.Flex" --shape-config '{"ocpus":2,"memoryInGBs":12}' \
  --subnet-id ocid1.subnet.oc1.sa-santiago-1.aaaaaaaadbfa2i2gbxqqz4h3xyfnzoe6qppk63a67rdkywjgzoc2vq3crz3a \
  --assign-public-ip true \
  --source-details '{"sourceType":"bootVolume","bootVolumeId":"<NEW_BV_FROM_PATH_A_STEP_3>"}' \
  --display-name arm-restored
```

Terminate the broken instance first so the shape fits inside the
`always-free-cap` quota (4 OCPU / 24 GB / 400 GB storage).

## Serial console (out-of-band rescue)

A console connection lets you watch boot messages without SSH. This CLI build
lacks the command and the raw-API call returned 404 (the account likely needs
an IAM policy granting `manage instance-console-connection`). If SSH breaks in
a way Path A cannot fix, add this policy in the Console first, then retry:

```
Allow group Administrators to manage instance-console-connections in tenancy
Allow group Administrators to manage instances in tenancy
```

Connect afterwards with the standard proxy-command from the OCI docs using
`~/.ssh/id_ed25519`.

## Notes

- Backups stay free up to 5 (`free-backup-count` limit); one slot in use.
- The `always-free-cap` quota deliberately allows one extra full-size boot
  volume so neither restore path gets blocked by the guardrail.
- Refresh this backup at milestones (before the edge migration, after any
  risky experiment lands): delete the stale one only after its replacement
  reaches AVAILABLE.
