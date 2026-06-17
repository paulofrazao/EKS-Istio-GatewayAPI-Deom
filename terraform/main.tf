# MTKC POC EKS - Main Terraform Configuration
# @author Shanaka Jayasundera - shanakaj@gmail.com
#
# Architecture Layers:
# ===================
# Layer 1: Cloud Foundations (Terraform)
#   - VPC, Subnets, NAT Gateway, Internet Gateway
#
# Layer 2: Base EKS Cluster Setup (Terraform)
#   - EKS Cluster, Node Groups, OIDC Provider
#   - IAM Roles (Cluster, Node, LB Controller, ACK)
#   - ArgoCD Installation
#   - AWS Load Balancer Controller
#   - ALB (External Load Balancer)
#
# Layer 3: EKS Customizations (ArgoCD)
#   - Istio Ambient Mesh (base, istiod, cni, ztunnel)
#   - Namespaces with ambient labels
#   - Gateway and HTTPRoutes
#
# Layer 4: Application Deployment (ArgoCD)
#   - Sample Applications

locals {
  name_prefix_a  = "${var.project_name}-${var.environment}-a"
  name_prefix_b  = "${var.project_name}-${var.environment}-b"
  cluster_name_a = "cluster-a"
  cluster_name_b = "cluster-b"
}

# ==============================================================================
# CLUSTER-A (us-east-1)
# ==============================================================================

# --- Layer 1: Cloud Foundations ---

module "vpc_a" {
  source = "./modules/vpc"

  providers = {
    aws = aws.us_east_1
  }

  name_prefix        = local.name_prefix_a
  vpc_cidr           = var.cluster_a_vpc_cidr
  az_count           = var.az_count
  cluster_name       = local.cluster_name_a
  enable_nat_gateway = var.enable_nat_gateway
  tags               = var.tags
}

# --- Layer 2: Base EKS Cluster Setup ---

module "iam_a" {
  source = "./modules/iam"

  providers = {
    aws = aws.us_east_1
  }

  name_prefix = local.name_prefix_a
  tags        = var.tags
}

module "eks_a" {
  source = "./modules/eks"

  providers = {
    aws = aws.us_east_1
    tls = tls
  }

  name_prefix        = local.name_prefix_a
  cluster_name       = local.cluster_name_a
  kubernetes_version = var.kubernetes_version
  cluster_role_arn   = module.iam_a.cluster_role_arn
  node_role_arn      = module.iam_a.node_role_arn

  subnet_ids      = concat(module.vpc_a.public_subnet_ids, module.vpc_a.private_subnet_ids)
  node_subnet_ids = module.vpc_a.private_subnet_ids

  system_node_count         = var.eks_node_count
  system_node_instance_type = var.eks_node_instance_type
  system_node_min_count     = var.system_node_min_count
  system_node_max_count     = var.system_node_max_count

  enable_user_node_pool   = var.enable_user_node_pool
  user_node_count         = var.user_node_count
  user_node_instance_type = var.user_node_instance_type
  user_node_min_count     = var.user_node_min_count
  user_node_max_count     = var.user_node_max_count

  enable_autoscaling = var.enable_eks_autoscaling
  enable_logging     = var.enable_logging

  tags = var.tags
}

module "iam_lb_controller_a" {
  source = "./modules/iam"

  providers = {
    aws = aws.us_east_1
  }

  name_prefix               = "${local.name_prefix_a}-lb"
  create_lb_controller_role = true
  oidc_provider_arn         = module.eks_a.oidc_provider_arn
  oidc_provider_url         = module.eks_a.oidc_provider_url
  tags                      = var.tags
}

module "alb_a" {
  count  = var.create_alb ? 1 : 0
  source = "./modules/alb"

  providers = {
    aws = aws.us_east_1
  }

  name_prefix       = local.name_prefix_a
  vpc_id            = module.vpc_a.vpc_id
  vpc_cidr          = var.cluster_a_vpc_cidr
  public_subnet_ids = module.vpc_a.public_subnet_ids

  enable_https          = var.enable_https
  certificate_arn       = var.cluster_a_acm_certificate_arn
  backend_https_enabled = var.backend_https_enabled

  health_check_path = "/healthz/ready"

  tags = var.tags
}

module "lb_controller_a" {
  source = "./modules/lb-controller"

  providers = {
    helm = helm.cluster_a
  }

  cluster_name       = module.eks_a.cluster_name
  iam_role_arn       = module.iam_lb_controller_a.lb_controller_role_arn
  region             = var.cluster_a_region
  vpc_id             = module.vpc_a.vpc_id
  cluster_dependency = module.eks_a.cluster_name
}

module "argocd_a" {
  source = "./modules/argocd"

  providers = {
    helm       = helm.cluster_a
    kubernetes = kubernetes.cluster_a
  }

  argocd_version           = var.argocd_version
  service_type             = var.argocd_service_type
  insecure_mode            = true
  cluster_dependency       = module.eks_a.cluster_name
  lb_controller_dependency = module.lb_controller_a.release_name
}

