# Dev mode (ministack): SSM root token owned by TF state.
# Value written by scripts/vault-init.sh (after_hook in terragrunt.hcl).

resource "aws_ssm_parameter" "vault_root_token_dev" {
  count = var.vault_mode == "dev" ? 1 : 0

  name      = local.ssm_token_name
  type      = "SecureString"
  value     = "placeholder-overwritten-by-vault-init-script"
  overwrite = true

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [helm_release.vault]
}
