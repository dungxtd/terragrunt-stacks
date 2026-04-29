include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  common  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  env_cfg = include.root.locals.env_cfg
}

inputs = {
  project  = local.common.locals.project
  region   = local.common.locals.region
  vpc_cidr = local.common.locals.vpc_cidr
  azs      = local.common.locals.azs
  tags     = local.common.locals.common_tags

  enable_nat_gateway = local.env_cfg.locals.enable_nat_gateway
  single_nat_gateway = local.env_cfg.locals.single_nat_gateway
}
