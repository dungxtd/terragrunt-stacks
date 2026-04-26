variable "datacenter" {
  description = "Consul datacenter name"
  type        = string
  default     = "dc1"
}

variable "replicas" {
  description = "Number of Consul server replicas"
  type        = number
  default     = 3
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
