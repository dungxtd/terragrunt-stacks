variable "project" {
  description = "Project name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block for security group"
  type        = string
}

variable "database_subnet_group_name" {
  description = "Database subnet group name"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "backup_retention_period" {
  description = "Backup retention in days (0 = disabled, required for free tier)"
  type        = number
  default     = 7
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Max autoscaling storage in GB (set equal to allocated_storage to disable autoscaling)"
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Enable Multi-AZ"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = true
}

variable "performance_insights" {
  description = "Enable Performance Insights"
  type        = bool
  default     = true
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds (0 to disable)"
  type        = number
  default     = 60
}

variable "create_monitoring_role" {
  description = "Create IAM role for Enhanced Monitoring"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when destroying the DB"
  type        = bool
  default     = true
}

variable "master_password_override" {
  description = "Plaintext master password. Set ONLY for ministack/LocalStack where AWS-managed secrets aren't usable. Empty in production — RDS auto-generates and stores in Secrets Manager."
  type        = string
  sensitive   = true
  default     = ""
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
