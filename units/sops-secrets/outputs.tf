output "sops_kms_key_arn" {
  description = "SOPS KMS key ARN"
  value       = aws_kms_key.sops.arn
}

output "sops_kms_key_id" {
  description = "SOPS KMS key ID"
  value       = aws_kms_key.sops.key_id
}

output "sops_decrypt_policy_arn" {
  description = "IAM policy ARN for SOPS decrypt"
  value       = aws_iam_policy.sops_decrypt.arn
}

output "sops_encrypt_policy_arn" {
  description = "IAM policy ARN for SOPS encrypt"
  value       = aws_iam_policy.sops_encrypt.arn
}
