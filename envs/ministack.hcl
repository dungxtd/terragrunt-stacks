locals {
  use_ministack = true

  # MiniStack / LocalStack connection
  endpoint   = "http://localhost:4566"
  access_key = "test"
  secret_key = "test"

  # ── Feature flags ──────────────────────────────────────────────
  # Disable resources that MiniStack cannot handle properly.

  # EKS: security-group-rule creation hangs; access entries API unsupported
  create_cluster_security_group            = false
  create_node_security_group               = false
  create_cluster_addons                    = false
  enable_cluster_creator_admin_permissions = false
  update_launch_template_default_version   = false
  eks_node_instance_types                  = ["t3.medium"]
  eks_node_min_size                        = 1
  eks_node_max_size                        = 3
  eks_node_desired_size                    = 2

  # VPC: NAT Gateways are not functional in MiniStack
  enable_nat_gateway = false
  single_nat_gateway = true

  # RDS: some advanced features are unsupported
  rds_multi_az                  = false
  rds_deletion_protection       = false
  rds_performance_insights      = false
  rds_monitoring_interval       = 0
  rds_create_monitoring_role    = false
  rds_instance_class            = "db.t3.micro"
  rds_backup_retention_period   = 0
  rds_allocated_storage         = 20
  rds_max_allocated_storage     = 20

  # GitHub Actions Runner: not needed locally
  enable_github_runner = false
}
