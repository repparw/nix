# Adoption mappings for Epsilon's pre-existing OCI resources.
#
# These blocks document how the live infrastructure was imported into local
# state. OpenTofu only acts on an import block when the target address is not
# yet present in state, so they are inert in normal operation and stay here as
# the authoritative record of the mapping.

import {
  to = oci_core_instance.epsilon
  id = "ocid1.instance.oc1.sa-santiago-1.anzwgljrrfvlrqqc7uwir4tkxbggoerat4q7v2worqd5edufawxibxszcnfq"
}

# The boot volume (ocid1.bootvolume.oc1.sa-santiago-1.abzwgljromeycebcjj2nftl5zmo2glsg5akcjl27j4qjgucilwf6jxkjy44q)
# is not managed: see the note in compute.tf (oracle/terraform-provider-oci#2422).

import {
  to = oci_core_public_ip.epsilon
  id = "ocid1.publicip.oc1.sa-santiago-1.amaaaaaarfvlrqqazh6axzidsqbkfoqgqjx2ytlz73b4kz57clt5yz3pckcq"
}

import {
  to = oci_core_vcn.main
  id = "ocid1.vcn.oc1.sa-santiago-1.amaaaaaarfvlrqqab2mbxubngxxdxz27qh7aiesrcwide3x5msrzy2onqarq"
}

import {
  to = oci_core_subnet.main
  id = "ocid1.subnet.oc1.sa-santiago-1.aaaaaaaadbfa2i2gbxqqz4h3xyfnzoe6qppk63a67rdkywjgzoc2vq3crz3a"
}

import {
  to = oci_core_internet_gateway.main
  id = "ocid1.internetgateway.oc1.sa-santiago-1.aaaaaaaadv2zi3fasuoq5pw42echwktrmjxxi62mhvs4fh5s5lxayan3lczq"
}

import {
  to = oci_core_default_route_table.main
  id = "ocid1.routetable.oc1.sa-santiago-1.aaaaaaaakjnzgbdx7do47fiy63q4mhngldk6xagycjgngfp6rxh3geskyhma"
}

import {
  to = oci_core_default_security_list.main
  id = "ocid1.securitylist.oc1.sa-santiago-1.aaaaaaaa22ymd2u6mweb53gtxsagnzddm26h4fpsoi2ltdt72hf6mqq5be2a"
}

import {
  to = oci_core_default_dhcp_options.main
  id = "ocid1.dhcpoptions.oc1.sa-santiago-1.aaaaaaaasuwmnuqq6cmc6zn75ryisrotiwbgztjbhywdehmp3aj5v4twlyca"
}
