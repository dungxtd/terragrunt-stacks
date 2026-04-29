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

inputs = {
  region          = local.region
  vault_mode      = local.env_cfg.locals.vault_mode
  dev_root_token  = local.env_cfg.locals.dev_root_token
  tags            = local.common.locals.common_tags
  ssm_endpoint    = local.env_cfg.locals.ssm_endpoint
  kubeconfig_path = local.env_cfg.locals.kubeconfig_path

  # Build Helm values at Terragrunt layer — module receives only the final YAML.
  # Keyed by vault_mode ("dev" / "ha") from the env config.
  helm_values = {
    dev = yamlencode({
      server = {
        enabled = true
        dev = {
          enabled      = true
          devRootToken = "root"
        }
      }
      injector = { enabled = false }
      csi      = { enabled = false }
      ui       = { enabled = true }
    })

    ha = yamlencode({
      server = {
        enabled = true
        ha = {
          enabled  = true
          replicas = 3
          raft = {
            enabled = true
            config  = <<-EOF
              ui = true
              listener "tcp" {
                tls_disable     = 1
                address         = "[::]:8200"
                cluster_address = "[::]:8201"
              }
              storage "raft" {
                path = "/vault/data"
              }
              seal "awskms" {
                region     = "${local.region}"
                kms_key_id = "${dependency.kms.outputs.vault_unseal_key_id}"
              }
              service_registration "kubernetes" {}
            EOF
          }
        }
        dataStorage = {
          enabled      = true
          size         = "10Gi"
          storageClass = null
        }
        extraEnvironmentVars = {
          VAULT_SEAL_TYPE          = "awskms"
          VAULT_AWSKMS_SEAL_KEY_ID = dependency.kms.outputs.vault_unseal_key_id
          AWS_REGION               = local.region
        }
      }
      injector = { enabled = true }
      csi      = { enabled = true }
      ui       = { enabled = true }
    })
  }[local.env_cfg.locals.vault_mode]
}
