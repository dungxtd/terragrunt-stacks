variable "project" {
  description = "Project name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnets" {
  description = "Private subnet IDs for EKS nodes"
  type        = list(string)
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "create_cluster_security_group" {
  description = "Create EKS cluster security group"
  type        = bool
  default     = true
}

variable "create_node_security_group" {
  description = "Create EKS node security group"
  type        = bool
  default     = true
}

variable "create_cluster_addons" {
  description = "Create EKS cluster add-ons (coredns, kube-proxy, vpc-cni)"
  type        = bool
  default     = true
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Enable EKS access entries for cluster creator"
  type        = bool
  default     = true
}

variable "update_launch_template_default_version" {
  description = "Update the default version of the launch template on changes"
  type        = bool
  default     = true
}

variable "use_latest_ami_release_version" {
  description = "Use latest AMI release version (looks up SSM param). Disable for MiniStack."
  type        = bool
  default     = true
}

variable "node_instance_types" {
  description = "EC2 instance types for EKS managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_min_size" {
  description = "Minimum number of nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes"
  type        = number
  default     = 3
}

variable "node_desired_size" {
  description = "Desired number of nodes"
  type        = number
  default     = 2
}
