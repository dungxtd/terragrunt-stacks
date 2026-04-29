variable "enable_consul_project" {
  description = "Create ArgoCD AppProject for Consul (vault-consul env only)"
  type        = bool
  default     = false
}

variable "service_type" {
  description = "Kubernetes service type for ArgoCD server (NodePort or LoadBalancer)"
  type        = string
  default     = "LoadBalancer"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
