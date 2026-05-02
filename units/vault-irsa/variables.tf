variable "enabled" {
  description = "Create Vault IRSA resources"
  type        = bool
}

variable "project" {
  description = "Project name used for IAM resources"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for the Vault service account"
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes service account name used by Vault"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN used for Vault IRSA"
  type        = string
}

variable "vault_unseal_key_arn" {
  description = "KMS key ARN used by Vault auto-unseal"
  type        = string
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
