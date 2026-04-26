include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

include "k8s" {
  path   = "${get_repo_root()}/_common/k8s_providers.hcl"
  expose = true
}

inputs = {
  datadog_api_key = get_env("DATADOG_API_KEY", "")
  datadog_site    = get_env("DATADOG_SITE", "datadoghq.com")
}
