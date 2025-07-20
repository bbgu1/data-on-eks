data "aws_availability_zones" "available" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

#---------------------------------------------------------------
# VPC
#---------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.15"

  name = var.name
  cidr = var.vpc_cidr

  azs = local.azs
  
  # Primary CIDR - Private and public subnets
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]
  
  # Secondary CIDR - Private subnets for EKS pods and nodes
  secondary_cidr_blocks = var.secondary_cidrs
  private_subnet_names = concat(
    [for k, v in local.azs : "${var.name}-private-${v}"],
    [for k, v in local.azs : "${var.name}-private-secondary-${v}"]
  )
  public_subnet_names = [for k, v in local.azs : "${var.name}-public-${v}"]

  # Add secondary CIDR subnets
  private_subnets = concat(
    [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)],
    [for k, v in local.azs : cidrsubnet(var.secondary_cidrs[0], 2, k)]
  )

  enable_nat_gateway = true
  single_nat_gateway = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Manage so we can name it
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${var.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${var.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${var.name}-default" }

  public_subnet_tags = merge(var.public_subnet_tags, {
    "kubernetes.io/role/elb" = 1
  })

  private_subnet_tags = merge(var.private_subnet_tags, {
    "kubernetes.io/role/internal-elb" = 1
  })

  tags = var.tags
}