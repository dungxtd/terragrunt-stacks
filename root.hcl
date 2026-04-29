locals {
  common = read_terragrunt_config("${get_repo_root()}/common.hcl")

  # Env resolved from the nearest env.hcl walking up from the unit directory.
  # stacks/vault-consul/production/env.hcl → production
  # stacks/vault-consul/ministack/env.hcl  → ministack
  _env_name = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.name
  env_cfg   = read_terragrunt_config("${get_repo_root()}/envs/${local._env_name}.hcl")

  project = local.common.locals.project
  region  = local.common.locals.region

  # Resolved from envs/<active_env>.hcl
  use_ministack      = local.env_cfg.locals.use_ministack
  ministack_endpoint = local.env_cfg.locals.endpoint
  ministack_access   = local.env_cfg.locals.access_key
  ministack_secret   = local.env_cfg.locals.secret_key

  # ── Provider: AWS ────────────────────────────────────────────
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

  # ── Provider: MiniStack ──────────────────────────────────────
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
        cloudwatchlogs = "${local.ministack_endpoint}"
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

  # ── Remote state: AWS ────────────────────────────────────────
  backend_aws = {
    bucket         = "tf-state-terragrunt-stacks"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.region
    dynamodb_table = "tf-state-lock"
    encrypt        = true
  }

  # ── Remote state: MiniStack ──────────────────────────────────
  backend_ministack = {
    bucket                      = "tf-state-${local.project}-${local.region}"
    key                         = "${path_relative_to_include()}/terraform.tfstate"
    region                      = local.region
    dynamodb_table              = "tf-state-lock"
    encrypt                     = false
    access_key                  = local.ministack_access
    secret_key                  = local.ministack_secret
    endpoint                    = local.ministack_endpoint
    dynamodb_endpoint           = local.ministack_endpoint
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    force_path_style            = true
    skip_bucket_versioning      = true
    skip_bucket_ssencryption    = true
    skip_bucket_root_access     = true
    skip_bucket_enforced_tls    = true
  }
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
  config = local.use_ministack ? local.backend_ministack : local.backend_aws
}

terraform {
  extra_arguments "common_vars" {
    commands = get_terraform_commands_that_need_vars()

    optional_var_files = [
      "${get_terragrunt_dir()}/terraform.tfvars",
    ]
  }
}
