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
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

dependency "rds" {
  config_path = "../rds"

  mock_outputs = {
    rds_endpoint = "mock:5432"
    rds_username = "postgres"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

locals {
  _local_cfg               = read_terragrunt_config("${get_repo_root()}/local.hcl")
  _env_cfg                 = read_terragrunt_config("${get_repo_root()}/envs/${local._local_cfg.locals.active_env}.hcl")
  _use_ministack           = local._env_cfg.locals.use_ministack
  _rds_password            = get_env("RDS_MASTER_PASSWORD", "")
  _payments_processor_password = get_env("PAYMENTS_PROCESSOR_PASSWORD", "")
}

inputs = {
  use_ministack      = local._use_ministack
  vault_address      = dependency.vault.outputs.vault_address
  kubernetes_host    = dependency.eks.outputs.cluster_endpoint
  kubernetes_ca_cert = base64decode(dependency.eks.outputs.cluster_certificate_authority_data)
  rds_endpoint       = dependency.rds.outputs.rds_endpoint
  rds_username       = dependency.rds.outputs.rds_username
  rds_password       = local._rds_password

  payments_processor_password = local._payments_processor_password
}
