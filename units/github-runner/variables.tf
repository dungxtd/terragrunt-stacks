variable "enabled" {
  description = "Whether to deploy the GitHub Actions runner. Set to false for MiniStack."
  type        = bool
  default     = true
}

variable "github_config_url" {
  description = "GitHub organization or repository URL for the runner scale set"
  type        = string
}

variable "github_app_id" {
  description = "GitHub App ID for runner authentication"
  type        = string
  default     = ""
}

variable "github_app_installation_id" {
  description = "GitHub App installation ID"
  type        = string
  default     = ""
}

variable "github_app_private_key" {
  description = "GitHub App private key (PEM format)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "github_pat" {
  description = "GitHub Personal Access Token (alternative to GitHub App auth)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "runner_scale_set_name" {
  description = "Name for the runner scale set (used as runs-on label)"
  type        = string
  default     = "arc-runner"
}

variable "min_runners" {
  description = "Minimum number of idle runner pods"
  type        = number
  default     = 0
}

variable "max_runners" {
  description = "Maximum number of concurrent runner pods"
  type        = number
  default     = 5
}

variable "runner_requests_cpu" {
  description = "CPU request for runner pods"
  type        = string
  default     = "1"
}

variable "runner_requests_memory" {
  description = "Memory request for runner pods"
  type        = string
  default     = "2Gi"
}

variable "runner_limits_cpu" {
  description = "CPU limit for runner pods"
  type        = string
  default     = "2"
}

variable "runner_limits_memory" {
  description = "Memory limit for runner pods"
  type        = string
  default     = "4Gi"
}

variable "runner_service_account_annotations" {
  description = "Annotations for the runner service account (e.g. IRSA role ARN)"
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
