locals {
  use_ministack = false

  # Not used — credentials come from the AWS CLI / instance profile
  endpoint   = ""
  access_key = ""
  secret_key = ""

  # ── Feature flags ──────────────────────────────────────────────
  # All features enabled for real AWS.

  # EKS
  create_cluster_security_group             = true
  create_node_security_group                = true
  create_cluster_addons                     = true
  enable_cluster_creator_admin_permissions  = true
  update_launch_template_default_version    = true

  # VPC
  enable_nat_gateway = true
  single_nat_gateway = false

  # RDS
  rds_multi_az              = true
  rds_deletion_protection   = true
  rds_performance_insights  = true
  rds_monitoring_interval   = 60
  rds_create_monitoring_role = true
}
