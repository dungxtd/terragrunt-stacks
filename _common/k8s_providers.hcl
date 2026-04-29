# Shared k8s provider config for units that deploy to EKS.
# Units that include this file must NOT define their own dependency "eks".
#
# Auth strategy:
#   ministack → config_path = <repo>/.kubeconfig-ministack  (run: make ms-kubeconfig)
#   aws       → config_path = ~/.kube/config                (run: make kubeconfig)

locals {
  _env_name        = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.name
  _env_cfg         = read_terragrunt_config("${get_repo_root()}/envs/${local._env_name}.hcl")
  _kubeconfig_path = local._env_cfg.locals.kubeconfig_path
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_endpoint                   = "https://mock"
    cluster_certificate_authority_data = "bW9jaw=="
    cluster_name                       = "mock-cluster"
    oidc_provider_arn                  = "arn:aws:iam::mock:oidc-provider"
  }
}

generate "k8s_providers" {
  path      = "k8s_providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "helm" {
      kubernetes = {
        config_path = "${local._kubeconfig_path}"
      }
    }

    provider "kubernetes" {
      config_path = "${local._kubeconfig_path}"
    }
  EOF
}
