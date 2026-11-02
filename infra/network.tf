# Virtual networking for Epsilon: one VCN with a single public subnet and an
# internet gateway. These were Oracle-created defaults (except the security
# list rules, which carry epsilon's edge policy) and are adopted as-is.

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "vcn-20260128-1948"
  dns_label      = "vcn01281953"
}

resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "Internet Gateway vcn-20260128-1948"
  enabled        = true
}

resource "oci_core_subnet" "main" {
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = "10.0.0.0/24"
  display_name               = "subnet-20260128-1948"
  dns_label                  = "subnet01281953"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_default_route_table.main.id
  security_list_ids          = [oci_core_default_security_list.main.id]
  dhcp_options_id            = oci_core_default_dhcp_options.main.id
}

resource "oci_core_default_route_table" "main" {
  compartment_id             = var.compartment_id
  manage_default_resource_id = oci_core_vcn.main.default_route_table_id

  route_rules {
    description       = ""
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

resource "oci_core_default_security_list" "main" {
  compartment_id             = var.compartment_id
  manage_default_resource_id = oci_core_vcn.main.default_security_list_id
  display_name               = "Default Security List for vcn-20260128-1948"

  egress_security_rules {
    description      = ""
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
    stateless        = false
  }

  ingress_security_rules {
    description = ""
    protocol    = "1"
    source      = "10.0.0.0/16"
    source_type = "CIDR_BLOCK"
    stateless   = false

    icmp_options {
      code = -1
      type = 3
    }
  }

  ingress_security_rules {
    description = ""
    protocol    = "1"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false

    icmp_options {
      code = 4
      type = 3
    }
  }

  ingress_security_rules {
    description = ""
    protocol    = "6"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    description = "HTTPS public (traefik edge)"
    protocol    = "6"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false

    tcp_options {
      min = 443
      max = 443
    }
  }

  ingress_security_rules {
    description = "mosh client (single pinned port)"
    protocol    = "17"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false

    udp_options {
      min = 60002
      max = 60002
    }
  }
}

resource "oci_core_default_dhcp_options" "main" {
  compartment_id             = var.compartment_id
  manage_default_resource_id = oci_core_vcn.main.default_dhcp_options_id
  display_name               = "Default DHCP Options for vcn-20260128-1948"
  domain_name_type           = "CUSTOM_DOMAIN"

  options {
    type        = "DomainNameServer"
    server_type = "VcnLocalPlusInternet"
  }

  options {
    type                = "SearchDomain"
    search_domain_names = ["vcn01281953.oraclevcn.com"]
  }
}
