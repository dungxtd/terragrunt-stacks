locals {
  common = read_terragrunt_config("${get_repo_root()}/common.hcl")

  project = local.common.locals.project
  region  = local.common.locals.region
}

generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.7"

      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 5.0"
        }
        helm = {
          source  = "hashicorp/helm"
          version = "~> 2.0"
        }
        kubernetes = {
          source  = "hashicorp/kubernetes"
          version = "~> 2.0"
        }
        vault = {
          source  = "hashicorp/vault"
          version = "~> 4.0"
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
  contents  = <<-EOF
    provider "aws" {
      region = "${local.region}"

      default_tags {
        tags = {
          Project   = "${local.project}"
          ManagedBy = "terragrunt"
        }
      }
    }
  EOF
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "tf-state-${local.project}-${local.region}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.region
    dynamodb_table = "tf-state-lock"
    encrypt        = true
  }
}

terraform {
  extra_arguments "common_vars" {
    commands = get_terraform_commands_that_need_vars()

    optional_var_files = [
      "${get_terragrunt_dir()}/terraform.tfvars",
    ]
  }
}
