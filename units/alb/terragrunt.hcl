include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "k8s" {
  path = "${get_repo_root()}/_common/k8s_providers.hcl"
}

locals {
  common  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  env_cfg = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  alb     = local.env_cfg.locals.alb
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id         = "vpc-mock"
    public_subnets = ["subnet-mock-1", "subnet-mock-2"]
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# aws-alb installs the controller (provides TargetGroupBinding CRD).
# Must be ready before this unit applies.
dependency "aws_alb" {
  config_path = "../aws-alb"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

inputs = {
  project           = local.common.locals.project
  region            = local.common.locals.region
  vpc_id            = dependency.vpc.outputs.vpc_id
  public_subnet_ids = dependency.vpc.outputs.public_subnets
  tags              = local.common.locals.common_tags

  # Per-env ALB config (defined in env.hcl).
  service_namespace = local.alb.service_namespace
  service_name      = local.alb.service_name
  service_port      = local.alb.service_port
  listen_port       = local.alb.listen_port
  scheme            = local.alb.scheme
  health_check_path = local.alb.health_check_path
  certificate_arn   = local.alb.certificate_arn
}