# API Gateway (cluster-a only, optional)
module "iam_ack_apigatewayv2_a" {
  count  = var.enable_api_gateway ? 1 : 0
  source = "./modules/iam"

  providers = {
    aws = aws.us_east_1
  }

  name_prefix                  = "${local.name_prefix_a}-ack-apigw"
  create_ack_apigatewayv2_role = true
  oidc_provider_arn            = module.eks_a.oidc_provider_arn
  oidc_provider_url            = module.eks_a.oidc_provider_url
  tags                         = var.tags
}

module "api_gateway_a" {
  count  = var.enable_api_gateway ? 1 : 0
  source = "./modules/api-gateway"

  providers = {
    aws = aws.us_east_1
  }

  name_prefix        = local.name_prefix_a
  vpc_id             = module.vpc_a.vpc_id
  vpc_cidr           = var.cluster_a_vpc_cidr
  private_subnet_ids = module.vpc_a.private_subnet_ids

  custom_domain   = var.api_gateway_custom_domain
  certificate_arn = var.api_gateway_certificate_arn

  enable_access_logs = var.enable_api_gateway_logging

  tags = var.tags
}

# ==============================================================================
# CLUSTER-B (us-west-1)
# ==============================================================================

# --- Layer 1: Cloud Foundations ---

module "vpc_b" {
  source = "./modules/vpc"

  providers = {
    aws = aws.us_west_1
  }

  name_prefix        = local.name_prefix_b
  vpc_cidr           = var.cluster_b_vpc_cidr
  az_count           = var.az_count
  cluster_name       = local.cluster_name_b
  enable_nat_gateway = var.enable_nat_gateway
  tags               = var.tags
}

# --- Layer 2: Base EKS Cluster Setup ---

module "iam_b" {
  source = "./modules/iam"

  providers = {
    aws = aws.us_west_1
  }

  name_prefix = local.name_prefix_b
  tags        = var.tags
}

module "eks_b" {
  source = "./modules/eks"

  providers = {
    aws = aws.us_west_1
    tls = tls
  }

  name_prefix        = local.name_prefix_b
  cluster_name       = local.cluster_name_b
  kubernetes_version = var.kubernetes_version
  cluster_role_arn   = module.iam_b.cluster_role_arn
  node_role_arn      = module.iam_b.node_role_arn

  subnet_ids      = concat(module.vpc_b.public_subnet_ids, module.vpc_b.private_subnet_ids)
  node_subnet_ids = module.vpc_b.private_subnet_ids

  system_node_count         = var.eks_node_count
  system_node_instance_type = var.eks_node_instance_type
  system_node_min_count     = var.system_node_min_count
  system_node_max_count     = var.system_node_max_count

  enable_user_node_pool   = var.enable_user_node_pool
  user_node_count         = var.user_node_count
  user_node_instance_type = var.user_node_instance_type
  user_node_min_count     = var.user_node_min_count
  user_node_max_count     = var.user_node_max_count

  enable_autoscaling = var.enable_eks_autoscaling
  enable_logging     = var.enable_logging

  tags = var.tags
}

module "iam_lb_controller_b" {
  source = "./modules/iam"

  providers = {
    aws = aws.us_west_1
  }

  name_prefix               = "${local.name_prefix_b}-lb"
  create_lb_controller_role = true
  oidc_provider_arn         = module.eks_b.oidc_provider_arn
  oidc_provider_url         = module.eks_b.oidc_provider_url
  tags                      = var.tags
}

module "alb_b" {
  count  = var.create_alb ? 1 : 0
  source = "./modules/alb"

  providers = {
    aws = aws.us_west_1
  }

  name_prefix       = local.name_prefix_b
  vpc_id            = module.vpc_b.vpc_id
  vpc_cidr          = var.cluster_b_vpc_cidr
  public_subnet_ids = module.vpc_b.public_subnet_ids

  enable_https          = var.enable_https
  certificate_arn       = var.cluster_b_acm_certificate_arn
  backend_https_enabled = var.backend_https_enabled

  health_check_path = "/healthz/ready"

  tags = var.tags
}

module "lb_controller_b" {
  source = "./modules/lb-controller"

  providers = {
    helm = helm.cluster_b
  }

  cluster_name       = module.eks_b.cluster_name
  iam_role_arn       = module.iam_lb_controller_b.lb_controller_role_arn
  region             = var.cluster_b_region
  vpc_id             = module.vpc_b.vpc_id
  cluster_dependency = module.eks_b.cluster_name
}

module "argocd_b" {
  source = "./modules/argocd"

  providers = {
    helm       = helm.cluster_b
    kubernetes = kubernetes.cluster_b
  }

  argocd_version           = var.argocd_version
  service_type             = var.argocd_service_type
  insecure_mode            = true
  cluster_dependency       = module.eks_b.cluster_name
  lb_controller_dependency = module.lb_controller_b.release_name
}
