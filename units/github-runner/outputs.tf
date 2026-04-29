output "runner_namespace" {
  description = "Namespace where runner pods are scheduled"
  value       = var.enabled ? local.runner_namespace : ""
}

output "runner_scale_set_name" {
  description = "Runner scale set name (use as runs-on label in workflows)"
  value       = var.enabled ? var.runner_scale_set_name : ""
}

output "runner_service_account" {
  description = "Service account name for runner pods"
  value       = var.enabled ? kubernetes_service_account.runner[0].metadata[0].name : ""
}
