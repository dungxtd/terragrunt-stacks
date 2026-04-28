include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "k8s" {
  path   = "${get_repo_root()}/_common/k8s_providers.hcl"
  expose = true
}

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

inputs = {
  datacenter = "dc1"
  replicas   = 3
  tags       = local.common.locals.common_tags
}
