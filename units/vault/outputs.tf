output "vault_address" {
  description = "Vault internal address"
  value       = "http://vault.vault.svc.cluster.local:8200"
}

output "vault_namespace" {
  description = "Kubernetes namespace for Vault"
  value       = "vault"
}

output "vault_root_token" {
  description = "Vault root token (only available after manual init)"
  value       = ""
  sensitive   = true
}
