include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  common  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  env_cfg = include.root.locals.env_cfg
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id                     = "vpc-mock"
    database_subnet_group_name = "mock-db-subnet-group"
    vpc_cidr_block             = "10.0.0.0/16"
  }
}

inputs = {
  project                    = local.common.locals.project
  vpc_id                     = dependency.vpc.outputs.vpc_id
  vpc_cidr_block             = dependency.vpc.outputs.vpc_cidr_block
  database_subnet_group_name = dependency.vpc.outputs.database_subnet_group_name
  tags                       = local.common.locals.common_tags

  multi_az                = local.env_cfg.locals.rds_multi_az
  deletion_protection     = local.env_cfg.locals.rds_deletion_protection
  performance_insights    = local.env_cfg.locals.rds_performance_insights
  monitoring_interval     = local.env_cfg.locals.rds_monitoring_interval
  create_monitoring_role  = local.env_cfg.locals.rds_create_monitoring_role
  instance_class          = local.env_cfg.locals.rds_instance_class
  backup_retention_period = local.env_cfg.locals.rds_backup_retention_period
  allocated_storage       = local.env_cfg.locals.rds_allocated_storage
  max_allocated_storage   = local.env_cfg.locals.rds_max_allocated_storage
  skip_final_snapshot     = local.env_cfg.locals.rds_skip_final_snapshot
}
