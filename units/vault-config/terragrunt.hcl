include "root" {
  path = find_in_parent_folders("terragrunt.hcl")
}

dependency "vault" {
  config_path = "../vault"

  mock_outputs = {
    vault_address = "http://vault.vault.svc.cluster.local:8200"
  }
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_endpoint                   = "https://mock"
    cluster_certificate_authority_data = "bW9jaw=="
  }
}

dependency "rds" {
  config_path = "../rds"

  mock_outputs = {
    rds_endpoint = "mock:5432"
    rds_username = "postgres"
  }
}

inputs = {
  vault_address      = dependency.vault.outputs.vault_address
  kubernetes_host    = dependency.eks.outputs.cluster_endpoint
  kubernetes_ca_cert = base64decode(dependency.eks.outputs.cluster_certificate_authority_data)
  rds_endpoint       = dependency.rds.outputs.rds_endpoint
  rds_username       = dependency.rds.outputs.rds_username
  rds_password       = get_env("RDS_MASTER_PASSWORD", "")

  payments_processor_password = get_env("PAYMENTS_PROCESSOR_PASSWORD", "changeme")
}
