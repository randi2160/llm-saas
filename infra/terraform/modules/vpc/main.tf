data "aws_availability_zones" "available" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.name
  cidr = var.vpc_cidr

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /20 public, /20 private (adjust as you like)
  public_subnets  = [for i, az in azs : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i, az in azs : cidrsubnet(var.vpc_cidr, 4, i + 16)]

  enable_nat_gateway       = true
  single_nat_gateway       = true
  enable_dns_hostnames     = true
  enable_dns_support       = true
  map_public_ip_on_launch  = false

  tags = { Tier = "network" }
}
