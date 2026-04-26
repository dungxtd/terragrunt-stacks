output "rds_endpoint" {
  description = "RDS endpoint address"
  value       = module.rds.db_instance_endpoint
}

output "rds_address" {
  description = "RDS hostname"
  value       = module.rds.db_instance_address
}

output "rds_port" {
  description = "RDS port"
  value       = module.rds.db_instance_port
}

output "rds_name" {
  description = "Database name"
  value       = module.rds.db_instance_name
}

output "rds_username" {
  description = "Master username"
  value       = module.rds.db_instance_username
  sensitive   = true
}

output "rds_master_secret_arn" {
  description = "ARN of the Secrets Manager secret for master password"
  value       = module.rds.db_instance_master_user_secret_arn
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}
