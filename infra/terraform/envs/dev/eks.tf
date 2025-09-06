module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.20"

  cluster_name                   = local.name
  cluster_version                = "1.30"
  cluster_endpoint_public_access = true
  enable_irsa                    = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  eks_managed_node_groups = {
    general = {
      ami_type       = "AL2_x86_64"
      instance_types = ["m7i.large", "c7i.large"]
      desired_size   = 2
      min_size       = 1
      max_size       = 5
      capacity_type  = "ON_DEMAND"
      labels         = { workload = "general" }
      tags = {
        "k8s.io/cluster-autoscaler/${local.name}" = "owned"
        "k8s.io/cluster-autoscaler/enabled"       = "true"
      }
    }
    gpu = {
      ami_type       = "AL2_x86_64_GPU"
      instance_types = ["g5.xlarge"]
      desired_size   = 0
      min_size       = 0
      max_size       = 2
      capacity_type  = "ON_DEMAND"
      labels         = { workload = "gpu" }
      taints = [{
        key    = "nvidia.com/gpu"
        value  = "present"
        effect = "NO_SCHEDULE"
      }]
      tags = {
        "k8s.io/cluster-autoscaler/${local.name}" = "owned"
        "k8s.io/cluster-autoscaler/enabled"       = "true"
      }
    }
  }

  cloudwatch_log_group_retention_in_days = 14
  cluster_enabled_log_types              = ["api", "audit", "authenticator"]

  # Grant your SSO admin role cluster-admin via EKS Access Entry + Policy
  access_entries = {
    admin = {
      principal_arn = "arn:aws:iam::718277288381:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_4d66485080237ae2"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}

# Use module outputs; don't read cluster details before creation
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}