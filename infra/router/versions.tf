terraform {
  required_version = ">= 1.9"

  required_providers {
    tplink = {
      source = "registry.opentofu.org/repparw/tplink"
      # Matches the locally installed plugin (see README); tighten to an
      # exact registry version once the provider is published.
      version = "0.1.0"
    }
  }
}
