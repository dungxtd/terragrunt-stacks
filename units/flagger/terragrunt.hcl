include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "k8s" {
  path   = "${get_repo_root()}/_common/k8s_providers.hcl"
  expose = true
}

inputs = {
  mesh_provider  = try(values.mesh_provider, "linkerd")
  metrics_server = try(values.metrics_server, "http://prometheus.linkerd-viz:9090")
}
