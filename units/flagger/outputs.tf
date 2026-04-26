output "flagger_namespace" {
  description = "Flagger namespace"
  value       = "flagger-system"
}

output "mesh_provider" {
  description = "Active mesh provider"
  value       = var.mesh_provider
}
