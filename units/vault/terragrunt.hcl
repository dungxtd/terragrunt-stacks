include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "k8s" {
  path   = "${get_repo_root()}/_common/k8s_providers.hcl"
  expose = true
}

locals {
  common = read_terragrunt_config(find_in_parent_folders("common.hcl"))
}

dependency "kms" {
  config_path = "../kms"

  mock_outputs = {
    vault_unseal_key_id = "mock-key-id"
  }
}

inputs = {
  region     = local.common.locals.region
  kms_key_id = dependency.kms.outputs.vault_unseal_key_id
  replicas   = 3
  tags       = local.common.locals.common_tags
}
