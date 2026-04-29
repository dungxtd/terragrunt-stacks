# Shared k8s provider config for units that deploy to EKS.
# Units that include this file must NOT define their own dependency "eks".
#
# Auth strategy:
#   ministack → config_path = <repo>/.kubeconfig-ministack  (run: make ms-kubeconfig)
#   aws       → config_path = ~/.kube/config                (run: make kubeconfig)

locals {
  _local_cfg     = read_terragrunt_config("${get_repo_root()}/local.hcl")
  _env_cfg       = read_terragrunt_config("${get_repo_root()}/envs/${local._local_cfg.locals.active_env}.hcl")
  _use_ministack = local._env_cfg.locals.use_ministack

  _kubeconfig_path = local._use_ministack ? "${get_repo_root()}/.kubeconfig-ministack" : "~/.kube/config"
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
      kubernetes {
        config_path = "${local._kubeconfig_path}"
      }
    }

    provider "kubernetes" {
      config_path = "${local._kubeconfig_path}"
    }
  EOF
}
