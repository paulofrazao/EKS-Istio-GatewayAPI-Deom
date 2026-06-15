# MTKC POC EKS - Terraform Outputs
# @author Shanaka Jayasundera - shanakaj@gmail.com

# ==============================================================================
# LAYER 1: CLOUD FOUNDATIONS
# ==============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

# ==============================================================================
# LAYER 2: BASE EKS CLUSTER SETUP
# ==============================================================================

# EKS Cluster
output "eks_cluster_name" {
  description = "EKS Cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_get_credentials_command" {
  description = "Command to get EKS credentials"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "eks_oidc_issuer_url" {
  description = "EKS OIDC issuer URL for workload identity"
  value       = module.eks.oidc_issuer_url
}

# AWS Load Balancer Controller
output "lb_controller_role_arn" {
  description = "AWS Load Balancer Controller IAM role ARN"
  value       = module.iam_lb_controller.lb_controller_role_arn
}

# ALB Outputs
output "alb_name" {
  description = "Application Load Balancer name"
  value       = try(module.alb[0].alb_name, null)
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = try(module.alb[0].alb_dns_name, null)
}

output "alb_target_group_arn" {
  description = "ALB target group ARN (for backend pool update)"
  value       = var.create_alb ? (var.backend_https_enabled ? try(module.alb[0].target_group_https_arn, null) : try(module.alb[0].target_group_http_arn, null)) : null
}

# ArgoCD Outputs
output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = module.argocd.namespace
}

output "argocd_admin_password" {
  description = "ArgoCD admin password (retrieve with: terraform output -raw argocd_admin_password)"
  value       = module.argocd.admin_password
  sensitive   = true
}

output "argocd_url" {
  description = "ArgoCD URL (access via port-forward: kubectl port-forward svc/argocd-server -n argocd 8080:443)"
  value       = "https://localhost:8080"
}

# NOTE: API Gateway (ACK) is optional and disabled by default
# The ALB + Internal NLB pattern is the primary ingress path

# ==============================================================================
# APPLICATION URLS
# ==============================================================================

output "app_urls_https" {
  description = "HTTPS URLs for applications"
  value = (var.enable_https && var.create_alb) ? {
    health = "https://${module.alb[0].alb_dns_name}/healthz/ready"
    app1   = "https://${module.alb[0].alb_dns_name}/app1"
    app2   = "https://${module.alb[0].alb_dns_name}/app2"
  } : null
}

output "app_urls_http" {
  description = "HTTP URLs for applications (redirects to HTTPS when enabled)"
  value = var.create_alb ? {
    health = "http://${module.alb[0].alb_dns_name}/healthz/ready"
    app1   = "http://${module.alb[0].alb_dns_name}/app1"
    app2   = "http://${module.alb[0].alb_dns_name}/app2"
  } : null
}

output "https_enabled" {
  description = "Whether HTTPS is enabled"
  value       = var.enable_https
}

# ==============================================================================
# HELPER COMMANDS
# ==============================================================================

output "register_nlb_command" {
  description = "Run post-deployment script to register NLB with ALB"
  value       = "./scripts/06-register-nlb-with-alb.sh"
}

output "argocd_port_forward_command" {
  description = "Command to access ArgoCD UI via port-forward"
  value       = "kubectl port-forward svc/argocd-server -n argocd 8080:443"
}
