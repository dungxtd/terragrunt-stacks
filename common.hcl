locals {
  project = "terragrunt-infra"
  region  = "ap-southeast-1"

  # VPC CIDR
  vpc_cidr = "10.0.0.0/16"

  # Availability zones
  azs = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]

  # Tags applied to all resources
  common_tags = {
    Project   = local.project
    ManagedBy = "terragrunt"
  }
}
