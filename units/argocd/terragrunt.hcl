include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "k8s" {
  path   = "${get_repo_root()}/_common/k8s_providers.hcl"
  expose = true
}

inputs = {
  enable_consul_project = try(values.enable_consul_project, false)
  use_ministack         = include.k8s.locals._use_ministack
}
