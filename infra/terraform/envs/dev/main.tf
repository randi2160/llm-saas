terraform {
  backend "s3" {}
}

locals {
  # single source of truth for the cluster/env name
  name = "${var.project}-${var.environment}"
}

# Get available AZs in the current region
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # pick the first var.az_count AZs
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  enable_nat_gateway      = true
  single_nat_gateway      = true # cost-friendly for dev
  enable_vpn_gateway      = false
  enable_dns_hostnames    = true
  enable_dns_support      = true
  map_public_ip_on_launch = false

  tags = {
    Name = local.name
  }
}
