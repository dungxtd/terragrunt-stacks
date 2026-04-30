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

variable "rds_master_secret_arn" {
  description = "ARN of the Secrets Manager secret holding {username,password} for the RDS master user. Sourced from the rds unit output."
  type        = string
}

variable "payments_processor_password" {
  description = "Static password for payments-processor"
  type        = string
  sensitive   = true
  default     = ""
}
