locals {
  common    = read_terragrunt_config("${get_repo_root()}/common.hcl")
  local_cfg = read_terragrunt_config("${get_repo_root()}/local.hcl")

  project = local.common.locals.project
  region  = local.common.locals.region

  use_ministack      = local.local_cfg.locals.use_ministack
  ministack_endpoint = local.local_cfg.locals.ministack_endpoint
  ministack_access   = local.local_cfg.locals.ministack_access_key
  ministack_secret   = local.local_cfg.locals.ministack_secret_key

  provider_aws = <<-EOF
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

  provider_ministack = <<-EOF
    provider "aws" {
      region     = "${local.region}"
      access_key = "${local.ministack_access}"
      secret_key = "${local.ministack_secret}"

      skip_credentials_validation = true
      skip_metadata_api_check     = true
      skip_requesting_account_id  = true
      s3_use_path_style           = true

      default_tags {
        tags = {
          Project   = "${local.project}"
          ManagedBy = "terragrunt"
        }
      }

      endpoints {
        acm            = "${local.ministack_endpoint}"
        dynamodb       = "${local.ministack_endpoint}"
        ec2            = "${local.ministack_endpoint}"
        ecr            = "${local.ministack_endpoint}"
        ecs            = "${local.ministack_endpoint}"
        eks            = "${local.ministack_endpoint}"
        elbv2          = "${local.ministack_endpoint}"
        iam            = "${local.ministack_endpoint}"
        kms            = "${local.ministack_endpoint}"
        rds            = "${local.ministack_endpoint}"
        route53        = "${local.ministack_endpoint}"
        s3             = "${local.ministack_endpoint}"
        secretsmanager = "${local.ministack_endpoint}"
        sns            = "${local.ministack_endpoint}"
        sqs            = "${local.ministack_endpoint}"
        ssm            = "${local.ministack_endpoint}"
        sts            = "${local.ministack_endpoint}"
      }
    }
  EOF
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
  contents  = local.use_ministack ? local.provider_ministack : local.provider_aws
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = merge(
    {
      bucket         = "tf-state-${local.project}-${local.region}"
      key            = "${path_relative_to_include()}/terraform.tfstate"
      region         = local.region
      dynamodb_table = "tf-state-lock"
      encrypt        = true
    },
    local.use_ministack ? {
      access_key                  = local.ministack_access
      secret_key                  = local.ministack_secret
      endpoint                    = local.ministack_endpoint
      dynamodb_endpoint           = local.ministack_endpoint
      skip_credentials_validation = true
      skip_metadata_api_check     = true
      skip_requesting_account_id  = true
      force_path_style            = true
    } : {}
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
