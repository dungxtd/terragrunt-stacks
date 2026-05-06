# HA mode (production): SSM parameters owned by TF state for clean lifecycle.
# Values written by scripts/vault-init.sh (invoked via terragrunt after_hook
# in terragrunt.hcl). lifecycle.ignore_changes prevents TF from clobbering
# the runtime-injected token/keys on subsequent applies.

resource "aws_ssm_parameter" "vault_root_token_ha" {
  count = var.vault_mode == "ha" ? 1 : 0

  name      = local.ssm_token_name
  type      = "SecureString"
  value     = "placeholder-overwritten-by-vault-init-script"
  overwrite = true

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [helm_release.vault]
}

resource "aws_ssm_parameter" "vault_recovery_keys" {
  count = var.vault_mode == "ha" ? 5 : 0

  name      = "/terragrunt-infra/vault/recovery-key-${count.index}"
  type      = "SecureString"
  value     = "placeholder-overwritten-by-vault-init-script"
  overwrite = true

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [helm_release.vault]
}
