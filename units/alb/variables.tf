variable "project" {
  description = "Project name"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

variable "service_namespace" {
  description = "K8s namespace of target service"
  type        = string
}

variable "service_name" {
  description = "K8s Service name to bind to TG"
  type        = string
}

variable "service_port" {
  description = "K8s Service port to bind"
  type        = number
}

variable "listen_port" {
  description = "ALB listener port (80 for HTTP, 443 if certificate_arn set)"
  type        = number
  default     = 80
}

variable "scheme" {
  description = "ALB scheme: internet-facing or internal"
  type        = string
  default     = "internet-facing"
}

variable "health_check_path" {
  description = "Target group health check path"
  type        = string
  default     = "/"
}

variable "certificate_arn" {
  description = "ACM cert ARN to enable HTTPS listener (empty = HTTP only)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
