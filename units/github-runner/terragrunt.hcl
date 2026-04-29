include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

include "k8s" {
  path   = "${get_repo_root()}/_common/k8s_providers.hcl"
  expose = true
}

locals {
  common  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  env_cfg = include.root.locals.env_cfg
}

inputs = {
  enabled                    = local.env_cfg.locals.enable_github_runner
  github_config_url          = get_env("GITHUB_CONFIG_URL", "https://github.com/dungxtd/terragrunt-stacks")
  github_app_id              = get_env("GITHUB_APP_ID", "")
  github_app_installation_id = get_env("GITHUB_APP_INSTALLATION_ID", "")
  github_app_private_key     = get_env("GITHUB_APP_PRIVATE_KEY", "")
  github_pat                 = get_env("GITHUB_PAT", "")

  runner_scale_set_name = "arc-runner"
  min_runners           = 0
  max_runners           = 5

  tags = local.common.locals.common_tags
}
