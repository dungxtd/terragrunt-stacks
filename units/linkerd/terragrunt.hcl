include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "k8s" {
  path   = "${get_repo_root()}/_common/k8s_providers.hcl"
  expose = true
}

inputs = {
  external_ca = false
  enable_viz  = true
}
