include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  common  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  env_cfg = include.root.locals.env_cfg
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    oidc_provider_arn = "arn:aws:iam::000000000000:oidc-provider/oidc.eks.ap-southeast-1.amazonaws.com/id/mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    vault_unseal_key_arn = "arn:aws:kms:ap-southeast-1:000000000000:key/mock-key-id"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  enabled              = local.env_cfg.locals.vault_mode == "ha"
  project              = local.common.locals.project
  namespace            = "vault"
  service_account_name = "vault"
  oidc_provider_arn    = dependency.eks.outputs.oidc_provider_arn
  vault_unseal_key_arn = dependency.kms.outputs.vault_unseal_key_arn
  tags                 = local.common.locals.common_tags
}
