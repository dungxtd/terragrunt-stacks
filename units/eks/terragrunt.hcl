include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  common  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  env_cfg = include.root.locals.env_cfg
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id          = "vpc-mock"
    private_subnets = ["subnet-a", "subnet-b", "subnet-c"]
  }
}

inputs = {
  project         = local.common.locals.project
  vpc_id          = dependency.vpc.outputs.vpc_id
  private_subnets = dependency.vpc.outputs.private_subnets
  tags            = local.common.locals.common_tags

  create_cluster_security_group            = local.env_cfg.locals.create_cluster_security_group
  create_node_security_group               = local.env_cfg.locals.create_node_security_group
  create_cluster_addons                    = local.env_cfg.locals.create_cluster_addons
  enable_cluster_creator_admin_permissions = local.env_cfg.locals.enable_cluster_creator_admin_permissions
  update_launch_template_default_version   = local.env_cfg.locals.update_launch_template_default_version
  use_latest_ami_release_version           = local.env_cfg.locals.use_latest_ami_release_version
  node_instance_types                      = local.env_cfg.locals.eks_node_instance_types
  node_min_size                            = local.env_cfg.locals.eks_node_min_size
  node_max_size                            = local.env_cfg.locals.eks_node_max_size
  node_desired_size                        = local.env_cfg.locals.eks_node_desired_size
  kubernetes_version                       = local.env_cfg.locals.eks_kubernetes_version
  cluster_endpoint_public_access_cidrs     = local.env_cfg.locals.eks_endpoint_public_access_cidrs
  cluster_enabled_log_types                = local.env_cfg.locals.eks_cluster_enabled_log_types
}

terraform {
  after_hook "gen_kubeconfig" {
    commands     = ["apply"]
    execute      = ["bash", "-c", local.env_cfg.locals.kubeconfig_hook_cmd]
    run_on_error = false
  }
}
