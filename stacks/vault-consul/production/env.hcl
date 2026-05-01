locals {
  name = "production"

  _common  = read_terragrunt_config("${get_repo_root()}/common.hcl")
  _project = local._common.locals.project
  _region  = local._common.locals.region

  # ── AWS Provider ─────────────────────────────────────────────
  provider_content = <<-EOF
    provider "aws" {
      region = "${local._region}"

      default_tags {
        tags = {
          Project     = "${local._project}"
          Environment = "${local.name}"
          ManagedBy   = "terragrunt"
        }
      }
    }
  EOF

  # ── Remote state (key added by root.hcl) ─────────────────────
  backend_config = {
    bucket         = "tf-state-terragrunt-stacks"
    region         = local._region
    dynamodb_table = "tf-state-lock"
    encrypt        = true
  }

  # ── Feature flags ──────────────────────────────────────────────
  # All features enabled for real AWS.

  # EKS
  create_cluster_security_group            = true
  create_node_security_group               = true
  create_cluster_addons                    = true
  enable_cluster_creator_admin_permissions = true
  update_launch_template_default_version   = true
  use_latest_ami_release_version           = true
  eks_kubernetes_version                   = "1.35"
  eks_node_instance_types                  = ["t3.medium"]
  eks_node_min_size                        = 4
  eks_node_max_size                        = 6
  eks_node_desired_size                    = 5
  eks_endpoint_public_access_cidrs         = ["0.0.0.0/0"] # Open: free GitHub runners have dynamic IPs. Restrict after enabling github-runner unit (self-hosted in VPC).
  eks_cluster_enabled_log_types            = []            # free tier: disable all (CloudWatch Logs ingestion ~$0.50/GB)

  # VPC — single NAT to cut cost (~$32/mo vs ~$96/mo for 3 AZs)
  enable_nat_gateway = true
  single_nat_gateway = true

  # RDS
  rds_multi_az                = false
  rds_deletion_protection     = false # free tier demo — match current AWS state, easier teardown
  rds_performance_insights    = false # free tier db.t3.micro doesn't support Performance Insights
  rds_monitoring_interval     = 0
  rds_skip_final_snapshot     = true # free tier demo — no snapshot storage cost on destroy
  rds_create_monitoring_role  = false
  rds_instance_class          = "db.t3.micro"
  rds_backup_retention_period = 0 # free tier limit: 0 (no automated backups)
  rds_allocated_storage       = 20
  rds_max_allocated_storage   = 20

  # GitHub Actions Runner — disabled for freetear single-node (would saturate 1 t3.small)
  enable_github_runner = false

  # ── Resolved env-specific values ─────────────────────────────
  # Units read these directly — no ternaries needed.

  kubeconfig_path     = pathexpand("~/.kube/config")
  kubeconfig_hook_cmd = "aws eks update-kubeconfig --name terragrunt-infra-eks --region ap-southeast-1 && echo '✓ aws kubeconfig ready'"

  # Vault — dev mode for freetear (no PVC, single replica). Switch to "ha" for real prod.
  vault_mode      = "dev"
  dev_root_token  = "root"
  ssm_endpoint    = ""
  vault_token_cmd = "aws ssm get-parameter --name /terragrunt-infra/vault/root-token --with-decryption --query Parameter.Value --output text 2>/dev/null || echo root"

  # ArgoCD — NodePort to skip $16/mo NLB. Use kubectl port-forward to access.
  argocd_service_type = "NodePort"

  # DB: no overrides — use real RDS outputs
  rds_endpoint_override = ""
  rds_username_override = ""
  rds_password_override = ""
  db_ssl_mode           = "require" # TODO: upgrade to "verify-full" after mounting RDS CA bundle in Vault pods
}
