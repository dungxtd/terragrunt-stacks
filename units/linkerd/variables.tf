variable "external_ca" {
  description = "Use external CA for Linkerd identity"
  type        = bool
  default     = false
}

variable "enable_viz" {
  description = "Enable Linkerd Viz dashboard"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
