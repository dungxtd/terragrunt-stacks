locals {
  use_ministack = false

  # Not used — credentials come from the AWS CLI / instance profile
  endpoint   = ""
  access_key = ""
  secret_key = ""

  # ── Feature flags ──────────────────────────────────────────────
  # All features enabled for real AWS.

  # EKS
  create_cluster_security_group            = true
  create_node_security_group               = true
  create_cluster_addons                    = true
  enable_cluster_creator_admin_permissions = true
  update_launch_template_default_version   = true
  eks_node_instance_types                  = ["t3.medium"]
  eks_node_min_size                        = 1
  eks_node_max_size                        = 3
  eks_node_desired_size                    = 2

  # VPC
  enable_nat_gateway = true
  single_nat_gateway = false

  # RDS
  rds_multi_az                  = false
  rds_deletion_protection       = false
  rds_performance_insights      = false
  rds_monitoring_interval       = 0
  rds_create_monitoring_role    = false
  rds_instance_class            = "db.t3.micro"
  rds_backup_retention_period   = 0
  rds_allocated_storage         = 20
  rds_max_allocated_storage     = 20

  # GitHub Actions Runner
  enable_github_runner = true
}
