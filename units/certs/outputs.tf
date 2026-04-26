output "root_ca_pem" {
  description = "Root CA certificate PEM"
  value       = tls_self_signed_cert.root_ca.cert_pem
}

output "consul_server_pki_path" {
  description = "Vault PKI path for Consul server certs"
  value       = vault_mount.consul_server_intermediate.path
}

output "consul_connect_pki_path" {
  description = "Vault PKI path for Consul Connect certs"
  value       = vault_mount.consul_connect_intermediate.path
}

output "consul_gateway_pki_path" {
  description = "Vault PKI path for Consul API Gateway certs"
  value       = vault_mount.consul_gateway_intermediate.path
}
