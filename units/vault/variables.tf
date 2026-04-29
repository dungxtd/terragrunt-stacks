variable "region" {
  description = "AWS region"
  type        = string
}

variable "helm_values" {
  description = "YAML-encoded Helm values for the Vault chart"
  type        = string
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
  description = "Root token for dev mode. Only used when vault_mode = 'dev'."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "ssm_endpoint" {
  description = "SSM endpoint override for MiniStack"
  type        = string
  default     = ""
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig used by kubectl in init"
  type        = string
}
