provider "tplink" {
  host     = var.router_host
  password = var.router_password
}

# Static DHCP address assignments, keyed by the device MAC address.
# prevent_destroy is deliberate: these rows cover infrastructure hosts
# (pi, alpha) and appliances; a stray destroy would re-address them on
# their next DHCP renewal. Removing a row on purpose is a documented
# two-step (see README).
resource "tplink_dhcp_reservation" "entries" {
  for_each = var.dhcp_reservations

  mac      = each.key
  ip       = each.value.ip
  hostname = each.value.hostname
  enabled  = each.value.enabled

  lifecycle {
    prevent_destroy = true
  }
}

# Port forwarding (virtual server) rules, keyed by rule name.
resource "tplink_port_forward" "rules" {
  for_each = var.port_forwards

  name          = each.key
  ip            = each.value.ip
  external_port = each.value.external_port
  internal_port = each.value.internal_port
  protocol      = each.value.protocol
  enabled       = each.value.enabled

  lifecycle {
    prevent_destroy = true
  }
}

# Stable identification of the managed device; read-only.
data "tplink_firmware" "current" {}

output "router_firmware" {
  description = "Firmware the provider is managing against."
  value = {
    model     = data.tplink_firmware.current.model
    hardware  = data.tplink_firmware.current.hardware_version
    firmware  = data.tplink_firmware.current.firmware_version
  }
}
