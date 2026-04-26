output "kubernetes_auth_path" {
  description = "Vault Kubernetes auth backend path"
  value       = vault_auth_backend.kubernetes.path
}

output "database_mount_path" {
  description = "Vault database secrets engine mount path"
  value       = vault_mount.database.path
}

output "transit_mount_path" {
  description = "Vault transit engine mount path"
  value       = vault_mount.transit.path
}
