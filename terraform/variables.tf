# MTKC POC EKS - Terraform Variables
# @author Shanaka Jayasundera - shanakaj@gmail.com

# AWS Region
variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "poc"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "mtkc"
}

# Network
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones"
  type        = number
  default     = 2
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

# EKS Configuration
variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "eks_node_count" {
  description = "Number of EKS system nodes"
  type        = number
  default     = 2
}

variable "eks_node_instance_type" {
  description = "Instance type for EKS system nodes"
  type        = string
  default     = "t3.medium"
}

# User Node Pool (optional)
variable "enable_user_node_pool" {
  description = "Enable separate user node pool"
  type        = bool
  default     = false
}

variable "user_node_count" {
  description = "Number of user nodes"
  type        = number
  default     = 2
}

variable "user_node_instance_type" {
  description = "Instance type for user nodes"
  type        = string
  default     = "t3.medium"
}

# EKS Autoscaling
variable "enable_eks_autoscaling" {
  description = "Enable EKS cluster autoscaler"
  type        = bool
  default     = false
}

variable "system_node_min_count" {
  description = "Minimum number of system nodes (when autoscaling enabled)"
  type        = number
  default     = 1
}

variable "system_node_max_count" {
  description = "Maximum number of system nodes (when autoscaling enabled)"
  type        = number
  default     = 3
}

variable "user_node_min_count" {
  description = "Minimum number of user nodes (when autoscaling enabled)"
  type        = number
  default     = 1
}

variable "user_node_max_count" {
  description = "Maximum number of user nodes (when autoscaling enabled)"
  type        = number
  default     = 5
}

# EKS Logging
variable "enable_logging" {
  description = "Enable EKS control plane logging"
  type        = bool
  default     = false
}

# TLS Configuration
variable "enable_https" {
  description = "Enable HTTPS on ALB"
  type        = bool
  default     = true
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for ALB HTTPS listener"
  type        = string
  default     = ""
}

variable "backend_https_enabled" {
  description = "Enable HTTPS for backend (Istio Gateway)"
  type        = bool
  default     = true
}

# ArgoCD Configuration
variable "argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "5.51.6"
}

variable "argocd_service_type" {
  description = "ArgoCD server service type (LoadBalancer or ClusterIP)"
  type        = string
  default     = "LoadBalancer"
}

# AWS API Gateway Configuration (equivalent to Azure APIM)
variable "enable_api_gateway" {
  description = "Enable AWS API Gateway for API traffic (equivalent to Azure APIM)"
  type        = bool
  default     = false
}

variable "api_gateway_certificate_arn" {
  description = "ACM certificate ARN for API Gateway custom domain (optional)"
  type        = string
  default     = ""
}

variable "api_gateway_custom_domain" {
  description = "Custom domain for API Gateway (optional, e.g., api.example.com)"
  type        = string
  default     = ""
}

variable "enable_api_gateway_logging" {
  description = "Enable CloudWatch logging for API Gateway"
  type        = bool
  default     = true
}

# Tags
variable "tags" {
  description = "Tags for all resources"
  type        = map(string)
  default = {
    Project   = "MTKC-POC"
    Purpose   = "Gateway-API-EKS-Integration"
    ManagedBy = "Terraform"
  }
}
