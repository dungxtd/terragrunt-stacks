output "rds_endpoint" {
  description = "RDS endpoint address"
  value       = module.rds.db_instance_endpoint
}

output "rds_username" {
  description = "Master username"
  value       = module.rds.db_instance_username
  sensitive   = true
}

output "rds_master_secret_arn" {
  description = "ARN of the Secrets Manager secret holding {username,password} for the master user. Always populated — managed by RDS in prod, mirrored from override in ministack."
  sensitive   = true
  value = (
    local.use_managed_password
    ? module.rds.db_instance_master_user_secret_arn
    : aws_secretsmanager_secret_version.master_override[0].arn
  )
}
