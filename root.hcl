locals {
  common = read_terragrunt_config("${get_repo_root()}/common.hcl")

  # Env config resolved from the nearest env.hcl walking up from the unit
  # directory. stacks/vault-consul/<env>/env.hcl carries the full per-env
  # config: provider, backend, feature flags, kubeconfig, vault, RDS overrides.
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl"))
}

generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.12"

      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 6.42"
        }
        helm = {
          source  = "hashicorp/helm"
          version = "~> 3.1"
        }
        kubernetes = {
          source  = "hashicorp/kubernetes"
          version = "~> 2.35"
        }
        vault = {
          source  = "hashicorp/vault"
          version = "~> 5.2"
        }
        tls = {
          source  = "hashicorp/tls"
          version = "~> 4.0"
        }
      }
    }
  EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = local.env_cfg.locals.provider_content
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = merge(
    local.env_cfg.locals.backend_config,
    { key = "${path_relative_to_include()}/terraform.tfstate" }
  )
}

terraform {
  extra_arguments "common_vars" {
    commands = get_terraform_commands_that_need_vars()

    optional_var_files = [
      "${get_terragrunt_dir()}/terraform.tfvars",
    ]
  }
}
