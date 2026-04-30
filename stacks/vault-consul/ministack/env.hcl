locals {
  name = "ministack"

  _common  = read_terragrunt_config("${get_repo_root()}/common.hcl")
  _project = local._common.locals.project
  _region  = local._common.locals.region

  # ── MiniStack connection (internal to provider/backend) ──────
  _endpoint   = "http://localhost:4566"
  _access_key = "test"
  _secret_key = "test"

  # ── AWS Provider ─────────────────────────────────────────────
  provider_content = <<-EOF
    provider "aws" {
      region     = "${local._region}"
      access_key = "${local._access_key}"
      secret_key = "${local._secret_key}"

      skip_credentials_validation = true
      skip_metadata_api_check     = true
      skip_requesting_account_id  = true
      s3_use_path_style           = true

      default_tags {
        tags = {
          Project     = "${local._project}"
          Environment = "${local.name}"
          ManagedBy   = "terragrunt"
        }
      }

      endpoints {
        acm            = "${local._endpoint}"
        cloudwatchlogs = "${local._endpoint}"
        dynamodb       = "${local._endpoint}"
        ec2            = "${local._endpoint}"
        ecr            = "${local._endpoint}"
        ecs            = "${local._endpoint}"
        eks            = "${local._endpoint}"
        elbv2          = "${local._endpoint}"
        iam            = "${local._endpoint}"
        kms            = "${local._endpoint}"
        rds            = "${local._endpoint}"
        route53        = "${local._endpoint}"
        s3             = "${local._endpoint}"
        secretsmanager = "${local._endpoint}"
        sns            = "${local._endpoint}"
        sqs            = "${local._endpoint}"
        ssm            = "${local._endpoint}"
        sts            = "${local._endpoint}"
      }
    }
  EOF

  # ── Remote state (key added by root.hcl) ─────────────────────
  backend_config = {
    bucket                      = "tf-state-${local._project}-${local._region}"
    region                      = local._region
    dynamodb_table              = "tf-state-lock"
    encrypt                     = false
    access_key                  = local._access_key
    secret_key                  = local._secret_key
    endpoint                    = local._endpoint
    dynamodb_endpoint           = local._endpoint
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    force_path_style            = true
    skip_bucket_versioning      = true
    skip_bucket_ssencryption    = true
    skip_bucket_root_access     = true
    skip_bucket_enforced_tls    = true
  }

  # ── Feature flags ──────────────────────────────────────────────
  # Disable resources that MiniStack cannot handle properly.

  # EKS: security-group-rule creation hangs; access entries API unsupported
  create_cluster_security_group            = false
  create_node_security_group               = false
  create_cluster_addons                    = false
  enable_cluster_creator_admin_permissions = false
  update_launch_template_default_version   = false
  use_latest_ami_release_version           = false
  eks_kubernetes_version                   = "1.32"
  eks_node_instance_types                  = ["t3.medium"]
  eks_node_min_size                        = 1
  eks_node_max_size                        = 3
  eks_node_desired_size                    = 2
  eks_endpoint_public_access_cidrs         = ["0.0.0.0/0"]
  eks_cluster_enabled_log_types            = ["api", "audit", "authenticator"]

  # VPC: NAT Gateways are not functional in MiniStack
  enable_nat_gateway = false
  single_nat_gateway = true

  # RDS: some advanced features are unsupported
  rds_multi_az                = false
  rds_deletion_protection     = false
  rds_performance_insights    = false
  rds_monitoring_interval     = 0
  rds_create_monitoring_role  = false
  rds_instance_class          = "db.t3.micro"
  rds_backup_retention_period = 0
  rds_allocated_storage       = 20
  rds_max_allocated_storage   = 20
  rds_skip_final_snapshot     = true

  # GitHub Actions Runner: not needed locally
  enable_github_runner = false

  # ── Resolved env-specific values ─────────────────────────────
  # Units read these directly — no ternaries needed.

  kubeconfig_path     = "${get_repo_root()}/.kubeconfig-ministack"
  kubeconfig_hook_cmd = "docker exec ministack-eks-terragrunt-infra-eks cat /etc/rancher/k3s/k3s.yaml 2>/dev/null | sed 's|127.0.0.1|localhost|g' > ${get_repo_root()}/.kubeconfig-ministack && echo '✓ ministack kubeconfig ready'"

  # Vault
  vault_mode      = "dev"
  dev_root_token  = "root"
  ssm_endpoint    = "http://localhost:4566"
  vault_token_cmd = "AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=ap-southeast-1 aws ssm get-parameter --endpoint-url http://localhost:4566 --name /terragrunt-infra/vault/root-token --with-decryption --query Parameter.Value --output text 2>/dev/null || echo root"

  # ArgoCD
  argocd_service_type = "NodePort"

  # DB overrides (MiniStack PostgreSQL via Docker host)
  rds_endpoint_override = "host.docker.internal:15432"
  rds_username_override = "postgres"
  rds_password_override = "password"
  db_ssl_mode           = "disable"
}
