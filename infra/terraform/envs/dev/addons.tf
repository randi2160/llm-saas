############################
# IRSA roles for add-ons  #
############################

module "irsa_alb" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name_prefix = "${local.name}-alb"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = { Component = "alb-controller" }
}

module "irsa_ca" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name_prefix = "${local.name}-ca"

  attach_cluster_autoscaler_policy = true

  # Tell the IAM module which cluster the autoscaler can manage
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }

  tags = { Component = "cluster-autoscaler" }
}

##############################################
# Service Accounts (annotated with IRSA ARNs)
##############################################

resource "kubernetes_service_account" "alb_sa" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.irsa_alb.iam_role_arn
    }
    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
    }
  }
}

resource "kubernetes_service_account" "ca_sa" {
  metadata {
    name      = "cluster-autoscaler"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.irsa_ca.iam_role_arn
    }
    labels = {
      "k8s-addon"                   = "cluster-autoscaler.addons.k8s.io"
      "k8s-app"                     = "cluster-autoscaler"
      "app.kubernetes.io/component" = "cluster-autoscaler"
      "app.kubernetes.io/name"      = "cluster-autoscaler"
    }
  }
}

################################
# Helm: AWS Load Balancer Ctrl #
################################

resource "helm_release" "aws_load_balancer_controller" {
  name             = "aws-load-balancer-controller"
  namespace        = "kube-system"
  create_namespace = false
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"

  # Use the pre-created SA with IRSA
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  # Required values
  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "region"
    value = var.region
  }
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  # Ensure SA/IRSA is ready before Helm installs the controller
  depends_on = [
    module.irsa_alb,
    kubernetes_service_account.alb_sa
  ]

  wait            = true
  timeout         = 600
  cleanup_on_fail = true
}

#############################
# Helm: Cluster Autoscaler  #
#############################

resource "helm_release" "cluster_autoscaler" {
  name             = "cluster-autoscaler"
  namespace        = "kube-system"
  create_namespace = false
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"

  # Some chart versions use serviceAccount.*, some use rbac.serviceAccount.*
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = "cluster-autoscaler"
  }
  set {
    name  = "rbac.serviceAccount.create"
    value = "false"
  }
  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  # Required for autodiscovery on AWS
  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "cloudProvider"
    value = "aws"
  }
  set {
    name  = "awsRegion"
    value = var.region
  }

  # Sane defaults
  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }
  set {
    name  = "extraArgs.expander"
    value = "least-waste"
  }
  set {
    name  = "extraArgs.scan-interval"
    value = "10s"
  }
  set {
    name  = "extraArgs.skip-nodes-with-local-storage"
    value = "false"
  }
  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }

  depends_on = [
    module.irsa_ca,
    kubernetes_service_account.ca_sa
  ]

  wait            = true
  timeout         = 600
  cleanup_on_fail = true
}