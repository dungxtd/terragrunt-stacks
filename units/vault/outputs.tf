output "vault_address" {
  description = "Vault internal cluster address"
  value       = "http://vault.vault.svc.cluster.local:8200"
}

output "vault_namespace" {
  description = "Kubernetes namespace for Vault"
  value       = "vault"
}

output "vault_root_token" {
  description = "Vault root token (retrieved from SSM after auto-init)"
  value       = data.aws_ssm_parameter.vault_root_token.value
  sensitive   = true
}
