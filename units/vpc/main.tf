module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr

  azs              = var.azs
  public_subnets   = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnets  = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  database_subnets = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i + 20)]

  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true
  enable_dns_support   = true

  create_database_subnet_group = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"              = "1"
    "kubernetes.io/cluster/${var.project}-eks"     = "shared"
  }

  tags = var.tags
}
