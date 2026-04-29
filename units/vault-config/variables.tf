variable "vault_address" {
  description = "Vault server address"
  type        = string
}

variable "kubernetes_host" {
  description = "Kubernetes API server URL"
  type        = string
}

variable "kubernetes_ca_cert" {
  description = "Kubernetes CA certificate (base64 decoded)"
  type        = string
  default     = ""
}

variable "rds_endpoint" {
  description = "RDS endpoint (host:port)"
  type        = string
}

variable "rds_username" {
  description = "RDS master username"
  type        = string
}

variable "rds_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "payments_processor_password" {
  description = "Static password for payments-processor"
  type        = string
  sensitive   = true
  default     = ""
}
