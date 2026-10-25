# Epsilon itself: the compute instance, its boot volume, and the reserved
# public IP that the edge services are addressed by.
#
# The instance must never be recreated: Always Free A1 capacity is scarce and
# the boot volume holds the NixOS installation. Every resource here carries
# `prevent_destroy`.

# The Ubuntu 24.04 image the instance was launched from (then converted in
# place with nixos-infect). Pinned by OCID on purpose: following Oracle's
# image list would surface new images as forced replacements.
locals {
  epsilon_source_image_id = "ocid1.image.oc1.sa-santiago-1.aaaaaaaagnsi2dl2vkmgvo2qc3rh2i2plsw72evc6c5qwfecieti4mdqwyka"
}

data "oci_core_vnic_attachments" "epsilon" {
  compartment_id = var.compartment_id
  instance_id    = oci_core_instance.epsilon.id
}

# The primary VNIC has a single private IP; the reserved public IP attaches to
# it. Resolved from the live VNIC so the mapping survives a re-import.
data "oci_core_private_ips" "epsilon_vnic" {
  vnic_id = data.oci_core_vnic_attachments.epsilon.vnic_attachments[0].vnic_id
}

resource "oci_core_instance" "epsilon" {
  availability_domain = "rTqj:SA-SANTIAGO-1-AD-1"
  compartment_id      = var.compartment_id
  display_name        = "epsilon"
  shape               = "VM.Standard.A1.Flex"
  fault_domain        = "FAULT-DOMAIN-2"
  state               = "RUNNING"

  metadata = {
    ssh_authorized_keys = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPFzKXBKbNZ+jr06UNKj0MHIzYw54CMP6suD8iTd7CxH\n"
  }

  shape_config {
    ocpus         = 2
    memory_in_gbs = 12
    vcpus         = 2
    nvmes         = 0
  }

  source_details {
    source_type                     = "image"
    source_id                       = local.epsilon_source_image_id
    boot_volume_size_in_gbs         = "200"
    boot_volume_vpus_per_gb         = "10"
    kms_key_id                      = ""
    is_preserve_boot_volume_enabled = false
  }

  create_vnic_details {
    subnet_id                 = oci_core_subnet.main.id
    assign_public_ip          = "true"
    display_name              = "arm-always-free"
    hostname_label            = "arm-always-free"
    private_ip                = "10.0.0.234"
    skip_source_dest_check    = false
    assign_private_dns_record = false
    assign_ipv6ip             = false
  }

  agent_config {
    are_all_plugins_disabled = false
    is_management_disabled   = false
    is_monitoring_disabled   = false
  }

  availability_config {
    is_live_migration_preferred = false
    recovery_action             = "RESTORE_INSTANCE"
  }

  instance_options {
    are_legacy_imds_endpoints_disabled = false
  }

  launch_options {
    boot_volume_type                    = "PARAVIRTUALIZED"
    firmware                            = "UEFI_64"
    network_type                        = "PARAVIRTUALIZED"
    remote_data_volume_type             = "PARAVIRTUALIZED"
    is_consistent_volume_naming_enabled = true
    is_pv_encryption_in_transit_enabled = false
  }

  lifecycle {
    # The boot volume holds the only NixOS install; a replacement is not
    # recoverable while Always Free A1 capacity is unavailable.
    prevent_destroy = true
  }
}

# The boot volume itself is intentionally NOT managed as oci_core_boot_volume:
# the provider requires a `source_details` block that the OCI API never reports
# for instance-launched boot volumes (oracle/terraform-provider-oci#2422), so
# adopting it would force a replacement. Its size and performance are pinned
# through the instance's source_details above; the volume is inventoried in
# README.md.

resource "oci_core_public_ip" "epsilon" {
  compartment_id = var.compartment_id
  lifetime       = "RESERVED"
  display_name   = "epsilon-reserved"
  private_ip_id  = [for ip in data.oci_core_private_ips.epsilon_vnic.private_ips : ip.id if ip.is_primary][0]

  lifecycle {
    # The address is what Cloudflare and DNS resolve to; losing it means
    # republishing every public endpoint.
    prevent_destroy = true
  }
}
