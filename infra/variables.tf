variable "oci_profile" {
  description = "Profile name in the OCI CLI configuration file to authenticate with."
  type        = string
  default     = "DEFAULT"
}

variable "compartment_id" {
  description = "OCID of the compartment holding Epsilon's cloud resources (the tenancy root)."
  type        = string
}
