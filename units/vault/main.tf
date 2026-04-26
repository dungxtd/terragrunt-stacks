resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  namespace        = "vault"
  create_namespace = true

  values = [yamlencode({
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

    injector = {
      enabled = true
    }

    csi = {
      enabled = true
    }

    ui = {
      enabled = true
    }
  })]
}

resource "helm_release" "vault_secrets_operator" {
  name             = "vault-secrets-operator"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault-secrets-operator"
  namespace        = "vault-secrets-operator-system"
  create_namespace = true

  depends_on = [helm_release.vault]
}
