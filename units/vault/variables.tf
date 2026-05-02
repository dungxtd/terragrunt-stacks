variable "region" {
  description = "AWS region"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for Vault auto-unseal (HA mode)"
  type        = string
  default     = ""
}

variable "vault_mode" {
  description = "Vault deployment mode: 'dev' (single-node, known root token) or 'ha' (raft, operator init)"
  type        = string

  validation {
    condition     = contains(["dev", "ha"], var.vault_mode)
    error_message = "vault_mode must be 'dev' or 'ha'."
  }
}

variable "dev_root_token" {
  description = "Root token for dev mode"
  type        = string
  default     = "root"
  sensitive   = true
}

variable "vault_irsa_role_arn" {
  description = "IAM role ARN annotated on Vault service account in HA mode"
  type        = string
  default     = ""
}

variable "ssm_endpoint" {
  description = "SSM endpoint override for MiniStack (LocalStack)"
  type        = string
  default     = ""
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig for kubectl exec during vault init"
  type        = string
}
