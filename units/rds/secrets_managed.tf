# ── Production path: AWS-managed master password ─────────────────
# Active when local.use_managed_password == true (override empty).
# RDS module creates the Secrets Manager secret automatically when
# manage_master_user_password = true. No resources to declare here —
# this file documents the contract:
#
#   secret ARN  → module.rds.db_instance_master_user_secret_arn
#   secret JSON → {"username": "...", "password": "..."}
#
# Consumers read via aws_secretsmanager_secret_version data source.
