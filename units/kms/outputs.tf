output "vault_unseal_key_id" {
  description = "KMS key ID for Vault auto-unseal"
  value       = aws_kms_key.vault_unseal.key_id
}

output "vault_unseal_key_arn" {
  description = "KMS key ARN for Vault auto-unseal"
  value       = aws_kms_key.vault_unseal.arn
}

output "sops_key_id" {
  description = "KMS key ID for SOPS"
  value       = aws_kms_key.sops.key_id
}

output "sops_key_arn" {
  description = "KMS key ARN for SOPS"
  value       = aws_kms_key.sops.arn
}

output "tf_state_key_id" {
  description = "KMS key ID for Terraform state"
  value       = aws_kms_key.tf_state.key_id
}
