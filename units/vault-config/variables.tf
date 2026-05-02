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

variable "vault_mode" {
  description = "Vault deployment mode from the environment config"
  type        = string

  validation {
    condition     = contains(["dev", "ha"], var.vault_mode)
    error_message = "vault_mode must be 'dev' or 'ha'."
  }
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

variable "db_ssl_mode" {
  description = "PostgreSQL sslmode for Vault DB connection. Use 'verify-full' in production once RDS CA bundle is mounted in Vault pods."
  type        = string
  default     = "require"
}

variable "payments_processor_password" {
  description = "Static password for payments-processor"
  type        = string
  sensitive   = true
  default     = ""
}
