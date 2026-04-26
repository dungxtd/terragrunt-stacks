variable "vault_address" {
  description = "Vault server address"
  type        = string
}

variable "organization" {
  description = "Organization name for CA certificates"
  type        = string
  default     = "HashiCorp Demo"
}
