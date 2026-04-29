include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "vault" {
  path   = "${get_repo_root()}/_common/vault_provider.hcl"
  expose = true
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_endpoint                   = "https://mock"
    cluster_certificate_authority_data = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "rds" {
  config_path = "../rds"

  mock_outputs = {
    rds_endpoint = "mock:5432"
    rds_username = "postgres"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

locals {
  _env_name                    = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.name
  _env_cfg                     = read_terragrunt_config("${get_repo_root()}/envs/${local._env_name}.hcl")
  _rds_password                = get_env("RDS_MASTER_PASSWORD", "")
  _payments_processor_password = get_env("PAYMENTS_PROCESSOR_PASSWORD", "")
}

inputs = {
  vault_address      = dependency.vault.outputs.vault_address
  kubernetes_host    = dependency.eks.outputs.cluster_endpoint
  kubernetes_ca_cert = base64decode(dependency.eks.outputs.cluster_certificate_authority_data)

  # Env config provides overrides; empty string → fall back to real RDS outputs
  rds_endpoint = coalesce(local._env_cfg.locals.rds_endpoint_override, dependency.rds.outputs.rds_endpoint)
  rds_username = coalesce(local._env_cfg.locals.rds_username_override, dependency.rds.outputs.rds_username)
  rds_password = coalesce(local._env_cfg.locals.rds_password_override, local._rds_password)

  payments_processor_password = local._payments_processor_password
}
