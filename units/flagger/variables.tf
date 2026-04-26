variable "mesh_provider" {
  description = "Flagger mesh provider: linkerd or consul"
  type        = string

  validation {
    condition     = contains(["linkerd", "consul"], var.mesh_provider)
    error_message = "mesh_provider must be 'linkerd' or 'consul'"
  }
}

variable "metrics_server" {
  description = "Metrics server URL for Flagger"
  type        = string
  default     = "http://prometheus.linkerd-viz:9090"
}

variable "enable_loadtester" {
  description = "Deploy Flagger load tester"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
