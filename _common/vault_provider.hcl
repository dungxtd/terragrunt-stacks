# Shared Vault provider config for units that configure Vault (certs, vault-config).
# Provides: vault dependency (ordering only), generated vault provider, port-forward hook.
# Units that include this file must NOT define their own dependency "vault"
# or provider "vault" block.
#
# Auth: root token read directly from SSM at runtime via data source.
#       Reading from `dependency.vault.outputs.vault_root_token` would return
#       the placeholder value cached in vault-unit tfstate before the
#       after_hook (scripts/vault-init.sh) overwrote SSM with the real token.
# VAULT_TOKEN env var overrides (emergency / local dev escape hatch).

locals {
  _env_cfg         = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  _kubeconfig      = local._env_cfg.locals.kubeconfig_path
  _vault_port      = 18200
  _vault_address   = "http://localhost:${local._vault_port}"
  _vault_token_env = get_env("VAULT_TOKEN", "")
  _ssm_token_name  = "/terragrunt-infra/vault/root-token"
}

# Ordering dependency: ensures vault unit completes before this unit applies.
# vault_address consumed by vault-config inputs; mock used when vault state is
# empty (destroy order: vault-config destroys first, vault state already gone).
dependency "vault" {
  config_path = "../vault"

  mock_outputs = {
    vault_address = "http://vault.vault.svc.cluster.local:8200"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

generate "vault_provider" {
  path      = "vault_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    data "aws_ssm_parameter" "vault_root_token_runtime" {
      name            = "${local._ssm_token_name}"
      with_decryption = true
    }

    provider "vault" {
      address          = "${local._vault_address}"
      token            = ${local._vault_token_env != "" ? "\"${local._vault_token_env}\"" : "data.aws_ssm_parameter.vault_root_token_runtime.value"}
      skip_child_token = true
    }
  EOF
}

# CI runs `make predestroy-production` (which calls scripts/vault-portforward.sh start)
# before Terragrunt, so port 18200 is already open and healthy when this hook fires.
# Hook delegates to the same script — idempotent, skips start if port already open.
# For local dev (make apply-vault-config etc.) the script starts the port-forward itself.
terraform {
  before_hook "vault_port_forward" {
    commands = ["apply", "plan", "destroy"]
    execute  = ["bash", "-c", "KUBECONFIG=${local._kubeconfig} ${get_repo_root()}/scripts/vault-portforward.sh start ${local._vault_port}"]
  }
}
