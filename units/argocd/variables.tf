variable "service_type" {
  description = "Kubernetes service type for ArgoCD server (NodePort or LoadBalancer)"
  type        = string
  default     = "LoadBalancer"
}
