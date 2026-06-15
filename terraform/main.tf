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
#   - API Gateway Foundations (VPCLink, API, Stage)
#
# Layer 3: EKS Customizations (ArgoCD)
#   - Istio Ambient Mesh (base, istiod, cni, ztunnel)
#   - Namespaces with ambient labels
#   - Gateway and HTTPRoutes
#
# Layer 4: Application Deployment (ArgoCD)
#   - Sample Applications
#   - App-specific API Gateway routes and integrations (via ACK CRDs)

locals {
  name_prefix  = "${var.project_name}-${var.environment}"
  cluster_name = "eks-${local.name_prefix}"
}

# ==============================================================================
# LAYER 1: CLOUD FOUNDATIONS
# ==============================================================================

# VPC Module - Network infrastructure
module "vpc" {
  source = "./modules/vpc"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  cluster_name       = local.cluster_name
  enable_nat_gateway = var.enable_nat_gateway
  tags               = var.tags
}

# ==============================================================================
# LAYER 2: BASE EKS CLUSTER SETUP
# ==============================================================================

# IAM Module - Cluster and Node roles
module "iam" {
  source = "./modules/iam"

  name_prefix = local.name_prefix
  tags        = var.tags
}

# EKS Module - Kubernetes cluster
module "eks" {
  source = "./modules/eks"

  name_prefix        = local.name_prefix
  cluster_name       = local.cluster_name
  kubernetes_version = var.kubernetes_version
  cluster_role_arn   = module.iam.cluster_role_arn
  node_role_arn      = module.iam.node_role_arn

  # Use private subnets for cluster, private for nodes
  subnet_ids      = concat(module.vpc.public_subnet_ids, module.vpc.private_subnet_ids)
  node_subnet_ids = module.vpc.private_subnet_ids

  # System Node Pool
  system_node_count         = var.eks_node_count
  system_node_instance_type = var.eks_node_instance_type
  system_node_min_count     = var.system_node_min_count
  system_node_max_count     = var.system_node_max_count

  # User Node Pool (optional)
  enable_user_node_pool   = var.enable_user_node_pool
  user_node_count         = var.user_node_count
  user_node_instance_type = var.user_node_instance_type
  user_node_min_count     = var.user_node_min_count
  user_node_max_count     = var.user_node_max_count

  # Autoscaling
  enable_autoscaling = var.enable_eks_autoscaling

  # Logging
  enable_logging = var.enable_logging

  tags = var.tags
}

# IAM for AWS Load Balancer Controller (IRSA)
module "iam_lb_controller" {
  source = "./modules/iam"

  name_prefix               = "${local.name_prefix}-lb"
  create_lb_controller_role = true
  oidc_provider_arn         = module.eks.oidc_provider_arn
  oidc_provider_url         = module.eks.oidc_provider_url
  tags                      = var.tags
}

# Application Load Balancer - External entry point
module "alb" {
  count  = var.create_alb ? 1 : 0
  source = "./modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = var.vpc_cidr
  public_subnet_ids = module.vpc.public_subnet_ids

  # HTTPS/TLS
  enable_https          = var.enable_https
  certificate_arn       = var.acm_certificate_arn
  backend_https_enabled = var.backend_https_enabled

  # Health check
  health_check_path = "/healthz/ready"

  tags = var.tags
}

# AWS Load Balancer Controller - Manages NLB/ALB in K8s
module "lb_controller" {
  source = "./modules/lb-controller"

  cluster_name       = module.eks.cluster_name
  iam_role_arn       = module.iam_lb_controller.lb_controller_role_arn
  region             = var.region
  vpc_id             = module.vpc.vpc_id
  cluster_dependency = module.eks.cluster_name
}

# ArgoCD - GitOps continuous delivery
# Note: ArgoCD depends on LB controller to avoid webhook errors during deployment
module "argocd" {
  source = "./modules/argocd"

  argocd_version           = var.argocd_version
  service_type             = var.argocd_service_type
  insecure_mode            = true
  cluster_dependency       = module.eks.cluster_name
  lb_controller_dependency = module.lb_controller.release_name
}

# IAM for ACK API Gateway v2 Controller (IRSA)
module "iam_ack_apigatewayv2" {
  count  = var.enable_api_gateway ? 1 : 0
  source = "./modules/iam"

  name_prefix                  = "${local.name_prefix}-ack-apigw"
  create_ack_apigatewayv2_role = true
  oidc_provider_arn            = module.eks.oidc_provider_arn
  oidc_provider_url            = module.eks.oidc_provider_url
  tags                         = var.tags
}

# API Gateway Foundations - VPCLink, API, Stage
# App-specific routes/integrations are managed by ArgoCD via ACK CRDs
module "api_gateway" {
  count  = var.enable_api_gateway ? 1 : 0
  source = "./modules/api-gateway"

  name_prefix        = local.name_prefix
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = var.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids

  # Custom domain (optional)
  custom_domain   = var.api_gateway_custom_domain
  certificate_arn = var.api_gateway_certificate_arn

  # Logging
  enable_access_logs = var.enable_api_gateway_logging

  tags = var.tags
}
