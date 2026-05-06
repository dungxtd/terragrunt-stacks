locals {
  vault_service_account_name = "vault"
  ssm_token_name             = "/terragrunt-infra/vault/root-token"
  ssm_endpoint_arg           = var.ssm_endpoint != "" ? "--endpoint-url ${var.ssm_endpoint}" : ""
  ssm_env_prefix             = var.ssm_endpoint != "" ? "AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=${var.region}" : "AWS_DEFAULT_REGION=${var.region}"

  helm_values_dev = yamlencode({
    server = {
      enabled = true
      dev = {
        enabled      = true
        devRootToken = var.dev_root_token
      }
    }
    injector = { enabled = true }
    csi      = { enabled = false }
    ui       = { enabled = true }
  })

  helm_values_ha = yamlencode({
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
              retry_join { leader_api_addr = "http://vault-0.vault-internal:8200" }
              retry_join { leader_api_addr = "http://vault-1.vault-internal:8200" }
              retry_join { leader_api_addr = "http://vault-2.vault-internal:8200" }
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
  version          = "0.32.0"
  namespace        = "vault"
  create_namespace = true

  values = [var.vault_mode == "ha" ? local.helm_values_ha : local.helm_values_dev]

  set = var.vault_mode == "ha" ? [
    {
      name  = "server.serviceAccount.create"
      value = "true"
    },
    {
      name  = "server.serviceAccount.name"
      value = local.vault_service_account_name
      type  = "string"
    },
    {
      name  = "server.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = var.vault_irsa_role_arn
      type  = "string"
    },
  ] : []
}

resource "helm_release" "vault_secrets_operator" {
  name             = "vault-secrets-operator"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault-secrets-operator"
  version          = "1.3.0"
  namespace        = "vault-secrets-operator-system"
  create_namespace = true

  depends_on = [helm_release.vault]
}

data "aws_ssm_parameter" "vault_root_token" {
  name            = local.ssm_token_name
  with_decryption = true

  depends_on = [
    aws_ssm_parameter.vault_root_token_dev,
    aws_ssm_parameter.vault_root_token_ha,
  ]
}
