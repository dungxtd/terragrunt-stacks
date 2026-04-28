include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

inputs = {
  project  = local.common.locals.project
  region   = local.common.locals.region
  vpc_cidr = local.common.locals.vpc_cidr
  azs      = local.common.locals.azs
  tags     = local.common.locals.common_tags
}
