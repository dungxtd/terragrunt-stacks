module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.19"

  name               = "${var.project}-eks"
  kubernetes_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets

  endpoint_public_access       = true
  endpoint_private_access      = true
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  enabled_log_types                      = var.cluster_enabled_log_types
  cloudwatch_log_group_retention_in_days = 365

  # Min deletion window (default 30) — speeds cleanup, avoids KMS pile-up
  kms_key_deletion_window_in_days = 7

  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  create_security_group      = var.create_cluster_security_group
  create_node_security_group = var.create_node_security_group

  # Range covers Vault/Consul injectors (8080), Linkerd (8443), AWS LBC/ArgoCD (9443).
  # apiserver→pod webhook calls otherwise time out → failurePolicy=Ignore silently
  # skips injection (vault-agent + Consul envoy sidecars never added).
  node_security_group_additional_rules = {
    ingress_cluster_webhooks = {
      description                   = "Allow EKS control plane to reach admission webhooks on nodes"
      protocol                      = "tcp"
      from_port                     = 8080
      to_port                       = 9443
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size

      update_launch_template_default_version = var.update_launch_template_default_version
      use_latest_ami_release_version         = var.use_latest_ami_release_version

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required" # IMDSv2 only (CKV_AWS_79)
        http_put_response_hop_limit = 1          # block container IMDS hop (CKV_AWS_341)
      }

      labels = {
        role = "general"
      }
    }
  }

  addons = var.create_cluster_addons ? {
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    eks-pod-identity-agent = { most_recent = true, before_compute = true }
    kube-proxy             = { most_recent = true }
    coredns                = { most_recent = true }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
      # defaultStorageClass.enabled marks gp2 as default so PVCs without
      # explicit storageClassName bind. Without this, consul-server PVC
      # stays Pending on fresh cluster.
      configuration_values = jsonencode({
        defaultStorageClass = { enabled = true }
      })
    }
  } : {}

  tags = var.tags
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.58"

  role_name = "${var.project}-ebs-csi"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}
