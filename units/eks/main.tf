module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.19"

  name               = "${var.project}-eks"
  kubernetes_version = "1.35"

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnets

  endpoint_public_access  = true
  endpoint_private_access = true

  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions

  create_security_group      = var.create_cluster_security_group
  create_node_security_group = var.create_node_security_group

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size

      update_launch_template_default_version = var.update_launch_template_default_version
      use_latest_ami_release_version         = var.use_latest_ami_release_version

      labels = {
        role = "general"
      }
    }
  }

  addons = var.create_cluster_addons ? {
    vpc-cni    = { most_recent = true, before_compute = true }
    kube-proxy = { most_recent = true, before_compute = true }
    coredns    = { most_recent = true }
  } : {}

  tags = var.tags
}
