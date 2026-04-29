# Shared Vault provider config for units that configure Vault.
# Provides: vault dependency, generated vault provider.
# Units that include this file must NOT define their own dependency "vault"
# or provider "vault" block.
#
# Auth strategy:
#   in-cluster (ARC runner) → vault.vault.svc.cluster.local:8200
#   local dev               → localhost via port-forward or NodePort

locals {
  _env_name      = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.name
  _env_cfg       = read_terragrunt_config("${get_repo_root()}/envs/${local._env_name}.hcl")
  _use_ministack = local._env_cfg.locals.use_ministack
  _kubeconfig    = local._use_ministack ? "${get_repo_root()}/.kubeconfig-ministack" : pathexpand("~/.kube/config")
  _vault_port    = 18200

  # Local dev: port-forward to localhost; in-cluster (ARC): K8s DNS
  _vault_address = local._use_ministack ? "http://localhost:${local._vault_port}" : "http://localhost:${local._vault_port}"

  # dependency.* not allowed in locals or generate blocks during stack evaluation.
  # Fetch vault root token from SSM at parse time via run_cmd.
  # MiniStack: reads from LocalStack; AWS: reads from real SSM. Falls back to "mock-token" if not yet initialized.
  _vault_token = run_cmd("--terragrunt-quiet", "bash", "-c",
    local._use_ministack
    ? "AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=ap-southeast-1 aws ssm get-parameter --endpoint-url http://localhost:4566 --name /terragrunt-infra/vault/root-token --with-decryption --query Parameter.Value --output text 2>/dev/null || echo root"
    : "aws ssm get-parameter --name /terragrunt-infra/vault/root-token --with-decryption --query Parameter.Value --output text 2>/dev/null || echo mock-token"
  )
}

generate "vault_provider" {
  path      = "vault_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "vault" {
      address          = "${local._vault_address}"
      token            = "${local._vault_token}"
      skip_child_token = true
    }
  EOF
}

terraform {
  before_hook "vault_port_forward" {
    commands = ["apply", "plan", "destroy"]
    execute = [
      "bash", "-c",
      "if lsof -i :${local._vault_port} >/dev/null 2>&1; then echo 'vault port-forward already running'; else KUBECONFIG=${local._kubeconfig} kubectl port-forward svc/vault ${local._vault_port}:8200 -n vault >/dev/null 2>&1 & sleep 3 && echo 'vault port-forward started on :${local._vault_port}'; fi"
    ]
  }
}

# Satisfy the kubernetes/helm providers required by root.hcl versions.tf
generate "k8s_providers" {
  path      = "k8s_providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "helm" {
      kubernetes {
        config_path = "${local._kubeconfig}"
      }
    }

    provider "kubernetes" {
      config_path = "${local._kubeconfig}"
    }
  EOF
}
