# Shared Vault provider config for units that configure Vault.
# Provides: vault dependency, generated vault provider.
# Units that include this file must NOT define their own dependency "vault"
# or provider "vault" block.
#
# Auth strategy:
#   in-cluster (ARC runner) → vault.vault.svc.cluster.local:8200
#   local dev               → localhost via port-forward or NodePort

locals {
  _local_cfg     = read_terragrunt_config("${get_repo_root()}/local.hcl")
  _env_cfg       = read_terragrunt_config("${get_repo_root()}/envs/${local._local_cfg.locals.active_env}.hcl")
  _use_ministack = local._env_cfg.locals.use_ministack
  _kubeconfig    = local._use_ministack ? "${get_repo_root()}/.kubeconfig-ministack" : pathexpand("~/.kube/config")
  _vault_port    = 18200

  # Local dev: port-forward to localhost; in-cluster (ARC): K8s DNS
  _vault_address = local._use_ministack ? "http://localhost:${local._vault_port}" : "http://localhost:${local._vault_port}"

  # Resolved here so generate block can reference local.* (dependency.* not allowed in generate contents)
  _vault_token = dependency.vault.outputs.vault_root_token
}

dependency "vault" {
  config_path = "../vault"

  mock_outputs = {
    vault_address    = "http://vault.vault.svc.cluster.local:8200"
    vault_root_token = "mock-token"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "destroy"]
  mock_outputs_merge_strategy_with_state  = "shallow"
}

generate "vault_provider" {
  path      = "vault_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "vault" {
      address          = "${local._vault_address}"
      token            = "${local._vault_token}"
      skip_child_token = true
    }
  EOF
}

terraform {
  before_hook "vault_port_forward" {
    commands = ["apply", "plan", "destroy"]
    execute = [
      "bash", "-c",
      "if lsof -i :${local._vault_port} >/dev/null 2>&1; then echo 'vault port-forward already running'; else KUBECONFIG=${local._kubeconfig} kubectl port-forward svc/vault ${local._vault_port}:8200 -n vault >/dev/null 2>&1 & sleep 3 && echo 'vault port-forward started on :${local._vault_port}'; fi"
    ]
  }
}

# Satisfy the kubernetes/helm providers required by root.hcl versions.tf
generate "k8s_providers" {
  path      = "k8s_providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "helm" {
      kubernetes {
        config_path = "${local._kubeconfig}"
      }
    }

    provider "kubernetes" {
      config_path = "${local._kubeconfig}"
    }
  EOF
}
