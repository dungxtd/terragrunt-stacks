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

# Ordering-only dependency: ensures vault unit (Helm install + after_hook)
# completes before this unit applies. Outputs not consumed.
dependency "vault" {
  config_path = "../vault"

  mock_outputs                            = {}
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

terraform {
  before_hook "vault_port_forward" {
    commands = ["apply", "plan", "destroy"]
    execute = [
      "bash", "-c",
      "if lsof -i :${local._vault_port} >/dev/null 2>&1; then echo 'vault port-forward already running'; else KUBECONFIG=${local._kubeconfig} kubectl port-forward svc/vault ${local._vault_port}:8200 -n vault >/dev/null 2>&1 & sleep 3 && echo 'vault port-forward started on :${local._vault_port}'; fi"
    ]
  }
}
