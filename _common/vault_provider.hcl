# Shared Vault provider config for units that configure Vault.
# Provides: vault dependency, generated vault provider, port-forward hook.
# Units that include this file must NOT define their own dependency "vault"
# or provider "vault" block.
#
# Auth strategy:
#   in-cluster (ARC runner) → vault.vault.svc.cluster.local:8200
#   local dev               → localhost via port-forward
#
# Token resolution (first wins):
#   1. VAULT_TOKEN env var (CI sets this; skips SSM call)
#   2. vault_token_cmd from env.hcl (SSM fetch with || echo root fallback)

locals {
  _env_cfg    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  _kubeconfig = local._env_cfg.locals.kubeconfig_path
  _vault_port = 18200

  _vault_address = "http://localhost:${local._vault_port}"

  _vault_token_env = get_env("VAULT_TOKEN", "")
  _vault_token     = local._vault_token_env != "" ? local._vault_token_env : run_cmd("--terragrunt-quiet", "bash", "-c", local._env_cfg.locals.vault_token_cmd)
}

dependency "vault" {
  config_path = "../vault"

  mock_outputs = {
    vault_address = "http://vault.vault.svc.cluster.local:8200"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
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
