variable "enable_consul_project" {
  description = "Create ArgoCD AppProject for Consul (vault-consul env only)"
  type        = bool
  default     = false
}

variable "use_ministack" {
  description = "Running against MiniStack — use NodePort instead of LoadBalancer"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
