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
  region  = local.common.locals.region
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    vault_unseal_key_id = "mock-key-id"
  }
}

dependency "vault_irsa" {
  config_path = "../vault-irsa"
  enabled     = local.env_cfg.locals.vault_mode == "ha"

  mock_outputs = {
    vault_irsa_role_arn = "arn:aws:iam::000000000000:role/mock-vault"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

inputs = {
  region              = local.region
  vault_mode          = local.env_cfg.locals.vault_mode
  dev_root_token      = local.env_cfg.locals.dev_root_token
  vault_irsa_role_arn = local.env_cfg.locals.vault_mode == "ha" ? dependency.vault_irsa.outputs.vault_irsa_role_arn : ""
  kms_key_id          = dependency.kms.outputs.vault_unseal_key_id
  ssm_endpoint        = local.env_cfg.locals.ssm_endpoint
  kubeconfig_path     = local.env_cfg.locals.kubeconfig_path
}

# After helm_release + aws_ssm_parameter resources apply, run init script.
# Script is idempotent (skips if Vault already initialized), so safe on every apply.
terraform {
  after_hook "vault_init" {
    commands = ["apply"]
    execute = [
      "bash", "-c",
      "VAULT_MODE='${local.env_cfg.locals.vault_mode}' AWS_REGION='${local.region}' KUBECONFIG='${local.env_cfg.locals.kubeconfig_path}' SSM_ENDPOINT='${local.env_cfg.locals.ssm_endpoint}' DEV_ROOT_TOKEN='${local.env_cfg.locals.dev_root_token}' bash ${get_repo_root()}/scripts/vault-init.sh"
    ]
    run_on_error = false
  }
}
