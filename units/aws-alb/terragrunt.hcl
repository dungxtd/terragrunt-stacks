include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "k8s" {
  path   = "${get_repo_root()}/_common/k8s_providers.hcl"
  expose = true
}

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = { vpc_id = "vpc-mock" }
}

inputs = {
  project           = local.common.locals.project
  region            = local.common.locals.region
  cluster_name      = dependency.eks.outputs.cluster_name
  vpc_id            = dependency.vpc.outputs.vpc_id
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  tags              = local.common.locals.common_tags
}
