# MTKC POC EKS - Terraform Outputs

# ==============================================================================
# CLUSTER-A (us-east-1)
# ==============================================================================

output "cluster_a_vpc_id" {
  description = "cluster-a VPC ID"
  value       = module.vpc_a.vpc_id
}

output "cluster_a_private_subnet_ids" {
  description = "cluster-a private subnet IDs"
  value       = module.vpc_a.private_subnet_ids
}

output "cluster_a_public_subnet_ids" {
  description = "cluster-a public subnet IDs"
  value       = module.vpc_a.public_subnet_ids
}

output "cluster_a_name" {
  description = "cluster-a EKS cluster name"
  value       = module.eks_a.cluster_name
}

output "cluster_a_endpoint" {
  description = "cluster-a EKS API endpoint"
  value       = module.eks_a.cluster_endpoint
}

output "cluster_a_get_credentials" {
  description = "Command to configure kubectl for cluster-a"
  value       = "aws eks update-kubeconfig --region ${var.cluster_a_region} --name ${module.eks_a.cluster_name}"
}

output "cluster_a_oidc_issuer_url" {
  description = "cluster-a OIDC issuer URL"
  value       = module.eks_a.oidc_issuer_url
}

output "cluster_a_lb_controller_role_arn" {
  description = "cluster-a AWS Load Balancer Controller IAM role ARN"
  value       = module.iam_lb_controller_a.lb_controller_role_arn
}

output "cluster_a_alb_dns_name" {
  description = "cluster-a Application Load Balancer DNS name"
  value       = try(module.alb_a[0].alb_dns_name, null)
}

output "cluster_a_alb_target_group_arn" {
  description = "cluster-a ALB target group ARN"
  value       = var.create_alb ? (var.backend_https_enabled ? try(module.alb_a[0].target_group_https_arn, null) : try(module.alb_a[0].target_group_http_arn, null)) : null
}

output "cluster_a_argocd_password" {
  description = "cluster-a ArgoCD admin password"
  value       = module.argocd_a.admin_password
  sensitive   = true
}

output "cluster_a_app_urls" {
  description = "cluster-a application URLs"
  value = (var.enable_https && var.create_alb) ? {
    health = "https://${module.alb_a[0].alb_dns_name}/healthz/ready"
    app1   = "https://${module.alb_a[0].alb_dns_name}/app1"
    app2   = "https://${module.alb_a[0].alb_dns_name}/app2"
  } : null
}

# ==============================================================================
# CLUSTER-B (us-west-1)
# ==============================================================================

output "cluster_b_vpc_id" {
  description = "cluster-b VPC ID"
  value       = module.vpc_b.vpc_id
}

output "cluster_b_private_subnet_ids" {
  description = "cluster-b private subnet IDs"
  value       = module.vpc_b.private_subnet_ids
}

output "cluster_b_public_subnet_ids" {
  description = "cluster-b public subnet IDs"
  value       = module.vpc_b.public_subnet_ids
}

output "cluster_b_name" {
  description = "cluster-b EKS cluster name"
  value       = module.eks_b.cluster_name
}

output "cluster_b_endpoint" {
  description = "cluster-b EKS API endpoint"
  value       = module.eks_b.cluster_endpoint
}

output "cluster_b_get_credentials" {
  description = "Command to configure kubectl for cluster-b"
  value       = "aws eks update-kubeconfig --region ${var.cluster_b_region} --name ${module.eks_b.cluster_name}"
}

output "cluster_b_oidc_issuer_url" {
  description = "cluster-b OIDC issuer URL"
  value       = module.eks_b.oidc_issuer_url
}

output "cluster_b_lb_controller_role_arn" {
  description = "cluster-b AWS Load Balancer Controller IAM role ARN"
  value       = module.iam_lb_controller_b.lb_controller_role_arn
}

output "cluster_b_alb_dns_name" {
  description = "cluster-b Application Load Balancer DNS name"
  value       = try(module.alb_b[0].alb_dns_name, null)
}

output "cluster_b_alb_target_group_arn" {
  description = "cluster-b ALB target group ARN"
  value       = var.create_alb ? (var.backend_https_enabled ? try(module.alb_b[0].target_group_https_arn, null) : try(module.alb_b[0].target_group_http_arn, null)) : null
}

output "cluster_b_argocd_password" {
  description = "cluster-b ArgoCD admin password"
  value       = module.argocd_b.admin_password
  sensitive   = true
}

output "cluster_b_app_urls" {
  description = "cluster-b application URLs"
  value = (var.enable_https && var.create_alb) ? {
    health = "https://${module.alb_b[0].alb_dns_name}/healthz/ready"
    app1   = "https://${module.alb_b[0].alb_dns_name}/app1"
    app2   = "https://${module.alb_b[0].alb_dns_name}/app2"
  } : null
}

# ==============================================================================
# HELPER COMMANDS
# ==============================================================================

output "argocd_port_forward_cluster_a" {
  description = "Access ArgoCD UI for cluster-a (run after setting kubectl context)"
  value       = "kubectl port-forward svc/argocd-server -n argocd 8080:443"
}

output "argocd_port_forward_cluster_b" {
  description = "Access ArgoCD UI for cluster-b (run after setting kubectl context)"
  value       = "kubectl port-forward svc/argocd-server -n argocd 8081:443"
}

output "register_nlb_command" {
  description = "Run post-deployment script to register NLB IPs with ALB target group"
  value       = "./scripts/06-register-nlb-with-alb.sh"
}
