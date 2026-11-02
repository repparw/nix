# OpenTofu root module for Epsilon's OCI cloud resources.
#
# Authentication uses the local OCI CLI configuration (~/.oci/config) via
# `config_file_profile`; no credentials live in this repository.

terraform {
  required_version = "~> 1.9"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

provider "oci" {
  config_file_profile = var.oci_profile

  # Requests without credentials fail fast; this module never manages
  # resources outside the compartment below.
  #
  # OCI maintains the Oracle-Tags namespace itself (CreatedBy/CreatedOn), so
  # plans ignore changes to it instead of fighting the service.
  ignore_defined_tags = ["Oracle-Tags"]
}
