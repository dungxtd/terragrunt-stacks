output "vault_irsa_role_arn" {
  description = "IAM role ARN annotated on the Vault service account for KMS auto-unseal"
  value       = var.enabled ? aws_iam_role.vault[0].arn : ""
}
