locals {
  vault_dev_values = yamlencode({
    server = {
      enabled = true
      dev = {
        enabled      = true
        devRootToken = "root"
      }
      serviceAccount = {
        annotations = var.vault_sa_annotations
      }
    }
    injector = { enabled = false }
    csi      = { enabled = false }
    ui       = { enabled = true }
  })

  vault_ha_values = yamlencode({
    server = {
      enabled = true
      ha = {
        enabled  = true
        replicas = var.replicas
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
              region     = "${var.region}"
              kms_key_id = "${var.kms_key_id}"
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
        VAULT_AWSKMS_SEAL_KEY_ID = var.kms_key_id
        AWS_REGION               = var.region
      }

      serviceAccount = {
        annotations = var.vault_sa_annotations
      }
    }

    injector = { enabled = true }
    csi      = { enabled = true }
    ui       = { enabled = true }
  })
}

resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  namespace        = "vault"
  create_namespace = true

  values = [var.use_ministack ? local.vault_dev_values : local.vault_ha_values]
}

resource "helm_release" "vault_secrets_operator" {
  name             = "vault-secrets-operator"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault-secrets-operator"
  namespace        = "vault-secrets-operator-system"
  create_namespace = true

  depends_on = [helm_release.vault]
}

locals {
  ssm_token_name   = "/terragrunt-infra/vault/root-token"
  ssm_endpoint_arg = var.ssm_endpoint != "" ? "--endpoint-url ${var.ssm_endpoint}" : ""
}

resource "null_resource" "vault_init" {
  depends_on = [helm_release.vault, helm_release.vault_secrets_operator]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
    command = <<-EOF
      set -euo pipefail

      echo "Waiting for Vault pods..."
      kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=vault \
        -n vault --timeout=300s

      if [ "${var.use_ministack}" = "true" ]; then
        # Dev mode: already unsealed, root token is hardcoded "root"
        echo "MiniStack dev mode — storing hardcoded root token in SSM..."
        AWS_ACCESS_KEY_ID="test" \
        AWS_SECRET_ACCESS_KEY="test" \
        AWS_DEFAULT_REGION="${var.region}" \
        aws ssm put-parameter \
          --name "${local.ssm_token_name}" \
          --value "root" \
          --type SecureString \
          --overwrite \
          ${local.ssm_endpoint_arg}
        echo "Done."
      else
        # Production: port-forward and run vault operator init
        kubectl port-forward svc/vault 18200:8200 -n vault &
        PF_PID=$!
        trap "kill $PF_PID 2>/dev/null || true" EXIT
        sleep 5

        export VAULT_ADDR="http://127.0.0.1:18200"

        INITIALIZED=$(vault status -format=json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['initialized'])" 2>/dev/null || echo "false")

        if [ "$INITIALIZED" = "False" ] || [ "$INITIALIZED" = "false" ]; then
          echo "Initializing Vault..."
          INIT_JSON=$(vault operator init \
            -recovery-shares=1 \
            -recovery-threshold=1 \
            -format=json)

          ROOT_TOKEN=$(echo "$INIT_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['root_token'])")

          echo "Storing root token in SSM..."
          AWS_DEFAULT_REGION="${var.region}" \
          aws ssm put-parameter \
            --name "${local.ssm_token_name}" \
            --value "$ROOT_TOKEN" \
            --type SecureString \
            --overwrite

          echo "Vault initialized and root token stored."
        else
          echo "Vault already initialized, skipping."
        fi
      fi
    EOF
  }

  triggers = {
    vault_helm_version = helm_release.vault.metadata[0].app_version
  }
}

data "aws_ssm_parameter" "vault_root_token" {
  name            = local.ssm_token_name
  with_decryption = true

  depends_on = [null_resource.vault_init]
}
