terraform {
  required_version = ">= 1.9"

  required_providers {
    tplink = {
      source  = "registry.opentofu.org/repparw/tplink"
      version = "= 0.1.0"
    }
  }
}
