include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl"))
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
}
