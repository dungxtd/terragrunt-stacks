# Dev mode (ministack): Vault starts initialized + unsealed with a known token.
# Just wait for Ready then store the static token in SSM/LocalStack.

resource "terraform_data" "vault_init_dev" {
  count = var.vault_mode == "dev" ? 1 : 0

  depends_on = [helm_release.vault, helm_release.vault_secrets_operator]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
    command = <<-EOF
      set -euo pipefail
      echo "Waiting for Vault pod ready (dev mode)..."
      kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=vault \
        -n vault --timeout=300s

      echo "Storing dev root token in SSM..."
      ${local.ssm_env_prefix} \
      aws ssm put-parameter \
        --name "${local.ssm_token_name}" \
        --value "${var.dev_root_token}" \
        --type SecureString \
        --overwrite \
        ${local.ssm_endpoint_arg}
      echo "Done."
    EOF
  }

  triggers_replace = [
    helm_release.vault.metadata.app_version,
    helm_release.vault.version,
  ]
}

# Destroy-time cleanup: SSM root-token written imperatively above is out-of-band.
resource "terraform_data" "vault_ssm_cleanup_dev" {
  count = var.vault_mode == "dev" ? 1 : 0

  input = {
    region       = var.region
    ssm_endpoint = var.ssm_endpoint
    token_name   = local.ssm_token_name
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOF
      ENDPOINT=""
      [ -n "${self.input.ssm_endpoint}" ] && ENDPOINT="--endpoint-url ${self.input.ssm_endpoint}"
      AWS_DEFAULT_REGION="${self.input.region}" \
        aws ssm delete-parameter $ENDPOINT \
        --name "${self.input.token_name}" \
        2>/dev/null || true
    EOF
  }
}
