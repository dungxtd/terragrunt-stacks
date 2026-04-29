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
}

dependency "rds" {
  config_path = "../rds"

  mock_outputs = {
    rds_endpoint = "mock:5432"
    rds_username = "postgres"
  }
}

locals {
  _local_cfg     = read_terragrunt_config("${get_repo_root()}/local.hcl")
  _env_cfg       = read_terragrunt_config("${get_repo_root()}/envs/${local._local_cfg.locals.active_env}.hcl")
  _use_ministack = local._env_cfg.locals.use_ministack

  _kubernetes_ca_cert         = base64decode(dependency.eks.outputs.cluster_certificate_authority_data)
  _rds_password               = get_env("RDS_MASTER_PASSWORD", "")
  _payments_processor_password = get_env("PAYMENTS_PROCESSOR_PASSWORD", "")
}

inputs = {
  use_ministack      = local._use_ministack
  vault_address      = dependency.vault.outputs.vault_address
  kubernetes_host    = dependency.eks.outputs.cluster_endpoint
  kubernetes_ca_cert = local._kubernetes_ca_cert
  rds_endpoint       = dependency.rds.outputs.rds_endpoint
  rds_username       = dependency.rds.outputs.rds_username
  rds_password       = local._rds_password

  payments_processor_password = local._payments_processor_password
}
