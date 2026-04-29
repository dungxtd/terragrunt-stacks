module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project}-eks"
  cluster_version = "1.29"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  create_cluster_security_group = var.create_cluster_security_group
  create_node_security_group    = var.create_node_security_group

  eks_managed_node_groups = {
    default = {
      instance_types = ["m5.large"]
      min_size       = 2
      max_size       = 5
      desired_size   = 3

      update_launch_template_default_version = var.update_launch_template_default_version

      labels = {
        role = "general"
      }
    }
  }

  cluster_addons = var.create_cluster_addons ? {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
  } : {}

  tags = var.tags
}
