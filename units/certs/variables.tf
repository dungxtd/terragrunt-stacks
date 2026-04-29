variable "vault_address" {
  description = "Vault server address"
  type        = string
}

variable "vault_token" {
  description = "Vault root token for provider auth"
  type        = string
  sensitive   = true
}

variable "organization" {
  description = "Organization name for CA subject"
  type        = string
  default     = "HashiCorp Demo"
}
