output "instance_id" {
  description = "OCID of the Epsilon compute instance."
  value       = oci_core_instance.epsilon.id
}

output "instance_public_ip" {
  description = "Reserved public IP terminating Epsilon's public edge."
  value       = oci_core_public_ip.epsilon.ip_address
}

output "instance_private_ip" {
  description = "Private IP of Epsilon's primary VNIC."
  value       = oci_core_instance.epsilon.private_ip
}
