variable "region" {
  description = "AWS region"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for Vault auto-unseal"
  type        = string
}

variable "replicas" {
  description = "Number of Vault server replicas"
  type        = number
  default     = 3
}

variable "vault_sa_annotations" {
  description = "Annotations for Vault service account (e.g., IRSA role ARN)"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
