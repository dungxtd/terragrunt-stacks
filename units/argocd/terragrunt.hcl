include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "k8s" {
  path = "${get_repo_root()}/_common/k8s_providers.hcl"
}

inputs = {
  enable_consul_project = true
  service_type          = include.root.locals.env_cfg.locals.argocd_service_type
}
