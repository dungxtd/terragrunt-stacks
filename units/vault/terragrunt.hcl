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
  ssm_endpoint        = local.env_cfg.locals.ssm_endpoint
  kubeconfig_path     = local.env_cfg.locals.kubeconfig_path

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
      injector = { enabled = true }
      csi      = { enabled = false }
      ui       = { enabled = true }
    })

    ha = yamlencode({
      server = {
        enabled = true
        ha = {
          enabled   = true
          replicas  = 3
          setNodeId = true
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
                retry_join {
                  leader_api_addr = "http://vault-0.vault-internal:8200"
                }
                retry_join {
                  leader_api_addr = "http://vault-1.vault-internal:8200"
                }
                retry_join {
                  leader_api_addr = "http://vault-2.vault-internal:8200"
                }
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
